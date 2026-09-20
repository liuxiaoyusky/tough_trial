import Foundation
import ToughTrialV2Core

extension V2AppStore {
    func retryModuleOutbox() async {
        let kinds = Set(engine.snapshot.outbox.map(\.kind))
        for kind in kinds where engine.moduleRuntime.availability(kind.moduleID).isActive {
            do { try engine.requestSideEffect(kind) }
            catch { errorMessage = "重试状态未能保存，请稍后再试。"; return }
        }
        await drainModuleOutbox()
        refreshProjection(at: Date())
    }

    /// Runs only while the app is active. Each adapter rebuilds from the current
    /// projection, so a retry never repeats a payment or a business mutation.
    func drainModuleOutbox(at date: Date = Date()) async {
        guard canWrite, moduleSceneActive, !isStoppingServices, !isDrainingModuleOutbox else { return }
        isDrainingModuleOutbox = true
        defer { isDrainingModuleOutbox = false }
        for job in engine.snapshot.outbox where job.retryAt <= date {
            guard !Task.isCancelled, moduleSceneActive, !isStoppingServices else { return }
            guard engine.moduleRuntime.availability(job.kind.moduleID).isActive,
                  engine.snapshot.outbox.contains(where: { $0.id == job.id }),
                  let ticket = try? engine.moduleRuntime.ticket(for: [job.kind.moduleID]) else { continue }
            var failure: String?
            do {
                switch job.kind {
                case .taskReminders:
                    let snapshot = engine.snapshot
                    let eligible = snapshot.planItems.filter { item in
                        let task = snapshot.tasks.first { $0.id == item.taskID }
                        return task?.status != .done && task?.status != .archived
                    }
                    try await notificationService.rebuildOwned(planItems: eligible, now: date, calendar: calendar)
                case .financeReminders:
                    let applied = await V2FinanceNotifications.shared.refresh(engine.snapshot.capture.finance?.plans ?? [], now: date)
                    if !applied { failure = "notification_pending" }
                case .scheduleSync:
                    guard !isScheduleSyncing, pendingScheduleConflict == nil,
                          let github = engine.snapshot.scheduleDocumentState?.github,
                          github.automaticSyncEnabled != false,
                          github.conflict == nil,
                          github.lastFailure != .authorization,
                          github.lastFailure != .invalidDocument else { continue }
                    await synchronizeConfiguredSchedule()
                    let githubAfter = engine.snapshot.scheduleDocumentState?.github
                    if scheduleSyncError != nil || githubAfter?.requiresRetry == true
                        || githubAfter?.conflict != nil || githubAfter?.lastSyncedAt == nil {
                        failure = "sync_pending"
                    }
                }
                try engine.moduleRuntime.validate(ticket)
            } catch {
                // A stopped module leaves its job dormant until explicitly enabled.
                guard (try? engine.moduleRuntime.validate(ticket)) != nil else { continue }
                failure = job.kind == .scheduleSync ? "sync_pending" : "notification_pending"
            }
            do {
                try engine.finishOutboxJob(id: job.id, failureCode: failure, at: Date())
                V2UsageTrace.shared.record(.init(kind: failure == nil ? .jobFinished : .jobDeferred,
                    operationID: job.id, moduleID: job.kind.moduleID, commandID: job.kind.rawValue))
            }
            catch { errorMessage = "内容已保存，后续提醒或同步的状态暂未保存，将在下次打开时重试。" }
        }
    }

    func reconcileStoppedModules(at date: Date = Date()) {
        if !engine.moduleRuntime.availability("core.tasks").isActive {
            scheduleReminderTask?.cancel()
            notificationService.cancelAllOwned()
            closeZen()
            do { try engine.pauseExecutionsForModuleStop(at: date) }
            catch { errorMessage = "任务已停用，但暂停计时未能保存；已有记录仍保留。" }
            Task { await stopAllLiveActivities() }
        }
        if !engine.moduleRuntime.availability("core.sync").isActive { stopForegroundScheduleSync() }
        refreshProjection(at: date)
    }
}
