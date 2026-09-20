import AVFoundation
import Combine
import Foundation
import Speech
import ToughTrialV2Core
import UserNotifications

#if os(iOS)
@preconcurrency import ActivityKit
import ToughTrialActivityShared
#endif

enum V2NativeCapabilityError: Error, LocalizedError {
    case notificationsDenied
    case speechDenied
    case microphoneDenied
    case speechUnavailable

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            "通知权限未开启，可以在系统设置中更改。"
        case .speechDenied:
            "语音识别权限未开启，可以在系统设置中更改。"
        case .microphoneDenied:
            "麦克风权限未开启，可以在系统设置中更改。"
        case .speechUnavailable:
            "当前设备暂时无法使用语音识别。"
        }
    }
}

@MainActor
final class V2NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAndSchedule(
        planItems: [V2PlanItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Int {
        let ticket = try V2PluginStore.shared.ticket(["tasks"])
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        try V2PluginStore.shared.validate(ticket)
        guard granted else {
            throw V2NativeCapabilityError.notificationsDenied
        }
        return try await schedule(planItems: planItems, now: now, calendar: calendar, ticket: ticket)
    }

    func scheduleIfAuthorized(
        planItems: [V2PlanItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Int {
        let ticket = try V2PluginStore.shared.ticket(["tasks"])
        let settings = await center.notificationSettings()
        try V2PluginStore.shared.validate(ticket)
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else {
            return 0
        }
        return try await schedule(planItems: planItems, now: now, calendar: calendar, ticket: ticket)
    }

    func replaceIfAuthorized(planItems: [V2PlanItem], affectedIDs: Set<String>, now: Date, calendar: Calendar) async throws {
        center.removePendingNotificationRequests(withIdentifiers: affectedIDs.map { "v2-plan-\($0)" })
        _ = try await scheduleIfAuthorized(planItems: planItems, now: now, calendar: calendar)
    }

    func cancel(planIDs: Set<String>) {
        center.removePendingNotificationRequests(withIdentifiers: planIDs.map { "v2-plan-\($0)" })
    }

    func cancelAllOwned() {
        Task {
            let pending = await center.pendingNotificationRequests()
            guard !V2PluginStore.shared.enabled("tasks") else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("v2-plan-") }.map(\.identifier))
        }
    }

    func rebuildOwned(planItems: [V2PlanItem], now: Date, calendar: Calendar) async throws {
        let ticket = try V2PluginStore.shared.ticket(["tasks"])
        let pending = await center.pendingNotificationRequests()
        try V2PluginStore.shared.validate(ticket)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("v2-plan-") }.map(\.identifier))
        let settings = await center.notificationSettings()
        try V2PluginStore.shared.validate(ticket)
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            // No future reminders means no outstanding system permission work.
            guard planItems.contains(where: { ($0.startAt ?? .distantPast) > now && $0.status != .completed && $0.status != .canceled }) else { return }
            throw V2NativeCapabilityError.notificationsDenied
        }
        _ = try await schedule(planItems: planItems, now: now, calendar: calendar, ticket: ticket)
    }

    private func schedule(
        planItems: [V2PlanItem],
        now: Date,
        calendar: Calendar,
        ticket: V2ModuleTicket
    ) async throws -> Int {
        let eligible = planItems
            .filter {
                $0.status != .canceled
                    && $0.status != .completed
                    && ($0.startAt ?? .distantPast) > now
            }
            .sorted { ($0.startAt ?? $0.date) < ($1.startAt ?? $1.date) }
            .prefix(32)

        var count = 0
        for item in eligible {
            try V2PluginStore.shared.validate(ticket)
            guard let startAt = item.startAt else { continue }
            let identifier = "v2-plan-\(item.id)"
            center.removePendingNotificationRequests(withIdentifiers: [identifier])

            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = "计划时间到了。是否开始以及做到什么程度，由你决定。"
            content.sound = .default
            content.userInfo = ["planItemID": item.id]

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: startAt
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
            )
            try await center.add(request)
            do { try V2PluginStore.shared.validate(ticket) }
            catch { center.removePendingNotificationRequests(withIdentifiers: [identifier]); throw error }
            count += 1
        }
        return count
    }
}

#if os(iOS)
@MainActor
final class V2LiveActivityService {
    func sync(session: V2ActiveSession, now: Date = Date()) async throws {
        let ticket = try V2PluginStore.shared.ticket(["tasks"])
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = V2FocusActivityAttributes.ContentState(
            title: session.title,
            isRunning: session.status == .running,
            segmentStartedAt: session.status == .running
                ? now.addingTimeInterval(-TimeInterval(session.totalElapsedSeconds))
                : nil,
            accumulatedSeconds: session.totalElapsedSeconds
        )
        if let activity = Activity<V2FocusActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == session.id
        }) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            if (try? V2PluginStore.shared.validate(ticket)) == nil { await endAll() }
            return
        }

        for activity in Activity<V2FocusActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        try V2PluginStore.shared.validate(ticket)
        _ = try Activity.request(
            attributes: V2FocusActivityAttributes(sessionID: session.id),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func endAll() async {
        for activity in Activity<V2FocusActivityAttributes>.activities {
            await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    func end(session: V2ActiveSession) async {
        let finalState = V2FocusActivityAttributes.ContentState(
            title: session.title,
            isRunning: false,
            segmentStartedAt: nil,
            accumulatedSeconds: session.totalElapsedSeconds
        )
        for activity in Activity<V2FocusActivityAttributes>.activities where
            activity.attributes.sessionID == session.id {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
#else
/// Live Activities are an iOS surface. The Mac app keeps the service type so
/// shared stores can use the same lifecycle calls while the desktop app
/// presents the running session in its own window.
@MainActor
final class V2LiveActivityService {
    func sync(session: V2ActiveSession, now: Date = Date()) async throws {}
    func endAll() async {}
    func end(session: V2ActiveSession) async {}
}
#endif

@MainActor
final class V2SpeechTranscriber: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasAudioTap = false
    private var wantsListening = false

    func toggle() {
        if isListening {
            stop()
        } else {
            wantsListening = true
            requestPermissionsAndStart()
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func stop() {
        wantsListening = false
        stopAudio()
    }

    private func stopAudio() {
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
    }

    private func requestPermissionsAndStart() {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.errorMessage = V2NativeCapabilityError.speechDenied.localizedDescription
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self, self.wantsListening else { return }
                let granted = await V2MicrophonePermission.requestAccess()
                guard self.wantsListening else { return }
                guard granted else {
                    self.errorMessage = V2NativeCapabilityError.microphoneDenied.localizedDescription
                    return
                }
                self.startRecording()
            }
        }
    }

    private func startRecording() {
        guard wantsListening else { return }
        guard recognizer?.isAvailable == true else {
            errorMessage = V2NativeCapabilityError.speechUnavailable.localizedDescription
            return
        }

        stopAudio()
        transcript = ""
        errorMessage = nil

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format
            ) { buffer, _ in
                request.append(buffer)
            }
            hasAudioTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result {
                        self?.transcript = result.bestTranscription.formattedString
                    }
                    if result?.isFinal == true || error != nil {
                        self?.stop()
                    }
                }
            }
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }
}
