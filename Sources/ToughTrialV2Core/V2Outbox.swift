import Foundation

/// A coalesced, durable request to rebuild a host side effect from current data.
/// Payloads contain no credentials, paths, text, or copied business records.
public struct V2OutboxJob: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case taskReminders, financeReminders, scheduleSync

        public var moduleID: String {
            switch self {
            case .taskReminders: "core.tasks"
            case .financeReminders: "core.finance"
            case .scheduleSync: "core.sync"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let createdAt: Date
    public var attempts: Int
    public var retryAt: Date
    public var failureCode: String?

    public init(kind: Kind, at date: Date = Date()) {
        id = UUID().uuidString
        self.kind = kind
        createdAt = date
        attempts = 0
        retryAt = date
    }
}

public enum V2OutboxPolicy {
    public static func enqueue(_ kind: V2OutboxJob.Kind, into snapshot: inout V2AppSnapshot, at date: Date) {
        snapshot.outbox.removeAll { $0.kind == kind }
        snapshot.outbox.append(.init(kind: kind, at: date))
    }

    public static func enqueueChanges(from old: V2AppSnapshot, into next: inout V2AppSnapshot, at date: Date) {
        if old.tasks != next.tasks || old.planItems != next.planItems {
            enqueue(.taskReminders, into: &next, at: date)
            // A saved destination is not permission for the first upload.
            if let github = next.scheduleDocumentState?.github,
               github.automaticSyncEnabled != false,
               github.lastSyncedAt != nil || github.activeAttemptID != nil || github.lastFailure != nil {
                enqueue(.scheduleSync, into: &next, at: date)
            }
        }
        if old.capture.finance?.plans != next.capture.finance?.plans {
            enqueue(.financeReminders, into: &next, at: date)
        }
    }

    /// Completion of an old job must never acknowledge a newer business edit.
    public static func finish(id: String, failureCode: String?, in snapshot: inout V2AppSnapshot, at date: Date) {
        guard let index = snapshot.outbox.firstIndex(where: { $0.id == id }) else { return }
        guard let failureCode else {
            snapshot.outbox.remove(at: index)
            return
        }
        snapshot.outbox[index].attempts = min(20, snapshot.outbox[index].attempts + 1)
        snapshot.outbox[index].failureCode = String(failureCode.prefix(80))
        let delay = min(3600, 30 * pow(2, Double(min(7, snapshot.outbox[index].attempts - 1))))
        snapshot.outbox[index].retryAt = date.addingTimeInterval(delay)
    }
}

extension V2Engine {
    public func finishOutboxJob(id: String, failureCode: String? = nil, at date: Date = Date()) throws {
        try commitHost { snapshot in
            V2OutboxPolicy.finish(id: id, failureCode: failureCode, in: &snapshot, at: date)
        }
    }

    public func requestSideEffect(_ kind: V2OutboxJob.Kind, at date: Date = Date()) throws {
        try moduleRuntime.require([kind.moduleID])
        try commitHost { snapshot in V2OutboxPolicy.enqueue(kind, into: &snapshot, at: date) }
    }

    /// Host cleanup remains available after the task module's entry gate closes.
    public func pauseExecutionsForModuleStop(at date: Date = Date()) throws {
        guard !moduleRuntime.availability("core.tasks").isActive,
              snapshot.executionSegments.contains(where: { $0.endAt == nil }) else { return }
        try commitHost { snapshot in
            for index in snapshot.executionSegments.indices where snapshot.executionSegments[index].endAt == nil {
                snapshot.executionSegments[index].endAt = max(date, snapshot.executionSegments[index].startAt)
                snapshot.executionSegments[index].endReason = .paused
                if let taskID = snapshot.executionSegments[index].taskID,
                   let taskIndex = snapshot.tasks.firstIndex(where: { $0.id == taskID }),
                   snapshot.tasks[taskIndex].status == .active {
                    snapshot.tasks[taskIndex].status = .paused
                    snapshot.tasks[taskIndex].updatedAt = date
                }
            }
        }
    }
}
