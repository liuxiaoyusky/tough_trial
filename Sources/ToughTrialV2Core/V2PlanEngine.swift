import Foundation

public struct V2PlanDraftAcceptance: Equatable, Sendable {
    public var draft: V2PlanDraftRecord
    public var createdTasks: [V2Task]
    public var createdPlanItems: [V2PlanItem]

    public init(
        draft: V2PlanDraftRecord,
        createdTasks: [V2Task],
        createdPlanItems: [V2PlanItem]
    ) {
        self.draft = draft
        self.createdTasks = createdTasks
        self.createdPlanItems = createdPlanItems
    }
}

public struct V2PlanningWorkspaceSnapshot: Equatable, Sendable {
    public var range: DateInterval
    public var pendingDrafts: [V2PlanDraftRecord]
    public var planItems: [V2PlanItem]
    public var availableTasks: [V2Task]
    public var taskContexts: [V2TaskContext]

    public init(
        range: DateInterval,
        pendingDrafts: [V2PlanDraftRecord],
        planItems: [V2PlanItem],
        availableTasks: [V2Task],
        taskContexts: [V2TaskContext]
    ) {
        self.range = range
        self.pendingDrafts = pendingDrafts
        self.planItems = planItems
        self.availableTasks = availableTasks
        self.taskContexts = taskContexts
    }
}

public extension V2Engine {
    @discardableResult
    func savePlanDraft(
        _ draft: V2PlanDraftRecord,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> V2PlanDraftRecord {
        try commit { snapshot in
            let existingIndex = snapshot.planDrafts.firstIndex(where: { $0.id == draft.id })
            if let existingIndex,
               snapshot.planDrafts[existingIndex].status != .draft {
                throw V2EngineError.planDraftNotEditable(draft.id)
            }
            try Self.validateDraftForSave(draft, snapshot: snapshot, at: date, calendar: calendar)

            var saved = draft
            saved.status = .draft
            saved.acceptedAt = nil
            saved.updatedAt = date

            if let existingIndex {
                saved.createdAt = snapshot.planDrafts[existingIndex].createdAt
                snapshot.planDrafts[existingIndex] = saved
            } else {
                saved.createdAt = date
                snapshot.planDrafts.append(saved)
            }
            return saved
        }
    }

    @discardableResult
    func acceptPlanDraft(
        id: String,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> V2PlanDraftAcceptance {
        try commit { snapshot in
            guard let draftIndex = snapshot.planDrafts.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.planDraftNotFound(id)
            }
            let draft = snapshot.planDrafts[draftIndex]
            guard draft.status == .draft else {
                throw V2EngineError.planDraftNotEditable(id)
            }

            let createdTasks: [V2Task]
            let createdPlanItems: [V2PlanItem]
            switch draft.mode {
            case .scheduleOnly:
                guard draft.proposedTaskChanges.isEmpty else {
                    throw V2EngineError.invalidPlanDraft("scheduleOnly contains task changes")
                }
                createdTasks = []
                createdPlanItems = try Self.materializePlanItems(
                    draft.proposedPlanItems,
                    sourceDraftID: draft.id,
                    calendar: calendar,
                    snapshot: snapshot
                )
                snapshot.planItems.append(contentsOf: createdPlanItems)
            case .breakdownOnly:
                guard draft.proposedPlanItems.isEmpty else {
                    throw V2EngineError.invalidPlanDraft("breakdownOnly contains plan items")
                }
                createdTasks = try Self.materializeTaskProposals(
                    draft.proposedTaskChanges,
                    at: date,
                    snapshot: &snapshot
                )
                createdPlanItems = []
            case .mixed:
                guard !draft.proposedTaskChanges.isEmpty,
                      !draft.proposedPlanItems.isEmpty else {
                    throw V2EngineError.invalidPlanDraft("mixed requires task changes and plan items")
                }
                createdTasks = try Self.materializeTaskProposals(
                    draft.proposedTaskChanges,
                    at: date,
                    snapshot: &snapshot
                )
                let taskIDByProposalID = Dictionary(
                    uniqueKeysWithValues: zip(
                        draft.proposedTaskChanges.map(\.id),
                        createdTasks.map(\.id)
                    )
                )
                let resolvedPlanItems = try Self.resolvePlanItemTaskReferences(
                    draft.proposedPlanItems,
                    taskIDByProposalID: taskIDByProposalID
                )
                createdPlanItems = try Self.materializePlanItems(
                    resolvedPlanItems,
                    sourceDraftID: draft.id,
                    calendar: calendar,
                    snapshot: snapshot
                )
                snapshot.planItems.append(contentsOf: createdPlanItems)
            }

            snapshot.planDrafts[draftIndex].status = .accepted
            snapshot.planDrafts[draftIndex].updatedAt = date
            snapshot.planDrafts[draftIndex].acceptedAt = date
            return V2PlanDraftAcceptance(
                draft: snapshot.planDrafts[draftIndex],
                createdTasks: createdTasks,
                createdPlanItems: createdPlanItems
            )
        }
    }

    @discardableResult
    func discardPlanDraft(id: String, at date: Date = Date()) throws -> V2PlanDraftRecord {
        try commit { snapshot in
            guard let index = snapshot.planDrafts.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.planDraftNotFound(id)
            }
            guard snapshot.planDrafts[index].status == .draft else {
                throw V2EngineError.planDraftNotEditable(id)
            }
            snapshot.planDrafts[index].status = .discarded
            snapshot.planDrafts[index].updatedAt = date
            snapshot.planDrafts[index].acceptedAt = nil
            return snapshot.planDrafts[index]
        }
    }

    func planningWorkspaceSnapshot(range: DateInterval) -> V2PlanningWorkspaceSnapshot {
        let pendingDrafts = snapshot.planDrafts
            .filter { $0.status == .draft }
            .sorted { $0.updatedAt > $1.updatedAt }
        let planItems = snapshot.planItems
            .filter {
                $0.status != .canceled &&
                    $0.date >= range.start &&
                    $0.date < range.end
            }
            .sorted {
                let lhs = $0.startAt ?? $0.date
                let rhs = $1.startAt ?? $1.date
                if lhs == rhs { return $0.id < $1.id }
                return lhs < rhs
            }
        let availableTasks = snapshot.tasks
            .filter { $0.status != .archived }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return $0.createdAt < $1.createdAt
            }
        let contexts = snapshot.taskContexts
            .filter { $0.archivedAt == nil }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return $0.createdAt < $1.createdAt
            }
        return V2PlanningWorkspaceSnapshot(
            range: range,
            pendingDrafts: pendingDrafts,
            planItems: planItems,
            availableTasks: availableTasks,
            taskContexts: contexts
        )
    }
}

private extension V2Engine {
    static func validateDraftForSave(
        _ draft: V2PlanDraftRecord,
        snapshot: V2AppSnapshot,
        at date: Date,
        calendar: Calendar
    ) throws {
        let normalizedDraftID = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDraftID.isEmpty, normalizedDraftID == draft.id else {
            throw V2EngineError.invalidPlanDraft("draft id is invalid")
        }
        guard draft.status == .draft, draft.acceptedAt == nil else {
            throw V2EngineError.planDraftNotEditable(draft.id)
        }

        switch draft.mode {
        case .scheduleOnly:
            guard draft.proposedTaskChanges.isEmpty else {
                throw V2EngineError.invalidPlanDraft("scheduleOnly contains task changes")
            }
            _ = try materializePlanItems(
                draft.proposedPlanItems,
                sourceDraftID: draft.id,
                calendar: calendar,
                snapshot: snapshot
            )
        case .breakdownOnly:
            guard draft.proposedPlanItems.isEmpty else {
                throw V2EngineError.invalidPlanDraft("breakdownOnly contains plan items")
            }
            var validationSnapshot = snapshot
            _ = try materializeTaskProposals(
                draft.proposedTaskChanges,
                at: date,
                snapshot: &validationSnapshot
            )
        case .mixed:
            guard !draft.proposedTaskChanges.isEmpty,
                  !draft.proposedPlanItems.isEmpty else {
                throw V2EngineError.invalidPlanDraft("mixed requires task changes and plan items")
            }
            var validationSnapshot = snapshot
            let createdTasks = try materializeTaskProposals(
                draft.proposedTaskChanges,
                at: date,
                snapshot: &validationSnapshot
            )
            let taskIDByProposalID = Dictionary(
                uniqueKeysWithValues: zip(
                    draft.proposedTaskChanges.map(\.id),
                    createdTasks.map(\.id)
                )
            )
            let resolvedPlanItems = try resolvePlanItemTaskReferences(
                draft.proposedPlanItems,
                taskIDByProposalID: taskIDByProposalID
            )
            _ = try materializePlanItems(
                resolvedPlanItems,
                sourceDraftID: draft.id,
                calendar: calendar,
                snapshot: validationSnapshot
            )
        }
    }

    static func materializeTaskProposals(
        _ proposals: [V2ProposedTaskChange],
        at date: Date,
        snapshot: inout V2AppSnapshot
    ) throws -> [V2Task] {
        let proposalIDs = try uniqueProposalIDs(proposals.map(\.id))
        guard proposalIDs.isDisjoint(with: Set(snapshot.tasks.map(\.id))) else {
            let collision = proposalIDs.first { id in snapshot.tasks.contains { $0.id == id } } ?? ""
            throw V2EngineError.duplicateProposalID(collision)
        }

        var pending = proposals
        var durableIDByProposalID: [String: String] = [:]
        var taskByProposalID: [String: V2Task] = [:]

        while !pending.isEmpty {
            var nextPending: [V2ProposedTaskChange] = []
            var madeProgress = false

            for proposal in pending {
                let parentID: String?
                if let proposedParentID = proposal.parentID, proposalIDs.contains(proposedParentID) {
                    guard let resolvedParentID = durableIDByProposalID[proposedParentID] else {
                        nextPending.append(proposal)
                        continue
                    }
                    parentID = resolvedParentID
                } else {
                    parentID = proposal.parentID
                }

                let title = try normalizedProposalTitle(proposal.title)
                let effectiveContextID = try validatePlacement(
                    parentID: parentID,
                    contextID: proposal.contextID,
                    tasks: snapshot.tasks,
                    contexts: snapshot.taskContexts
                )
                let task = V2Task(
                    id: UUID().uuidString,
                    contextID: effectiveContextID,
                    parentID: parentID,
                    title: title,
                    kind: proposal.kind,
                    createdAt: date,
                    updatedAt: date
                )
                snapshot.tasks.append(task)
                durableIDByProposalID[proposal.id] = task.id
                taskByProposalID[proposal.id] = task
                madeProgress = true
            }

            guard madeProgress else {
                throw V2EngineError.taskHierarchyCycle
            }
            pending = nextPending
        }

        return proposals.compactMap { taskByProposalID[$0.id] }
    }

    static func materializePlanItems(
        _ proposals: [V2ProposedPlanItem],
        sourceDraftID: String,
        calendar: Calendar,
        snapshot: V2AppSnapshot
    ) throws -> [V2PlanItem] {
        _ = try uniqueProposalIDs(proposals.map(\.id))

        return try proposals.map { proposal in
            guard proposal.proposedTaskID == nil else {
                throw V2EngineError.invalidPlanDraft("unresolved proposed task reference")
            }
            let linkedTask: V2Task?
            if let taskID = proposal.taskID {
                guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else {
                    throw V2EngineError.taskNotFound(taskID)
                }
                guard task.status != .archived else {
                    throw V2EngineError.taskArchived(taskID)
                }
                linkedTask = task
            } else {
                linkedTask = nil
            }

            if proposal.endAt != nil, proposal.startAt == nil {
                throw V2EngineError.invalidPlanTimeRange(proposal.id)
            }
            if let startAt = proposal.startAt,
               let endAt = proposal.endAt,
               endAt <= startAt {
                throw V2EngineError.invalidPlanTimeRange(proposal.id)
            }

            let rawTitle = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = try normalizedProposalTitle(rawTitle.isEmpty ? linkedTask?.title ?? "" : rawTitle)
            return V2PlanItem(
                id: UUID().uuidString,
                date: calendar.startOfDay(for: proposal.date),
                startAt: proposal.startAt,
                endAt: proposal.endAt,
                taskID: proposal.taskID,
                title: title,
                sourceDraftID: sourceDraftID
            )
        }
    }

    static func resolvePlanItemTaskReferences(
        _ proposals: [V2ProposedPlanItem],
        taskIDByProposalID: [String: String]
    ) throws -> [V2ProposedPlanItem] {
        try proposals.map { proposal in
            guard !(proposal.taskID != nil && proposal.proposedTaskID != nil) else {
                throw V2EngineError.invalidPlanDraft("plan item has two task references")
            }
            guard let proposedTaskID = proposal.proposedTaskID else {
                return proposal
            }
            guard let taskID = taskIDByProposalID[proposedTaskID] else {
                throw V2EngineError.invalidPlanDraft("unknown proposed task reference")
            }
            var resolved = proposal
            resolved.taskID = taskID
            resolved.proposedTaskID = nil
            return resolved
        }
    }

    static func uniqueProposalIDs(_ proposalIDs: [String]) throws -> Set<String> {
        var ids = Set<String>()
        for proposalID in proposalIDs {
            let id = proposalID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, id == proposalID else {
                throw V2EngineError.invalidPlanDraft("proposal id is invalid")
            }
            guard ids.insert(id).inserted else {
                throw V2EngineError.duplicateProposalID(id)
            }
        }
        return ids
    }

    static func normalizedProposalTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw V2EngineError.blankTitle
        }
        return normalized
    }
}
