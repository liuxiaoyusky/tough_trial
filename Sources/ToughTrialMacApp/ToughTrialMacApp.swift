import SwiftUI
import AppKit
import ToughTrialAppShared

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: MacAppModel?
    private var terminationPending = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        if let window = NSApp.windows.first(where: { $0.attachedSheet != nil }) {
            window.makeKeyAndOrderFront(nil)
            let alert = NSAlert()
            alert.messageText = "请先完成或取消当前编辑"
            alert.informativeText = "打开的编辑窗口可能有未保存内容。完成后再退出，已保存的资料不会丢失。"
            alert.addButton(withTitle: "返回编辑")
            alert.runModal()
            return .terminateCancel
        }
        terminationPending = true
        Task { @MainActor in
            let saved = await model.shutdown()
            terminationPending = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.preserve() != false }
    func observeMainWindow(_ window: NSWindow) {
        // System panels own their delegates and must retain them across dismissal.
        guard !(window is NSPanel), window.identifier?.rawValue == "workspace" else { return }
        window.delegate = self
    }
}

@main
struct ToughTrialMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @State private var model: MacAppModel?
    @State private var startupError: String?

    var body: some Scene {
        Window("Tough Trial", id: "workspace") {
            Group {
                if let model {
                    MacRootView(model: model, store: model.store)
                } else if let startupError {
                    ContentUnavailableView("本机资料暂时无法打开", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(startupError + "\n原始文件未被重置，请恢复文件后重新启动。"))
                } else { ProgressView().task { loadWorkspace() } }
            }
            .frame(minWidth: 1100, minHeight: 700)
            .background(V2Theme.page)
            .preferredColorScheme(.light)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard let window = note.object as? NSWindow else { return }
                delegate.observeMainWindow(window)
            }
        }
        .defaultSize(width: 1220, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增任务") { model?.select(.tasks); model?.workspace.beginNew() }.keyboardShortcut("n")
                    .disabled(model == nil)
            }
            CommandGroup(after: .newItem) {
                Button("保存任务") { model?.workspace.save() }.keyboardShortcut("s")
                    .disabled(model == nil)
            }
        }
    }

    private func loadWorkspace() {
        do {
            let directory: URL
            #if DEBUG
            let verificationPath = Bundle.main.object(forInfoDictionaryKey: "ToughTrialVerificationDirectory") as? String
            #else
            let verificationPath: String? = nil
            #endif
            if let path = ProcessInfo.processInfo.environment["TOUGH_TRIAL_MAC_DATA_DIR"] ?? verificationPath {
                directory = URL(fileURLWithPath: path, isDirectory: true)
            } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-test-host-\(ProcessInfo.processInfo.processIdentifier)")
            } else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true).appendingPathComponent("ToughTrialMac", isDirectory: true)
            }
            let loaded = try MacAppModel(directory: directory)
            model = loaded
            delegate.model = loaded
        } catch { startupError = "请检查资料文件格式与访问权限。" }
    }
}
