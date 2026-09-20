import Foundation

public struct V2ScheduleSyncConflict: Codable, Equatable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var base: V2ScheduleDocument
    public var local: V2ScheduleDocument
    public var remote: V2ScheduleDocument
    public var remoteSHA: String
    public var conflicts: [V2ScheduleConflict]

    public init(id: String = UUID().uuidString, base: V2ScheduleDocument, local: V2ScheduleDocument,
                remote: V2ScheduleDocument, remoteSHA: String, conflicts: [V2ScheduleConflict]) {
        self.id = id; self.base = base; self.local = local; self.remote = remote
        self.remoteSHA = remoteSHA; self.conflicts = conflicts
    }
}

public struct V2ScheduleGitHubState: Codable, Equatable, Sendable {
    public enum Failure: String, Codable, Sendable { case network, authorization, invalidDocument, concurrentChange, other }
    public var location: V2GitHubScheduleLocation
    public var baseline: V2ScheduleDocument?
    public var sha: String?
    public var lastSyncedAt: Date?
    public var requiresRetry = true
    public var lastFailure: Failure?
    public var conflict: V2ScheduleSyncConflict?
    public var activeAttemptID: String?
    public var automaticSyncEnabled: Bool?
    public init(location: V2GitHubScheduleLocation) { self.location = location }
}

public struct V2ScheduleSyncAttempt: Sendable {
    public let id: String
    public let location: V2GitHubScheduleLocation
    public let local: V2ScheduleDocument
    public let baseline: V2ScheduleDocument?
}

public enum V2ScheduleSyncResult: Sendable {
    case synced(document: V2ScheduleDocument, sha: String)
    case conflict(V2ScheduleSyncConflict)
}

public enum V2ScheduleSyncError: Error, LocalizedError, Sendable {
    case notConfigured, staleAttempt, unresolvedConflict, differentDocument
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "请先配置 GitHub 日程文件。"
        case .staleAttempt: "同步配置已有变化，旧结果没有覆盖当前日程。"
        case .unresolvedConflict: "还有需要处理的日程冲突，双方版本均已保留。"
        case .differentDocument: "远端文件属于另一份日程，请先导入该文件，或选择新的远端文件路径。"
        }
    }
}

public enum V2ScheduleSynchronizer {
    public static func synchronize<Transport: V2PlanningHTTPTransport>(
        _ attempt: V2ScheduleSyncAttempt, using github: V2GitHubScheduleClient<Transport>,
        preflight: @Sendable () async throws -> Void = {}
    ) async throws -> V2ScheduleSyncResult {
        guard github.location == attempt.location else { throw V2ScheduleSyncError.staleAttempt }
        for retry in 0...3 {
            try Task.checkCancellation()
            try await preflight()
            var revision: V2GitHubScheduleRevision?
            do { revision = try await github.read() }
            catch V2GitHubScheduleError.notFound {
                guard attempt.baseline == nil else { throw V2GitHubScheduleError.notFound }
            }
            try await preflight()
            let candidate: V2ScheduleDocument
            if let revision {
                let remote = try V2ScheduleMarkdown.decode(revision.content)
                var local = attempt.local
                if local.id != remote.id {
                    guard attempt.baseline == nil, local.tasks.isEmpty, local.taskContexts.isEmpty,
                          local.planItems.isEmpty, local.executionSegments.isEmpty, local.remoteRequests.isEmpty else {
                        throw V2ScheduleSyncError.differentDocument
                    }
                    local = remote
                }
                let base = attempt.baseline ?? local.emptyScheduleBaseline()
                let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
                guard result.conflicts.isEmpty else {
                    return .conflict(.init(base: base, local: local, remote: remote, remoteSHA: revision.sha, conflicts: result.conflicts))
                }
                let protected = try V2ScheduleMerge.merge(base: local, local: local, remote: result.document)
                guard protected.conflicts.isEmpty else {
                    return .conflict(.init(base: local, local: local, remote: remote, remoteSHA: revision.sha, conflicts: protected.conflicts))
                }
                candidate = protected.document
                if candidate == remote { return .synced(document: remote, sha: revision.sha) }
            } else { candidate = attempt.local }
            do { try V2Engine.validateDocumentPlacement(candidate) }
            catch { throw V2ScheduleMergeError.invalidDocument("invalid merged task placement") }
            try Task.checkCancellation()
            try await preflight()
            do {
                let written = try await github.write(content: V2ScheduleMarkdown.encode(candidate), expectedSHA: revision?.sha)
                return .synced(document: candidate, sha: written.sha)
            } catch V2GitHubScheduleError.conflict {
                guard retry < 3 else { throw V2GitHubScheduleError.conflict }
            } catch V2GitHubScheduleError.requestFailed(422) where revision == nil && retry < 3 {
                // Another device may have created the file since the 404. Re-read before deciding.
                continue
            }
        }
        throw V2GitHubScheduleError.conflict
    }
}

extension V2ScheduleDocument {
    func emptyScheduleBaseline() -> V2ScheduleDocument {
        .init(id: id, timeZoneIdentifier: timeZoneIdentifier, taskContexts: [], tasks: [], planItems: [], executionSegments: [])
    }
}

public extension V2Engine {
    func setScheduleAutomaticSync(_ enabled: Bool) throws {
        try commit(modules: ["core.sync"], commandID: "core.sync.configure") { next in
            guard next.scheduleDocumentState?.github != nil else { throw V2ScheduleSyncError.notConfigured }
            next.scheduleDocumentState?.github?.automaticSyncEnabled = enabled
        }
    }

    func configureScheduleGitHub(_ location: V2GitHubScheduleLocation) throws {
        try commit(modules: ["core.sync"], commandID: "core.sync.configure") { next in
            guard var state = next.scheduleDocumentState else { throw V2ScheduleDocumentError.notPrepared }
            if state.github?.location != location { state.github = .init(location: location) }
            next.scheduleDocumentState = state
        }
    }

    func beginScheduleSync() throws -> V2ScheduleSyncAttempt {
        try commit(modules: ["core.sync"], commandID: "core.sync.begin") { next in
            guard var state = next.scheduleDocumentState, var github = state.github else { throw V2ScheduleSyncError.notConfigured }
            guard github.conflict == nil else { throw V2ScheduleSyncError.unresolvedConflict }
            let attempt = V2ScheduleSyncAttempt(id: UUID().uuidString, location: github.location,
                local: next.scheduleDocument(using: state.document), baseline: github.baseline)
            github.activeAttemptID = attempt.id
            github.requiresRetry = true
            github.lastFailure = nil
            state.github = github
            next.scheduleDocumentState = state
            return attempt
        }
    }

    func failScheduleSync(_ attempt: V2ScheduleSyncAttempt, failure: V2ScheduleGitHubState.Failure) throws {
        try commit(modules: ["core.sync"], commandID: "core.sync.fail") { next in
            guard var state = next.scheduleDocumentState, var github = state.github,
                  github.activeAttemptID == attempt.id, github.location == attempt.location else { return }
            github.activeAttemptID = nil
            github.lastFailure = failure
            github.requiresRetry = true
            state.github = github
            next.scheduleDocumentState = state
        }
    }

    /// Rebase the network result onto edits made while the request was in flight.
    func acceptScheduleSync(_ result: V2ScheduleSyncResult, attempt: V2ScheduleSyncAttempt, at date: Date = Date()) throws {
        try commit(modules: ["core.sync"], commandID: "core.sync.accept") { next in
            guard var state = next.scheduleDocumentState, var github = state.github,
                  github.activeAttemptID == attempt.id, github.location == attempt.location else { throw V2ScheduleSyncError.staleAttempt }
            var current = next.scheduleDocument(using: state.document)
            var localAtStart = attempt.local
            switch result {
            case let .synced(remote, sha):
                if current.id != remote.id {
                    guard current == attempt.local, attempt.baseline == nil, current.tasks.isEmpty,
                          current.planItems.isEmpty, current.executionSegments.isEmpty, state.bookmark == nil else {
                        throw V2ScheduleSyncError.differentDocument
                    }
                    current = remote.emptyScheduleBaseline()
                    localAtStart = current
                }
                let merged = try V2ScheduleMerge.merge(base: localAtStart, local: current, remote: remote)
                github.baseline = remote
                github.sha = sha
                github.lastSyncedAt = date
                github.lastFailure = nil
                if merged.conflicts.isEmpty {
                    let protected = try V2ScheduleMerge.merge(base: current, local: current, remote: merged.document)
                    guard protected.conflicts.isEmpty else { throw V2ScheduleDocumentError.conflicts(protected.conflicts) }
                    try Self.validateDocumentPlacement(protected.document)
                    if current != protected.document {
                        state.versions.append(.init(id: attempt.id, createdAt: date, source: .sync, before: current, after: protected.document))
                        state.versions = Array(state.versions.suffix(20))
                    }
                    state.document = protected.document
                    next.taskContexts = protected.document.taskContexts
                    next.tasks = protected.document.tasks
                    next.planItems = protected.document.planItems
                    next.executionSegments = protected.document.executionSegments
                    github.conflict = nil
                    github.requiresRetry = protected.document != remote
                } else {
                    github.conflict = .init(base: localAtStart, local: current, remote: remote, remoteSHA: sha, conflicts: merged.conflicts)
                    github.requiresRetry = true
                }
            case let .conflict(conflict):
                let merged = try V2ScheduleMerge.merge(base: conflict.base, local: current, remote: conflict.remote)
                github.conflict = merged.conflicts.isEmpty ? nil : .init(base: conflict.base, local: current,
                    remote: conflict.remote, remoteSHA: conflict.remoteSHA, conflicts: merged.conflicts)
                github.requiresRetry = true
            }
            github.activeAttemptID = nil
            state.github = github
            next.scheduleDocumentState = state
        }
    }
}
