import Foundation
import ToughTrialV2Core

extension V2AppStore {
    func startForegroundScheduleSync() {
        guard !isStoppingServices else { return }
        guard V2PluginStore.shared.enabled("sync") else { stopForegroundScheduleSync(); return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["TOUGH_TRIAL_UI_TESTING"] != "1", environment["TOUGH_TRIAL_UI_TEST_EMPTY"] != "1",
              foregroundScheduleSyncTask == nil else { return }
        foregroundScheduleSyncTask = Task { @MainActor [weak self] in await self?.runForegroundScheduleSync() }
    }

    func stopForegroundScheduleSync() {
        foregroundScheduleSyncTask?.cancel()
        foregroundScheduleSyncTask = nil
    }

    static func shouldAutomaticallySync(_ github: V2ScheduleGitHubState, document: V2ScheduleDocument,
                                        lastCheckedAt: Date, now: Date, isBusy: Bool, needsConfirmation: Bool) -> Bool {
        guard github.automaticSyncEnabled != false, !isBusy, !needsConfirmation, github.conflict == nil,
              github.lastFailure != .authorization, github.lastFailure != .invalidDocument else { return false }
        // Saving a destination alone does not upload data; the first connection is user initiated.
        guard github.lastSyncedAt != nil || github.lastFailure != nil || github.activeAttemptID != nil else { return false }
        let elapsed = now.timeIntervalSince(lastCheckedAt)
        if github.lastFailure != nil { return elapsed >= 30 }
        return elapsed >= 30 || (elapsed >= 5 && (github.requiresRetry || github.baseline != document))
    }

    func runForegroundScheduleSync() async {
        var lastCheckedAt = Date.distantPast
        while !Task.isCancelled {
            if let state = engine.snapshot.scheduleDocumentState, let github = state.github,
               Self.shouldAutomaticallySync(github, document: engine.snapshot.scheduleDocument(using: state.document),
                   lastCheckedAt: lastCheckedAt, now: Date(), isBusy: isScheduleSyncing, needsConfirmation: pendingScheduleConflict != nil) {
                lastCheckedAt = Date()
                await synchronizeConfiguredSchedule()
            }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
        }
    }

    func setScheduleAutomaticSync(_ enabled: Bool) {
        do {
            try engine.setScheduleAutomaticSync(enabled)
            refreshProjection(at: Date())
        } catch { scheduleSyncError = "自动同步设置暂时无法保存。" }
    }
}
