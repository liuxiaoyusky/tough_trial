import Foundation

public struct V2PlanningTaskContext: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var parentID: String?
    public var contextID: String?
    public var kind: V2Task.Kind?
    public var status: V2Task.Status

    public init(
        id: String,
        title: String,
        parentID: String? = nil,
        contextID: String? = nil,
        kind: V2Task.Kind? = nil,
        status: V2Task.Status
    ) {
        self.id = id
        self.title = title
        self.parentID = parentID
        self.contextID = contextID
        self.kind = kind
        self.status = status
    }
}

public struct V2PlanningRequest: Equatable, Sendable {
    public var userPrompt: String
    public var clarificationResponse: String?
    public var scope: String?
    public var referenceDate: Date
    public var timeZoneIdentifier: String
    public var tasks: [V2PlanningTaskContext]
    public var memoryStatements: [String]
    public var currentDraft: V2PlanDraft?

    public init(
        userPrompt: String,
        clarificationResponse: String? = nil,
        scope: String? = nil,
        referenceDate: Date,
        timeZoneIdentifier: String,
        tasks: [V2PlanningTaskContext] = [],
        memoryStatements: [String] = [],
        currentDraft: V2PlanDraft? = nil
    ) {
        self.userPrompt = userPrompt
        self.clarificationResponse = clarificationResponse
        self.scope = scope
        self.referenceDate = referenceDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.tasks = tasks
        self.memoryStatements = memoryStatements
        self.currentDraft = currentDraft
    }
}

public struct V2PlanningClarification: Equatable, Sendable {
    public var question: String
    public var suggestedReplies: [String]

    public init(question: String, suggestedReplies: [String] = []) {
        self.question = question
        self.suggestedReplies = suggestedReplies
    }
}

public struct V2PlanningProposal: Equatable, Sendable {
    public var message: String
    public var draft: V2PlanDraft

    public init(message: String, draft: V2PlanDraft) {
        self.message = message
        self.draft = draft
    }
}

public enum V2PlanningOutcome: Equatable, Sendable {
    case clarification(V2PlanningClarification)
    case proposal(V2PlanningProposal)
}

public protocol V2PlanningClient: Sendable {
    var providerLabel: String { get }
    func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome
}

public struct V2DeterministicPlanningClient: V2PlanningClient {
    public let providerLabel = "本地基础规划"

    public init() {}

    public func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .current

        var state = V2PrototypeState.empty()
        state.beginPlanPrompt(
            request.userPrompt,
            scope: request.scope,
            at: request.referenceDate,
            calendar: calendar
        )

        guard let clarificationResponse = request.clarificationResponse else {
            let question = state.planMessages.last(where: { $0.role == .agent })?.text
                ?? "这件事最重要的限制是什么？"
            return .clarification(
                V2PlanningClarification(
                    question: question,
                    suggestedReplies: ["可以", "想分两次", "先看看时间"]
                )
            )
        }

        state.confirmPlanClarification(
            clarificationResponse,
            at: request.referenceDate,
            calendar: calendar
        )
        guard var draft = state.currentPlanDraft else {
            throw V2PlanningClientError.invalidOutput("本地规划器没有生成草稿")
        }
        if let currentDraft = request.currentDraft {
            draft.id = currentDraft.id
        }
        let message = state.planMessages.last(where: { $0.role == .agent })?.text
            ?? "我整理了一份草稿。"
        return .proposal(V2PlanningProposal(message: message, draft: draft))
    }
}

public enum V2PlanningClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case requestFailed(statusCode: Int, message: String)
    case missingOutput
    case refused(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            "AI 配置不可用：\(message)"
        case .requestFailed(let statusCode, let message):
            "AI 请求失败（\(statusCode)）：\(message)"
        case .missingOutput:
            "AI 没有返回可用内容。"
        case .refused(let message):
            "AI 无法完成这次规划：\(message)"
        case .invalidOutput(let message):
            "AI 返回的计划无法使用：\(message)"
        }
    }
}

public protocol V2PlanningHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct V2URLSessionPlanningTransport: V2PlanningHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V2PlanningClientError.invalidOutput("服务器没有返回 HTTP 响应")
        }
        return (data, httpResponse)
    }
}

public struct V2RemotePlanningConfiguration: Equatable, Sendable {
    public var endpoint: URL
    public var apiKey: String
    public var model: String

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        apiKey: String,
        model: String
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }
}

public struct V2RemotePlanningClient<Transport: V2PlanningHTTPTransport>: V2PlanningClient {
    public let providerLabel = "AI 规划"

    private let configuration: V2RemotePlanningConfiguration
    private let transport: Transport

    public init(
        configuration: V2RemotePlanningConfiguration,
        transport: Transport
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome {
        let urlRequest = try makeURLRequest(for: request)
        let (data, response) = try await transport.data(for: urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw V2PlanningClientError.requestFailed(
                statusCode: response.statusCode,
                message: Self.serverErrorMessage(from: data)
            )
        }
        return try decodeResponse(data, request: request)
    }

    public func makeURLRequest(for request: V2PlanningRequest) throws -> URLRequest {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw V2PlanningClientError.invalidConfiguration("缺少 API key")
        }
        guard !model.isEmpty else {
            throw V2PlanningClientError.invalidConfiguration("缺少模型名称")
        }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(configuration: configuration, request: request),
            options: [.sortedKeys]
        )
        return urlRequest
    }

    public func decodeResponse(
        _ data: Data,
        request: V2PlanningRequest
    ) throws -> V2PlanningOutcome {
        let response: ResponseEnvelope
        do {
            response = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw V2PlanningClientError.invalidOutput("响应结构无法解析")
        }

        for output in response.output where output.type == "message" {
            for content in output.content ?? [] {
                if content.type == "refusal", let refusal = content.refusal {
                    throw V2PlanningClientError.refused(refusal)
                }
                guard content.type == "output_text", let text = content.text else { continue }
                return try Self.decodeStructuredOutput(text, request: request)
            }
        }
        throw V2PlanningClientError.missingOutput
    }
}

public extension V2RemotePlanningClient where Transport == V2URLSessionPlanningTransport {
    init(configuration: V2RemotePlanningConfiguration) {
        self.init(configuration: configuration, transport: V2URLSessionPlanningTransport())
    }
}

public struct V2OpenAICompatiblePlanningConfiguration: Equatable, Sendable {
    public var endpoint: URL
    public var apiKey: String
    public var model: String
    public var providerLabel: String

    public init(
        endpoint: URL,
        apiKey: String,
        model: String,
        providerLabel: String = "在线 AI"
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.providerLabel = providerLabel
    }
}

public struct V2OpenAICompatiblePlanningClient<Transport: V2PlanningHTTPTransport>: V2PlanningClient {
    public var providerLabel: String {
        let label = configuration.providerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "在线 AI" : label
    }

    private let configuration: V2OpenAICompatiblePlanningConfiguration
    private let transport: Transport

    public init(
        configuration: V2OpenAICompatiblePlanningConfiguration,
        transport: Transport
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome {
        let urlRequest = try makeURLRequest(for: request)
        let (data, response) = try await transport.data(for: urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw V2PlanningClientError.requestFailed(
                statusCode: response.statusCode,
                message: V2RemotePlanningClient<Transport>.serverErrorMessage(from: data)
            )
        }
        return try decodeResponse(data, request: request)
    }

    public func makeURLRequest(for request: V2PlanningRequest) throws -> URLRequest {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw V2PlanningClientError.invalidConfiguration("缺少 API key")
        }
        guard !model.isEmpty else {
            throw V2PlanningClientError.invalidConfiguration("缺少模型名称")
        }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(configuration: configuration, request: request),
            options: [.sortedKeys]
        )
        return urlRequest
    }

    public func decodeResponse(
        _ data: Data,
        request: V2PlanningRequest
    ) throws -> V2PlanningOutcome {
        let response: ResponseEnvelope
        do {
            response = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw V2PlanningClientError.invalidOutput("响应结构无法解析")
        }

        for choice in response.choices {
            if let refusal = choice.message.refusal?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !refusal.isEmpty {
                throw V2PlanningClientError.refused(refusal)
            }
            guard let content = choice.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !content.isEmpty
            else {
                continue
            }
            return try V2RemotePlanningClient<Transport>.decodeStructuredOutput(
                content,
                request: request
            )
        }
        throw V2PlanningClientError.missingOutput
    }
}

public extension V2OpenAICompatiblePlanningClient where Transport == V2URLSessionPlanningTransport {
    init(configuration: V2OpenAICompatiblePlanningConfiguration) {
        self.init(configuration: configuration, transport: V2URLSessionPlanningTransport())
    }
}

private extension V2OpenAICompatiblePlanningClient {
    struct ResponseEnvelope: Decodable {
        var choices: [Choice]
    }

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String?
        var refusal: String?
    }

    static func requestBody(
        configuration: V2OpenAICompatiblePlanningConfiguration,
        request: V2PlanningRequest
    ) -> [String: Any] {
        let userPayload: [String: Any] = [
            "request": V2RemotePlanningClient<Transport>.planningInput(request),
            "output_schema": V2RemotePlanningClient<Transport>.structuredOutputSchema,
        ]
        let userContent = String(
            data: try! JSONSerialization.data(withJSONObject: userPayload, options: [.sortedKeys]),
            encoding: .utf8
        )!

        return [
            "model": configuration.model,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    \(V2RemotePlanningClient<Transport>.systemInstructions)
                    你必须只返回符合 output_schema 的 JSON 对象，不要使用 Markdown 代码块。
                    """,
                ],
                [
                    "role": "user",
                    "content": userContent,
                ],
            ],
            "response_format": ["type": "json_object"],
            "stream": false,
            "max_tokens": 4_096,
        ]
    }
}

fileprivate extension V2RemotePlanningClient {
    struct ResponseEnvelope: Decodable {
        var output: [Output]
    }

    struct Output: Decodable {
        var type: String
        var content: [Content]?
    }

    struct Content: Decodable {
        var type: String
        var text: String?
        var refusal: String?
    }

    struct StructuredOutput: Decodable {
        var kind: String
        var message: String
        var suggestedReplies: [String]
        var title: String
        var summary: String
        var decisions: [String]
        var taskChanges: [TaskChange]
        var scheduleItems: [ScheduleItem]

        enum CodingKeys: String, CodingKey {
            case kind
            case message
            case suggestedReplies = "suggested_replies"
            case title
            case summary
            case decisions
            case taskChanges = "task_changes"
            case scheduleItems = "schedule_items"
        }
    }

    struct TaskChange: Decodable {
        var temporaryID: String
        var title: String
        var parentID: String?
        var contextID: String?
        var kind: V2Task.Kind?

        enum CodingKeys: String, CodingKey {
            case temporaryID = "temporary_id"
            case title
            case parentID = "parent_id"
            case contextID = "context_id"
            case kind
        }
    }

    struct ScheduleItem: Decodable {
        var temporaryID: String
        var dayOffset: Int
        var startMinute: Int?
        var durationMinutes: Int?
        var existingTaskID: String?
        var proposedTaskID: String?
        var title: String

        enum CodingKeys: String, CodingKey {
            case temporaryID = "temporary_id"
            case dayOffset = "day_offset"
            case startMinute = "start_minute"
            case durationMinutes = "duration_minutes"
            case existingTaskID = "existing_task_id"
            case proposedTaskID = "proposed_task_id"
            case title
        }
    }

    static func decodeStructuredOutput(
        _ text: String,
        request: V2PlanningRequest
    ) throws -> V2PlanningOutcome {
        let output: StructuredOutput
        do {
            output = try JSONDecoder().decode(StructuredOutput.self, from: Data(text.utf8))
        } catch {
            throw V2PlanningClientError.invalidOutput("结构化内容无法解析")
        }

        let message = try nonempty(output.message, field: "message")
        switch output.kind {
        case "clarification":
            return .clarification(
                V2PlanningClarification(
                    question: message,
                    suggestedReplies: output.suggestedReplies
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .prefix(3)
                        .map { $0 }
                )
            )
        case "proposal":
            break
        default:
            throw V2PlanningClientError.invalidOutput("kind 必须是 clarification 或 proposal")
        }

        let knownTaskIDs = Set(request.tasks.map(\.id))
        let proposedIDs = Set(output.taskChanges.map(\.temporaryID))
        guard proposedIDs.count == output.taskChanges.count else {
            throw V2PlanningClientError.invalidOutput("任务临时 ID 重复")
        }

        let taskChanges = try output.taskChanges.map { item in
            let id = try nonempty(item.temporaryID, field: "task_changes.temporary_id")
            let title = try nonempty(item.title, field: "task_changes.title")
            if let parentID = item.parentID,
               !knownTaskIDs.contains(parentID),
               !proposedIDs.contains(parentID) {
                throw V2PlanningClientError.invalidOutput("任务父节点不存在：\(parentID)")
            }
            return V2PlanDraftTaskChange(
                id: id,
                title: title,
                parentID: item.parentID,
                contextID: item.contextID,
                kind: item.kind
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .current
        let referenceDay = calendar.startOfDay(for: request.referenceDate)
        let scheduleItems = try output.scheduleItems.map { item in
            guard (0...366).contains(item.dayOffset) else {
                throw V2PlanningClientError.invalidOutput("day_offset 超出可规划范围")
            }
            guard let day = calendar.date(byAdding: .day, value: item.dayOffset, to: referenceDay) else {
                throw V2PlanningClientError.invalidOutput("无法计算计划日期")
            }
            if let existingTaskID = item.existingTaskID,
               !knownTaskIDs.contains(existingTaskID) {
                throw V2PlanningClientError.invalidOutput("引用了不存在的任务：\(existingTaskID)")
            }
            if let proposedTaskID = item.proposedTaskID,
               !proposedIDs.contains(proposedTaskID) {
                throw V2PlanningClientError.invalidOutput("引用了不存在的候选任务：\(proposedTaskID)")
            }
            guard item.existingTaskID == nil || item.proposedTaskID == nil else {
                throw V2PlanningClientError.invalidOutput("计划项不能同时引用现有任务和候选任务")
            }

            let startAt: Date?
            let endAt: Date?
            if let startMinute = item.startMinute {
                guard (0...1_439).contains(startMinute) else {
                    throw V2PlanningClientError.invalidOutput("start_minute 超出当天范围")
                }
                guard let start = calendar.date(byAdding: .minute, value: startMinute, to: day) else {
                    throw V2PlanningClientError.invalidOutput("无法计算开始时间")
                }
                let duration = item.durationMinutes ?? 30
                guard (15...720).contains(duration) else {
                    throw V2PlanningClientError.invalidOutput("duration_minutes 必须在 15 到 720 之间")
                }
                startAt = start
                endAt = calendar.date(byAdding: .minute, value: duration, to: start)
            } else {
                guard item.durationMinutes == nil else {
                    throw V2PlanningClientError.invalidOutput("没有开始时间时不能设置时长")
                }
                startAt = nil
                endAt = nil
            }

            return V2PlanDraftScheduleItem(
                id: try nonempty(item.temporaryID, field: "schedule_items.temporary_id"),
                date: day,
                startAt: startAt,
                endAt: endAt,
                taskID: item.existingTaskID,
                proposedTaskID: item.proposedTaskID,
                title: try nonempty(item.title, field: "schedule_items.title")
            )
        }

        guard !taskChanges.isEmpty || !scheduleItems.isEmpty else {
            throw V2PlanningClientError.invalidOutput("草稿没有任务变化或计划项")
        }

        return .proposal(
            V2PlanningProposal(
                message: message,
                draft: V2PlanDraft(
                    id: request.currentDraft?.id ?? UUID().uuidString,
                    userPrompt: request.userPrompt,
                    title: try nonempty(output.title, field: "title"),
                    summary: try nonempty(output.summary, field: "summary"),
                    decisions: output.decisions,
                    taskChanges: taskChanges,
                    scheduleItems: scheduleItems
                )
            )
        )
    }

    static func nonempty(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw V2PlanningClientError.invalidOutput("\(field) 不能为空")
        }
        return trimmed
    }

    static func requestBody(
        configuration: V2RemotePlanningConfiguration,
        request: V2PlanningRequest
    ) -> [String: Any] {
        let input = planningInput(request)

        return [
            "model": configuration.model,
            "store": false,
            "instructions": systemInstructions,
            "input": String(data: try! JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]), encoding: .utf8)!,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "tough_trial_plan",
                    "strict": true,
                    "schema": structuredOutputSchema,
                ],
            ],
        ]
    }

    static func planningInput(_ request: V2PlanningRequest) -> [String: Any] {
        [
            "user_prompt": request.userPrompt,
            "clarification_response": request.clarificationResponse ?? NSNull(),
            "scope": request.scope ?? NSNull(),
            "reference_date": ISO8601DateFormatter().string(from: request.referenceDate),
            "time_zone": request.timeZoneIdentifier,
            "tasks": request.tasks.prefix(100).map { task in
                [
                    "id": task.id,
                    "title": task.title,
                    "parent_id": task.parentID ?? NSNull(),
                    "context_id": task.contextID ?? NSNull(),
                    "kind": task.kind?.rawValue ?? NSNull(),
                    "status": task.status.rawValue,
                ] as [String: Any]
            },
            "memory_statements": Array(request.memoryStatements.prefix(30)),
            "current_draft": request.currentDraft.map { draft in
                [
                    "title": draft.title,
                    "summary": draft.summary,
                    "decisions": draft.decisions,
                    "tasks": draft.taskChanges.map {
                        [
                            "temporary_id": $0.id,
                            "title": $0.title,
                            "parent_id": $0.parentID ?? NSNull(),
                            "context_id": $0.contextID ?? NSNull(),
                            "kind": $0.kind?.rawValue ?? NSNull(),
                        ] as [String: Any]
                    },
                    "schedule": draft.scheduleItems.map {
                        [
                            "temporary_id": $0.id,
                            "date": ISO8601DateFormatter().string(from: $0.date),
                            "task_id": $0.taskID ?? NSNull(),
                            "proposed_task_id": $0.proposedTaskID ?? NSNull(),
                            "title": $0.title,
                        ] as [String: Any]
                    },
                ] as [String: Any]
            } ?? NSNull(),
        ]
    }

    static var systemInstructions: String {
        """
        你是 Tough Trial 的轻量计划助手。先判断是否需要澄清，再返回候选计划。
        不替用户决定如何执行，不做容量冲突或任务替换，不把任何内容视为已保存。
        可以同时建议拆解任务与安排日期；已有任务只能使用输入中给出的 ID。
        day_offset 从 reference_date 的当天算起。没有明确时间时使用 null。
        """
    }

    static var structuredOutputSchema: [String: Any] {
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "kind", "message", "suggested_replies", "title", "summary",
                "decisions", "task_changes", "schedule_items",
            ],
            "properties": [
                "kind": ["type": "string", "enum": ["clarification", "proposal"]],
                "message": ["type": "string"],
                "suggested_replies": [
                    "type": "array",
                    "items": ["type": "string"],
                    "maxItems": 3,
                ],
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "decisions": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
                "task_changes": [
                    "type": "array",
                    "maxItems": 20,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["temporary_id", "title", "parent_id", "context_id", "kind"],
                        "properties": [
                            "temporary_id": ["type": "string"],
                            "title": ["type": "string"],
                            "parent_id": nullableString,
                            "context_id": nullableString,
                            "kind": [
                                "type": ["string", "null"],
                                "enum": ["goal", "commitment", "maintenance", NSNull()],
                            ],
                        ],
                    ],
                ],
                "schedule_items": [
                    "type": "array",
                    "maxItems": 31,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": [
                            "temporary_id", "day_offset", "start_minute", "duration_minutes",
                            "existing_task_id", "proposed_task_id", "title",
                        ],
                        "properties": [
                            "temporary_id": ["type": "string"],
                            "day_offset": ["type": "integer", "minimum": 0, "maximum": 366],
                            "start_minute": ["type": ["integer", "null"], "minimum": 0, "maximum": 1_439],
                            "duration_minutes": ["type": ["integer", "null"], "minimum": 15, "maximum": 720],
                            "existing_task_id": nullableString,
                            "proposed_task_id": nullableString,
                            "title": ["type": "string"],
                        ],
                    ],
                ],
            ],
        ]
    }

    static func serverErrorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return "服务器拒绝了请求"
        }
        return message
    }
}
