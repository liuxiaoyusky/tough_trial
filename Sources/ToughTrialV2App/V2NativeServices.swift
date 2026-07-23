@preconcurrency import ActivityKit
import AVFoundation
import Combine
import Foundation
import Speech
import ToughTrialActivityShared
import ToughTrialV2Core
import UserNotifications

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
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw V2NativeCapabilityError.notificationsDenied
        }
        return try await schedule(planItems: planItems, now: now, calendar: calendar)
    }

    func scheduleIfAuthorized(
        planItems: [V2PlanItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Int {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else {
            return 0
        }
        return try await schedule(planItems: planItems, now: now, calendar: calendar)
    }

    private func schedule(
        planItems: [V2PlanItem],
        now: Date,
        calendar: Calendar
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
            count += 1
        }
        return count
    }
}

@MainActor
final class V2LiveActivityService {
    func sync(session: V2ActiveSession, now: Date = Date()) async throws {
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
            return
        }

        for activity in Activity<V2FocusActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        _ = try Activity.request(
            attributes: V2FocusActivityAttributes(sessionID: session.id),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
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
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
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

            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard self?.wantsListening == true else { return }
                    guard granted else {
                        self?.errorMessage = V2NativeCapabilityError.microphoneDenied.localizedDescription
                        return
                    }
                    self?.startRecording()
                }
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
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

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
