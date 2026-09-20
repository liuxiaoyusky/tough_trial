import Foundation

public struct V2PlanningOutcomeValidator: Sendable {
    public init() {}

    @discardableResult
    public func validate(
        _ outcome: V2PlanningOutcome,
        for request: V2PlanningRequest
    ) throws -> V2PlanningOutcome {
        switch outcome {
        case .clarification(let clarification):
            try Self.requireNonempty(clarification.question, field: "clarification.question")
            guard clarification.suggestedReplies.count <= 3 else {
                throw V2PlanningClientError.invalidOutput("澄清快捷回答不能超过 3 个")
            }
            for reply in clarification.suggestedReplies {
                try Self.requireNonempty(reply, field: "clarification.suggested_replies")
            }

        case .proposal(let proposal):
            try Self.validate(proposal, for: request)
        }
        return outcome
    }
}

public struct V2ValidatedPlanningClient: V2PlanningClient {
    private let client: any V2PlanningClient
    private let validator: V2PlanningOutcomeValidator

    public var providerLabel: String {
        client.providerLabel
    }

    public init(
        client: any V2PlanningClient,
        validator: V2PlanningOutcomeValidator = V2PlanningOutcomeValidator()
    ) {
        self.client = client
        self.validator = validator
    }

    public func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome {
        let outcome = try await client.generate(request)
        return try validator.validate(outcome, for: request)
    }
}

private extension V2PlanningOutcomeValidator {
    static func validate(
        _ proposal: V2PlanningProposal,
        for request: V2PlanningRequest
    ) throws {
        try requireNonempty(proposal.message, field: "proposal.message")

        let draft = proposal.draft
        _ = try identifier(draft.id, field: "draft.id")
        try requireNonempty(draft.userPrompt, field: "draft.user_prompt")
        try requireNonempty(draft.title, field: "draft.title")
        try requireNonempty(draft.summary, field: "draft.summary")

        if let currentDraft = request.currentDraft, draft.id != currentDraft.id {
            throw V2PlanningClientError.invalidOutput("修改草稿时必须保留原草稿 ID")
        }
        guard !draft.taskChanges.isEmpty || !draft.scheduleItems.isEmpty else {
            throw V2PlanningClientError.invalidOutput("草稿没有任务变化或计划项")
        }
        guard draft.taskChanges.count <= 20 else {
            throw V2PlanningClientError.invalidOutput("候选任务不能超过 20 个")
        }
        guard draft.scheduleItems.count <= 31 else {
            throw V2PlanningClientError.invalidOutput("候选计划项不能超过 31 个")
        }

        let knownTaskIDs = Set(request.tasks.map(\.id))
        let proposedTaskIDs = try uniqueIdentifiers(
            draft.taskChanges.map(\.id),
            field: "task_changes.id"
        )
        try validateTaskChanges(
            draft.taskChanges,
            knownTaskIDs: knownTaskIDs,
            proposedTaskIDs: proposedTaskIDs
        )

        _ = try uniqueIdentifiers(
            draft.scheduleItems.map(\.id),
            field: "schedule_items.id"
        )
        try validateScheduleItems(
            draft.scheduleItems,
            request: request,
            knownTaskIDs: knownTaskIDs,
            proposedTaskIDs: proposedTaskIDs
        )
    }

    static func validateTaskChanges(
        _ taskChanges: [V2PlanDraftTaskChange],
        knownTaskIDs: Set<String>,
        proposedTaskIDs: Set<String>
    ) throws {
        var proposedParents: [String: String] = [:]

        for task in taskChanges {
            let taskID = try identifier(task.id, field: "task_changes.id")
            try requireNonempty(task.title, field: "task_changes.title")
            if let contextID = task.contextID {
                _ = try identifier(contextID, field: "task_changes.context_id")
            }
            guard let rawParentID = task.parentID else { continue }

            let parentID = try identifier(rawParentID, field: "task_changes.parent_id")
            guard parentID != taskID else {
                throw V2PlanningClientError.invalidOutput("候选任务不能把自己作为父节点：\(taskID)")
            }
            guard knownTaskIDs.contains(parentID) || proposedTaskIDs.contains(parentID) else {
                throw V2PlanningClientError.invalidOutput("任务父节点不存在：\(parentID)")
            }
            if proposedTaskIDs.contains(parentID) {
                proposedParents[taskID] = parentID
            }
        }

        for taskID in proposedTaskIDs {
            var visited: Set<String> = [taskID]
            var cursor = taskID
            while let parentID = proposedParents[cursor] {
                guard visited.insert(parentID).inserted else {
                    throw V2PlanningClientError.invalidOutput("候选任务父子关系形成循环")
                }
                cursor = parentID
            }
        }
    }

    static func validateScheduleItems(
        _ scheduleItems: [V2PlanDraftScheduleItem],
        request: V2PlanningRequest,
        knownTaskIDs: Set<String>,
        proposedTaskIDs: Set<String>
    ) throws {
        guard let timeZone = TimeZone(identifier: request.timeZoneIdentifier) else {
            throw V2PlanningClientError.invalidOutput("无法识别计划时区")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let referenceDay = calendar.startOfDay(for: request.referenceDate)
        guard let finalDay = calendar.date(byAdding: .day, value: 366, to: referenceDay) else {
            throw V2PlanningClientError.invalidOutput("无法计算计划日期范围")
        }

        for item in scheduleItems {
            _ = try identifier(item.id, field: "schedule_items.id")
            try requireNonempty(item.title, field: "schedule_items.title")

            guard !(item.taskID != nil && item.proposedTaskID != nil) else {
                throw V2PlanningClientError.invalidOutput("计划项不能同时引用现有任务和候选任务")
            }
            if let rawTaskID = item.taskID {
                let taskID = try identifier(rawTaskID, field: "schedule_items.task_id")
                guard knownTaskIDs.contains(taskID) else {
                    throw V2PlanningClientError.invalidOutput("引用了不存在的任务：\(taskID)")
                }
            }
            if let rawProposedTaskID = item.proposedTaskID {
                let proposedTaskID = try identifier(
                    rawProposedTaskID,
                    field: "schedule_items.proposed_task_id"
                )
                guard proposedTaskIDs.contains(proposedTaskID) else {
                    throw V2PlanningClientError.invalidOutput(
                        "引用了不存在的候选任务：\(proposedTaskID)"
                    )
                }
            }

            let itemDay = calendar.startOfDay(for: item.date)
            guard itemDay >= referenceDay && itemDay <= finalDay else {
                throw V2PlanningClientError.invalidOutput("计划日期超出 0 到 366 天范围")
            }

            if item.startAt == nil, item.endAt != nil {
                throw V2PlanningClientError.invalidOutput("没有开始时间时不能设置结束时间")
            }
            guard let startAt = item.startAt else { continue }
            guard calendar.isDate(startAt, inSameDayAs: itemDay) else {
                throw V2PlanningClientError.invalidOutput("开始时间不在计划项日期内")
            }
            guard let endAt = item.endAt else { continue }
            guard endAt > startAt else {
                throw V2PlanningClientError.invalidOutput("结束时间必须晚于开始时间")
            }

            let duration = endAt.timeIntervalSince(startAt)
            guard duration >= 15 * 60 && duration <= 720 * 60 else {
                throw V2PlanningClientError.invalidOutput("计划时长必须在 15 到 720 分钟之间")
            }
        }
    }

    static func uniqueIdentifiers(
        _ values: [String],
        field: String
    ) throws -> Set<String> {
        var identifiers: Set<String> = []
        for value in values {
            let normalized = try identifier(value, field: field)
            guard identifiers.insert(normalized).inserted else {
                throw V2PlanningClientError.invalidOutput("\(field) 重复：\(normalized)")
            }
        }
        return identifiers
    }

    static func identifier(_ value: String, field: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw V2PlanningClientError.invalidOutput("\(field) 不能为空")
        }
        guard normalized == value else {
            throw V2PlanningClientError.invalidOutput("\(field) 不能包含首尾空白")
        }
        return normalized
    }

    static func requireNonempty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2PlanningClientError.invalidOutput("\(field) 不能为空")
        }
    }
}
