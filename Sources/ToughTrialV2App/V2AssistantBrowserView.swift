import SwiftUI
import Combine
import ToughTrialV2Core
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import WebKit

struct V2AssistantBrowserKey: Hashable, Identifiable {
    let sessionID: String
    let browserID: String

    var id: String { "\(sessionID)::\(browserID)" }
}

struct V2AssistantBrowserPresentation: Identifiable, Equatable {
    let sessionID: String
    let browserID: String
    let source: V2WebSource

    var id: String { "\(sessionID)::\(browserID)" }

    var key: V2AssistantBrowserKey {
        V2AssistantBrowserKey(sessionID: sessionID, browserID: browserID)
    }
}

struct V2AssistantBrowserNavigationUpdate: Equatable {
    let browserID: String
    let lastURL: URL
    let navigationHistory: [URL]
    let scrollOffsetY: Double
}

@MainActor
final class V2AssistantBrowserRegistry: ObservableObject {
    @Published private(set) var fullscreenKey: V2AssistantBrowserKey?

    private var controllers: [V2AssistantBrowserKey: V2AssistantBrowserController] = [:]

    func controller(
        for key: V2AssistantBrowserKey,
        state: V2BrowserSessionState,
        onNavigationChange: @escaping @MainActor (V2AssistantBrowserNavigationUpdate) -> Void
    ) -> V2AssistantBrowserController {
        if let controller = controllers[key], controller.isModuleActive {
            return controller
        }
        controllers.removeValue(forKey: key)?.invalidate()

        let controller = V2AssistantBrowserController(
            state: state,
            onNavigationChange: onNavigationChange
        )
        controllers[key] = controller
        return controller
    }

    @discardableResult
    func claimFullscreen(_ key: V2AssistantBrowserKey) -> Bool {
        guard fullscreenKey == nil || fullscreenKey == key else { return false }
        fullscreenKey = key
        return true
    }

    func releaseFullscreen(_ key: V2AssistantBrowserKey) {
        guard fullscreenKey == key else { return }
        fullscreenKey = nil
    }

    func prune(keeping keys: Set<V2AssistantBrowserKey>) {
        let staleKeys = Set(controllers.keys).subtracting(keys)
        for key in staleKeys {
            controllers.removeValue(forKey: key)?.invalidate()
        }
        if let fullscreenKey, !keys.contains(fullscreenKey) {
            self.fullscreenKey = nil
        }
    }
}

@MainActor
final class V2AssistantBrowserController: NSObject, ObservableObject, WKNavigationDelegate,
    WKUIDelegate {
    let webView: WKWebView

    @Published private(set) var navigationError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false

    private(set) var state: V2BrowserSessionState
    private let onNavigationChange: @MainActor (V2AssistantBrowserNavigationUpdate) -> Void
    private var hasRestoredScrollOffset = false
    private var scrollRestoreAttempt = 0
    private let maximumScrollRestoreAttempts = 8
    private let moduleTicket: V2ModuleTicket?
    private var moduleObservation: AnyCancellable?
#if os(macOS)
    private static let scrollMessageName = "v2AssistantBrowserScroll"
    private static let scrollObservationScript = """
    (() => {
        const handler = window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.v2AssistantBrowserScroll;
        if (!handler) { return; }
        const report = () => handler.postMessage(window.scrollY || 0);
        window.addEventListener('scroll', report, { passive: true });
        report();
    })();
    """
    private var pendingScrollPersistence: DispatchWorkItem?
#endif
    var isModuleActive: Bool {
        guard let moduleTicket else { return false }
        return (try? V2PluginStore.shared.validate(moduleTicket)) != nil
    }

    init(
        state: V2BrowserSessionState,
        onNavigationChange: @escaping @MainActor (V2AssistantBrowserNavigationUpdate) -> Void
    ) {
        self.state = state
        self.onNavigationChange = onNavigationChange
        self.moduleTicket = try? V2PluginStore.shared.ticket(["web"])

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
#if os(iOS)
        webView.scrollView.delegate = self
#elseif os(macOS)
        configuration.userContentController.add(self, name: Self.scrollMessageName)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.scrollObservationScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
#endif
        webView.allowsBackForwardNavigationGestures = true
#if os(iOS)
        webView.backgroundColor = UIColor(V2Theme.ColorRole.surface)
        webView.isOpaque = false
#elseif os(macOS)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
#endif
        moduleObservation = NotificationCenter.default.publisher(for: .v2ModulesChanged).sink { [weak self] _ in
            guard let self, !self.isModuleActive else { return }
            self.webView.stopLoading()
            self.isLoading = false
            self.navigationError = "网页功能已停用，历史链接仍保留。"
        }
        loadInitialPageIfNeeded()
    }

    var currentURL: URL {
        webView.url ?? state.lastURL
    }

    var hostName: String {
        currentURL.host ?? currentURL.absoluteString
    }

    var isSecureConnection: Bool {
        currentURL.scheme?.lowercased() == "https"
    }

    func goBack() {
        guard isModuleActive, webView.canGoBack else { return }
        webView.goBack()
    }

    func retry() {
        guard isModuleActive else { navigationError = "网页功能已停用，请重新开启后打开链接。"; return }
        navigationError = nil
        guard Self.isSupportedWebURL(state.lastURL) else {
            recordBlockedNavigation()
            return
        }
        isLoading = true
        if webView.url == nil {
            webView.load(URLRequest(url: state.lastURL))
        } else {
            webView.reload()
        }
    }

    func openExternal() {
        guard isModuleActive, Self.isSupportedWebURL(currentURL) else { return }
#if os(iOS)
        UIApplication.shared.open(currentURL)
#elseif os(macOS)
        NSWorkspace.shared.open(currentURL)
#endif
    }

    func invalidate() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
#if os(iOS)
        webView.scrollView.delegate = nil
#elseif os(macOS)
        pendingScrollPersistence?.cancel()
        pendingScrollPersistence = nil
        persistState()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.scrollMessageName)
#endif
        moduleObservation?.cancel()
        moduleObservation = nil
    }

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation?
    ) {
        isLoading = true
        navigationError = nil
        refreshNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation?
    ) {
        guard isModuleActive else { webView.stopLoading(); isLoading = false; return }
        isLoading = false
        navigationError = nil

        if let url = webView.url {
            state.lastURL = url
        }
        state.navigationHistory = webView.backForwardList.backList.map(\.url)
            + [state.lastURL]
            + webView.backForwardList.forwardList.map(\.url)
        persistState()
        refreshNavigationState()
        restoreScrollOffsetIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard isModuleActive else { decisionHandler(.cancel); return }
        let isTopLevel = navigationAction.targetFrame == nil
            || navigationAction.targetFrame?.isMainFrame == true
        guard isTopLevel else {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url, Self.isSupportedWebURL(url) else {
            recordBlockedNavigation()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard isModuleActive, navigationAction.targetFrame == nil,
              let url = navigationAction.request.url,
              Self.isSupportedWebURL(url) else {
            return nil
        }
        webView.load(navigationAction.request)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        recordFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        recordFailure(error)
    }

#if os(macOS)
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.scrollMessageName,
              let offset = message.body as? NSNumber
        else {
            return
        }
        state.scrollOffsetY = max(0, offset.doubleValue)
        scheduleScrollPersistence()
    }
#endif

#if os(iOS)
    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate { persistScrollOffset() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        persistScrollOffset()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        persistScrollOffset()
    }
#endif

    private func loadInitialPageIfNeeded() {
        guard isModuleActive else { navigationError = "网页功能已停用，历史链接仍保留。"; return }
        guard webView.url == nil, !isLoading else { return }
        guard Self.isSupportedWebURL(state.lastURL) else {
            recordBlockedNavigation()
            return
        }
        isLoading = true
        webView.load(URLRequest(url: state.lastURL))
    }

    private func restoreScrollOffsetIfNeeded() {
        guard !hasRestoredScrollOffset else { return }
        let offset = max(0, state.scrollOffsetY)
        guard offset > 0 else {
            hasRestoredScrollOffset = true
            return
        }

#if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) { [weak self] in
            guard let self else { return }
            let scrollView = self.webView.scrollView
            let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let canReachTarget = maximumOffset + 1 >= offset
            let reachedAttemptLimit = self.scrollRestoreAttempt >= self.maximumScrollRestoreAttempts
            guard canReachTarget || reachedAttemptLimit else {
                self.scrollRestoreAttempt += 1
                self.restoreScrollOffsetIfNeeded()
                return
            }
            self.webView.scrollView.setContentOffset(
                CGPoint(x: 0, y: min(offset, maximumOffset)),
                animated: false
            )
            self.hasRestoredScrollOffset = true
        }
#elseif os(macOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) { [weak self] in
            guard let self else { return }
            let escapedOffset = String(format: "%.3f", offset)
            self.webView.evaluateJavaScript(
                "window.scrollTo(0, Math.max(0, \(escapedOffset))); window.scrollY || 0;"
            ) { [weak self] result, _ in
                guard let self else { return }
                let actualOffset = (result as? NSNumber)?.doubleValue ?? 0
                let reachedTarget = actualOffset + 1 >= offset
                let reachedAttemptLimit = self.scrollRestoreAttempt >= self.maximumScrollRestoreAttempts
                guard reachedTarget || reachedAttemptLimit else {
                    self.scrollRestoreAttempt += 1
                    self.restoreScrollOffsetIfNeeded()
                    return
                }
                self.hasRestoredScrollOffset = true
            }
        }
#endif
    }

    private func persistScrollOffset() {
#if os(iOS)
        state.scrollOffsetY = max(0, webView.scrollView.contentOffset.y)
        persistState()
#elseif os(macOS)
        webView.evaluateJavaScript("window.scrollY || 0") { [weak self] result, _ in
            guard let self, let offset = result as? NSNumber else { return }
            self.state.scrollOffsetY = max(0, offset.doubleValue)
            self.persistState()
        }
#endif
    }

#if os(macOS)
    private func scheduleScrollPersistence() {
        pendingScrollPersistence?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScrollPersistence = nil
            self.persistState()
        }
        pendingScrollPersistence = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
    }
#endif

    private func persistState() {
        guard isModuleActive else { return }
        state.updatedAt = Date()
        onNavigationChange(
            V2AssistantBrowserNavigationUpdate(
                browserID: state.id,
                lastURL: state.lastURL,
                navigationHistory: state.navigationHistory,
                scrollOffsetY: state.scrollOffsetY
            )
        )
    }

    private func recordFailure(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        isLoading = false
        navigationError = String(error.localizedDescription.prefix(240))
        refreshNavigationState()
    }

    private func refreshNavigationState() {
        let nextCanGoBack = webView.canGoBack
        if canGoBack != nextCanGoBack {
            canGoBack = nextCanGoBack
        }
    }

    private func recordBlockedNavigation() {
        isLoading = false
        navigationError = "为保护当前会话，只能打开 HTTP 或 HTTPS 网页。"
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }
}

#if os(iOS)
extension V2AssistantBrowserController: UIScrollViewDelegate {}
#elseif os(macOS)
extension V2AssistantBrowserController: WKScriptMessageHandler {}
#endif

#if os(iOS)
struct V2AssistantWebViewRepresentable: UIViewRepresentable {
    @ObservedObject var controller: V2AssistantBrowserController

    func makeUIView(context: Context) -> V2AssistantWebViewHostView {
        let host = V2AssistantWebViewHostView()
        host.attach(controller.webView)
        return host
    }

    func updateUIView(_ host: V2AssistantWebViewHostView, context: Context) {
        host.attach(controller.webView)
    }

    static func dismantleUIView(
        _ host: V2AssistantWebViewHostView,
        coordinator: ()
    ) {
        host.detachIfAttached()
    }
}

final class V2AssistantWebViewHostView: UIView {
    private weak var attachedWebView: WKWebView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(V2Theme.ColorRole.surface)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ webView: WKWebView) {
        guard webView.superview !== self else {
            attachedWebView = webView
            return
        }

        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        attachedWebView = webView
    }

    func detachIfAttached() {
        guard let attachedWebView, attachedWebView.superview === self else { return }
        attachedWebView.removeFromSuperview()
        self.attachedWebView = nil
    }
}
#elseif os(macOS)
struct V2AssistantWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: V2AssistantBrowserController

    func makeNSView(context: Context) -> V2AssistantWebViewHostView {
        let host = V2AssistantWebViewHostView()
        host.attach(controller.webView)
        return host
    }

    func updateNSView(_ host: V2AssistantWebViewHostView, context: Context) {
        host.attach(controller.webView)
    }

    static func dismantleNSView(
        _ host: V2AssistantWebViewHostView,
        coordinator: ()
    ) {
        host.detachIfAttached()
    }
}

final class V2AssistantWebViewHostView: NSView {
    private weak var attachedWebView: WKWebView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ webView: WKWebView) {
        guard webView.superview !== self else {
            attachedWebView = webView
            return
        }

        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        attachedWebView = webView
    }

    func detachIfAttached() {
        guard let attachedWebView, attachedWebView.superview === self else { return }
        attachedWebView.removeFromSuperview()
        self.attachedWebView = nil
    }
}
#endif

struct V2AssistantBrowserToolbar: View {
    @ObservedObject var controller: V2AssistantBrowserController
    let isFullscreen: Bool
    let onClose: (() -> Void)?
    let onFullscreen: (() -> Void)?
    let onMinimize: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let onMinimize {
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("缩小网页")
                .accessibilityIdentifier("assistant.browser.minimize")
            }

            if isFullscreen {
                Button(action: controller.goBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .disabled(!controller.canGoBack)
                .accessibilityLabel("网页后退")
                .accessibilityIdentifier("assistant.browser.back")
            }

            HStack(spacing: 5) {
                Image(systemName: controller.isSecureConnection ? "lock.fill" : "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(controller.isSecureConnection ? V2Theme.mint : V2Theme.orange)
                Text(controller.hostName)
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(V2Theme.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                controller.isSecureConnection
                    ? "安全连接，\(controller.hostName)"
                    : "未加密连接，\(controller.hostName)"
            )
            .accessibilityIdentifier("assistant.browser.domain")

            Spacer(minLength: 8)

            if isFullscreen {
                Button(action: controller.openExternal) {
                    Image(systemName: "safari")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("使用系统浏览器打开")
                .accessibilityIdentifier("assistant.browser.openExternal")
            } else {
                if let onFullscreen {
                    Button(action: onFullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("网页全屏")
                    .accessibilityIdentifier("assistant.browser.fullscreen")
                }

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("收起网页")
                    .accessibilityIdentifier("assistant.browser.close")
                }
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(V2Theme.secondary)
        .padding(.horizontal, 9)
        .frame(minHeight: 42)
        .background(V2Theme.ColorRole.surfaceRaised)
        .overlay(alignment: .bottom) {
            Divider().overlay(V2Theme.line.opacity(0.8))
        }
    }
}

struct V2AssistantBrowserFailureView: View {
    let message: String
    let onRetry: () -> Void
    let onOpenExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(V2Theme.orange)
            Text("网页暂时打不开")
                .font(V2Theme.TypeRole.labelLarge)
                .foregroundStyle(V2Theme.ink)
            Text(message)
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.secondary)
                .lineLimit(3)
            HStack(spacing: 14) {
                Button(action: onRetry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("assistant.browser.retry")

                Button(action: onOpenExternal) {
                    Label("系统浏览器", systemImage: "safari")
                }
                .accessibilityIdentifier("assistant.browser.openExternal")
            }
            .font(V2Theme.TypeRole.labelMedium)
            .foregroundStyle(V2Theme.blue)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(20)
        .background(V2Theme.ColorRole.surface)
    }
}

struct V2AssistantInlineBrowser: View {
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var registry: V2AssistantBrowserRegistry
    let sessionID: String
    let source: V2WebSource
    let state: V2BrowserSessionState
    let availableHeight: CGFloat
    let onFullscreen: (V2AssistantBrowserPresentation) -> Void

    var body: some View {
        let presentation = V2AssistantBrowserPresentation(
            sessionID: sessionID,
            browserID: state.id,
            source: source
        )
        let controller = browserController

        VStack(spacing: 0) {
            V2AssistantBrowserToolbar(
                controller: controller,
                isFullscreen: false,
                onClose: collapse,
                onFullscreen: { onFullscreen(presentation) },
                onMinimize: nil
            )

            if let error = controller.navigationError {
                V2AssistantBrowserFailureView(
                    message: error,
                    onRetry: controller.retry,
                    onOpenExternal: controller.openExternal
                )
            } else {
                ZStack(alignment: .topTrailing) {
                    V2AssistantWebViewRepresentable(controller: controller)
                        .accessibilityIdentifier("assistant.browser.inline.\(state.id)")
                    if controller.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(9)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(180, availableHeight * 0.25))
        .background(V2Theme.ColorRole.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(V2Theme.line, lineWidth: 1)
        }
    }

    private var browserController: V2AssistantBrowserController {
        registry.controller(
            for: V2AssistantBrowserKey(sessionID: sessionID, browserID: state.id),
            state: state,
            onNavigationChange: { update in
                _ = store.updateBrowserNavigation(update, sessionID: sessionID)
            }
        )
    }

    private func collapse() {
        _ = store.updateBrowserPresentation(
            browserID: state.id,
            sessionID: sessionID,
            isExpanded: false,
            isFullscreen: false
        )
    }
}

struct V2AssistantBrowserFullscreenView: View {
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var registry: V2AssistantBrowserRegistry
    let sessionID: String
    let browserID: String
    let source: V2WebSource
    let onMinimize: () -> Void
    let onDisappear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let state = browserState {
                let controller = browserController(state: state)
                V2AssistantBrowserToolbar(
                    controller: controller,
                    isFullscreen: true,
                    onClose: nil,
                    onFullscreen: nil,
                    onMinimize: onMinimize
                )

                if let error = controller.navigationError {
                    V2AssistantBrowserFailureView(
                        message: error,
                        onRetry: controller.retry,
                        onOpenExternal: controller.openExternal
                    )
                } else {
                    ZStack(alignment: .topTrailing) {
                        V2AssistantWebViewRepresentable(controller: controller)
                            .accessibilityIdentifier("assistant.browser.fullscreen")
                        if controller.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(12)
                        }
                    }
                }
            } else {
                Text("网页会话已不可用")
                    .font(V2Theme.TypeRole.bodyMedium)
                    .foregroundStyle(V2Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(V2Theme.ColorRole.surface.ignoresSafeArea())
        .onDisappear(perform: onDisappear)
    }

    private var browserState: V2BrowserSessionState? {
        store.workspace.session(id: sessionID)?.browserSessions.first { $0.id == browserID }
    }

    private func browserController(
        state: V2BrowserSessionState
    ) -> V2AssistantBrowserController {
        registry.controller(
            for: V2AssistantBrowserKey(sessionID: sessionID, browserID: browserID),
            state: state,
            onNavigationChange: { update in
                _ = store.updateBrowserNavigation(update, sessionID: sessionID)
            }
        )
    }
}
