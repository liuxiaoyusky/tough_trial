import Foundation

public struct V2ConnectorCursor: Codable, Equatable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct V2ExternalObjectKey: Codable, Equatable, Hashable, Sendable {
    public var provider: V2TaskSourceReference.Kind
    public var containerID: String
    public var externalID: String

    public init(
        provider: V2TaskSourceReference.Kind,
        containerID: String,
        externalID: String
    ) {
        self.provider = provider
        self.containerID = containerID
        self.externalID = externalID
    }

    public var sourceKey: String {
        "\(containerID):\(externalID)"
    }
}

public struct V2ExternalObservation: Codable, Equatable, Sendable {
    public var key: V2ExternalObjectKey
    public var title: String
    public var versionMarker: String
    public var location: String?
    public var updatedAt: Date?

    public init(
        key: V2ExternalObjectKey,
        title: String,
        versionMarker: String,
        location: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.key = key
        self.title = title
        self.versionMarker = versionMarker
        self.location = location
        self.updatedAt = updatedAt
    }
}

public struct V2ConnectorPullPage: Equatable, Sendable {
    public var observations: [V2ExternalObservation]
    public var nextCursor: V2ConnectorCursor?

    public init(
        observations: [V2ExternalObservation],
        nextCursor: V2ConnectorCursor?
    ) {
        self.observations = observations
        self.nextCursor = nextCursor
    }
}

public protocol V2ExternalConnector: Sendable {
    func pull(cursor: V2ConnectorCursor?) async throws -> V2ConnectorPullPage
}

public enum V2ExternalConnectorError: Error, Equatable, Sendable {
    case invalidCursor(String)
    case blankContainerID(V2ExternalObjectKey)
    case blankExternalID(V2ExternalObjectKey)
    case blankObservationTitle(V2ExternalObjectKey)
    case blankVersionMarker(V2ExternalObjectKey)
    case duplicateObservation(V2ExternalObjectKey)
    case observationNotFound(V2ExternalObjectKey)
    case proposalNotFound(String)
    case staleProposal(String)
    case confirmedTaskMissing(String)
}

public struct V2FixtureExternalConnector: V2ExternalConnector {
    private let pages: [[V2ExternalObservation]]

    public init(pages: [[V2ExternalObservation]] = Self.standardPages) {
        self.pages = pages
    }

    public func pull(cursor: V2ConnectorCursor?) async throws -> V2ConnectorPullPage {
        let pageIndex = try pageIndex(from: cursor)
        let nextIndex = pageIndex + 1
        let nextCursor = pages.indices.contains(nextIndex)
            ? V2ConnectorCursor(rawValue: Self.cursorRawValue(for: nextIndex))
            : nil
        return V2ConnectorPullPage(
            observations: pages[pageIndex],
            nextCursor: nextCursor
        )
    }

    private func pageIndex(from cursor: V2ConnectorCursor?) throws -> Int {
        guard let cursor else {
            guard !pages.isEmpty else {
                throw V2ExternalConnectorError.invalidCursor("")
            }
            return 0
        }

        let prefix = "fixture-page:"
        guard
            cursor.rawValue.hasPrefix(prefix),
            let pageIndex = Int(cursor.rawValue.dropFirst(prefix.count)),
            pages.indices.contains(pageIndex)
        else {
            throw V2ExternalConnectorError.invalidCursor(cursor.rawValue)
        }
        return pageIndex
    }

    private static func cursorRawValue(for pageIndex: Int) -> String {
        "fixture-page:\(pageIndex)"
    }

    public static var standardPages: [[V2ExternalObservation]] {
        let firstUpdatedAt = Date(timeIntervalSince1970: 1_799_900_000)
        let secondUpdatedAt = firstUpdatedAt.addingTimeInterval(60)
        let thirdUpdatedAt = secondUpdatedAt.addingTimeInterval(60)

        return [
            [
                V2ExternalObservation(
                    key: V2ExternalObjectKey(
                        provider: .fixture,
                        containerID: "stage-0",
                        externalID: "task-001"
                    ),
                    title: "整理本周研究材料",
                    versionMarker: "v1",
                    location: "fixture://stage-0/task-001",
                    updatedAt: firstUpdatedAt
                ),
                V2ExternalObservation(
                    key: V2ExternalObjectKey(
                        provider: .fixture,
                        containerID: "stage-0",
                        externalID: "task-002"
                    ),
                    title: "确认下周会议议程",
                    versionMarker: "v1",
                    location: "fixture://stage-0/task-002",
                    updatedAt: secondUpdatedAt
                ),
            ],
            [
                V2ExternalObservation(
                    key: V2ExternalObjectKey(
                        provider: .fixture,
                        containerID: "stage-0",
                        externalID: "task-003"
                    ),
                    title: "归档已完成的资料",
                    versionMarker: "v1",
                    location: "fixture://stage-0/task-003",
                    updatedAt: thirdUpdatedAt
                ),
            ],
        ]
    }
}

public struct V2ConnectorSyncResult: Equatable, Sendable {
    public var insertedCount: Int
    public var updatedCount: Int
    public var unchangedCount: Int
    public var nextCursor: V2ConnectorCursor?

    public init(
        insertedCount: Int,
        updatedCount: Int,
        unchangedCount: Int,
        nextCursor: V2ConnectorCursor?
    ) {
        self.insertedCount = insertedCount
        self.updatedCount = updatedCount
        self.unchangedCount = unchangedCount
        self.nextCursor = nextCursor
    }
}

public struct V2ExternalTaskProposal: Identifiable, Equatable, Sendable {
    public var id: String
    public var observationKey: V2ExternalObjectKey
    public var sourceVersionMarker: String
    public var title: String
    public var sourceReference: V2TaskSourceReference

    public init(
        id: String,
        observationKey: V2ExternalObjectKey,
        sourceVersionMarker: String,
        title: String,
        sourceReference: V2TaskSourceReference
    ) {
        self.id = id
        self.observationKey = observationKey
        self.sourceVersionMarker = sourceVersionMarker
        self.title = title
        self.sourceReference = sourceReference
    }
}

public final class V2ExternalConnectorSession {
    public private(set) var cursor: V2ConnectorCursor?
    public private(set) var observations: [V2ExternalObjectKey: V2ExternalObservation]

    private var proposalsByID: [String: V2ExternalTaskProposal]
    private var confirmedTaskIDByProposalID: [String: String]

    public init() {
        cursor = nil
        observations = [:]
        proposalsByID = [:]
        confirmedTaskIDByProposalID = [:]
    }

    @discardableResult
    public func syncPage(
        from connector: any V2ExternalConnector,
        cursor requestedCursor: V2ConnectorCursor?
    ) async throws -> V2ConnectorSyncResult {
        let page = try await connector.pull(cursor: requestedCursor)
        let validatedObservations = try Self.validated(page.observations)
        var nextObservations = observations
        var insertedCount = 0
        var updatedCount = 0
        var unchangedCount = 0

        for observation in validatedObservations {
            switch nextObservations[observation.key] {
            case nil:
                insertedCount += 1
            case observation:
                unchangedCount += 1
            default:
                updatedCount += 1
            }
            nextObservations[observation.key] = observation
        }

        observations = nextObservations
        cursor = page.nextCursor
        return V2ConnectorSyncResult(
            insertedCount: insertedCount,
            updatedCount: updatedCount,
            unchangedCount: unchangedCount,
            nextCursor: page.nextCursor
        )
    }

    public func proposeTask(
        for key: V2ExternalObjectKey
    ) throws -> V2ExternalTaskProposal {
        guard let observation = observations[key] else {
            throw V2ExternalConnectorError.observationNotFound(key)
        }

        let proposal = V2ExternalTaskProposal(
            id: Self.proposalID(for: observation),
            observationKey: key,
            sourceVersionMarker: observation.versionMarker,
            title: observation.title,
            sourceReference: V2TaskSourceReference(
                kind: key.provider,
                key: key.sourceKey,
                location: observation.location,
                updatedAt: observation.updatedAt
            )
        )
        proposalsByID[proposal.id] = proposal
        return proposal
    }

    @discardableResult
    public func confirmTaskProposal(
        id proposalID: String,
        with engine: V2Engine,
        at date: Date = Date()
    ) throws -> V2Task {
        guard let proposal = proposalsByID[proposalID] else {
            throw V2ExternalConnectorError.proposalNotFound(proposalID)
        }

        if let taskID = confirmedTaskIDByProposalID[proposalID] {
            guard let task = engine.snapshot.tasks.first(where: { $0.id == taskID }) else {
                throw V2ExternalConnectorError.confirmedTaskMissing(taskID)
            }
            return task
        }

        guard
            let currentObservation = observations[proposal.observationKey],
            currentObservation.versionMarker == proposal.sourceVersionMarker
        else {
            throw V2ExternalConnectorError.staleProposal(proposalID)
        }

        if let existingTask = engine.snapshot.tasks.first(where: {
            $0.sourceReference?.kind == proposal.sourceReference.kind
                && $0.sourceReference?.key == proposal.sourceReference.key
        }) {
            confirmedTaskIDByProposalID[proposalID] = existingTask.id
            return existingTask
        }

        let task = try engine.createTask(
            title: proposal.title,
            sourceReference: proposal.sourceReference,
            at: date
        )
        confirmedTaskIDByProposalID[proposalID] = task.id
        return task
    }

    private static func validated(
        _ observations: [V2ExternalObservation]
    ) throws -> [V2ExternalObservation] {
        var seenKeys: Set<V2ExternalObjectKey> = []

        return try observations.map { observation in
            let key = observation.key
            guard !key.containerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw V2ExternalConnectorError.blankContainerID(key)
            }
            guard !key.externalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw V2ExternalConnectorError.blankExternalID(key)
            }

            let title = observation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw V2ExternalConnectorError.blankObservationTitle(key)
            }

            let versionMarker = observation.versionMarker.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !versionMarker.isEmpty else {
                throw V2ExternalConnectorError.blankVersionMarker(key)
            }
            guard seenKeys.insert(key).inserted else {
                throw V2ExternalConnectorError.duplicateObservation(key)
            }

            var validated = observation
            validated.title = title
            validated.versionMarker = versionMarker
            return validated
        }
    }

    private static func proposalID(for observation: V2ExternalObservation) -> String {
        [
            "task",
            observation.key.provider.rawValue,
            observation.key.containerID,
            observation.key.externalID,
            observation.versionMarker,
        ].joined(separator: "|")
    }
}
