import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2DynamicToolTests: XCTestCase {
    func testCatalogScopesPluginAndBackgroundCallers() throws {
        let runtime = V2ModuleRuntime()

        let plugin = V2ToolCatalogBuilder.make(runtime: runtime, caller: .plugin)
        XCTAssertEqual(plugin.tools.map(\.id), ["core.capture.create"])
        XCTAssertTrue(plugin.tools.allSatisfy { !$0.id.contains("finance") && !$0.id.contains("ledger") })

        let background = V2ToolCatalogBuilder.make(runtime: runtime, caller: .background)
        XCTAssertFalse(background.tools.isEmpty)
        XCTAssertTrue(background.tools.allSatisfy(\.readOnly))
    }

    func testCatalogIncludesActiveAdditionalModuleDescriptorWithBoundedSchema() throws {
        let runtime = V2ModuleRuntime(descriptors: [
            V2ModuleDescriptor(id: "community.mood", name: "心情扩展")
        ])
        let descriptor = V2ToolDescriptor(
            id: "community.mood.record",
            moduleID: "community.mood",
            title: "记录心情",
            purpose: "保存一条简短的心情记录。",
            inputSchema: .init(fields: [
                .init(id: "mood", label: "心情", type: .enumID, required: true, enumValues: ["calm", "tired"]),
                .init(id: "note", label: "补充", type: .text, maxLength: 240)
            ]),
            canUndo: true
        )

        let catalog = V2ToolCatalogBuilder.make(runtime: runtime, additional: [descriptor])
        let selected = try XCTUnwrap(catalog.tool(descriptor.id))
        XCTAssertEqual(selected.inputSchema.fields.map(\.id), ["mood", "note"])
        XCTAssertEqual(selected.inputSchema.field("mood")?.enumValues, ["calm", "tired"])
        XCTAssertThrowsError(
            try V2ToolArguments.parse(Data(#"{"mood":"calm","operationID":"host"}"#.utf8), using: selected.inputSchema)
        ) { error in
            XCTAssertEqual(error as? V2ToolSchemaError, .forbiddenField("operationID"))
        }
    }

    func testCatalogRevisionIncludesExecutionPolicyAndSchemaFlags() {
        let runtime = V2ModuleRuntime(descriptors: [
            V2ModuleDescriptor(id: "community.mood", name: "心情扩展")
        ])
        let base = V2ToolDescriptor(
            id: "community.mood.record",
            moduleID: "community.mood",
            title: "记录心情",
            purpose: "保存一条心情。",
            inputSchema: .init(fields: [
                .init(id: "text", label: "内容", type: .text, required: true)
            ]),
            canUndo: false
        )
        let undoable = V2ToolDescriptor(
            id: base.id,
            moduleID: base.moduleID,
            title: base.title,
            purpose: base.purpose,
            inputSchema: base.inputSchema,
            canUndo: true
        )
        let first = V2ToolCatalogBuilder.make(runtime: runtime, additional: [base])
        let second = V2ToolCatalogBuilder.make(runtime: runtime, additional: [undoable])
        XCTAssertNotEqual(first.revision, second.revision)
    }

    func testCatalogScopesToolsToActiveModules() throws {
        let runtime = V2ModuleRuntime()
        let catalog = V2ToolCatalogBuilder.make(runtime: runtime)
        XCTAssertNotNil(catalog.tool("core.tasks.create"))
        XCTAssertNotNil(catalog.tool("core.finance.createPlan"))
        XCTAssertNotNil(catalog.tool("core.ledger.proposeCategory"))

        var preferences = runtime.preferences
        preferences.disabled.insert("core.finance")
        runtime.update(preferences: preferences)
        let disabled = V2ToolCatalogBuilder.make(runtime: runtime)
        XCTAssertNil(disabled.tool("core.finance.createPlan"))
        XCTAssertNil(disabled.tool("core.finance.markPaid"))
        XCTAssertNotNil(disabled.tool("core.tasks.create"))
        XCTAssertNotEqual(catalog.revision, disabled.revision)
    }

    func testArgumentsRejectUnknownAndHostAuthorityFields() throws {
        let runtime = V2ModuleRuntime()
        let catalog = V2ToolCatalogBuilder.make(runtime: runtime)
        let descriptor = try XCTUnwrap(catalog.tool("core.tasks.create"))

        XCTAssertThrowsError(
            try V2ToolArguments.parse(
                Data(#"{"title":"买牛奶","operationID":"host"}"#.utf8),
                using: descriptor.inputSchema
            )
        ) { error in
            XCTAssertEqual(error as? V2ToolSchemaError, .forbiddenField("operationID"))
        }
        XCTAssertThrowsError(
            try V2ToolArguments.parse(
                Data(#"{"title":"买牛奶","unknown":"不要写入"}"#.utf8),
                using: descriptor.inputSchema
            )
        ) { error in
            XCTAssertEqual(error as? V2ToolSchemaError, .unknownToolField("unknown"))
        }
        XCTAssertThrowsError(
            try V2ToolArguments.parse(Data(#"{"note":"没有标题"}"#.utf8), using: descriptor.inputSchema)
        ) { error in
            XCTAssertEqual(error as? V2ToolSchemaError, .missingRequiredField("title"))
        }
    }

    func testAdditionalPropertiesStillRejectNestedAuthorityFields() throws {
        let schema = V2ToolInputSchema(
            fields: [
                .init(id: "title", label: "标题", type: .text, required: true)
            ],
            allowsAdditionalProperties: true
        )
        XCTAssertThrowsError(
            try V2ToolArguments.parse(
                Data(#"{"title":"记录","metadata":{"operationID":"host"}}"#.utf8),
                using: schema
            )
        ) { error in
            XCTAssertEqual(error as? V2ToolSchemaError, .forbiddenField("operationID"))
        }
    }

    func testToolCallValidationUsesExactCatalogAndStableHostIdentity() throws {
        let runtime = V2ModuleRuntime()
        let catalog = V2ToolCatalogBuilder.make(runtime: runtime)
        let call = V2AgentToolCall(
            toolID: "core.tasks.create",
            argumentsJSON: Data(#"{"title":"买牛奶"}"#.utf8),
            modelCallID: "provider-call-id"
        )
        let (descriptor, arguments) = try catalog.validate(call)
        XCTAssertEqual(descriptor.id, "core.tasks.create")
        XCTAssertEqual(arguments.string("title"), "买牛奶")

        let context = V2ToolExecutionContext(
            traceID: "trace-1",
            assistantRequestID: "message-1",
            attemptID: "attempt-1",
            callOrdinal: 0,
            toolID: "core.tasks.create"
        )
        XCTAssertEqual(context.operationID, "assistant.message-1.tool.core.tasks.create.0")
        XCTAssertEqual(context.idempotencyKey, "message-1:core.tasks.create:0")
        XCTAssertFalse(context.operationID.contains("provider-call-id"))
    }

    func testAgentRequestPublishesOnlyCatalogToolsAndToolActionDecodes() throws {
        let runtime = V2ModuleRuntime()
        let catalog = V2ToolCatalogBuilder.make(runtime: runtime)
        let client = V2OpenAICompatibleAgentClient(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "secret",
                model: "fixture",
                providerLabel: "fixture"
            ),
            transport: DynamicToolTransport()
        )
        let request = V2AgentRequest(
            userText: "创建买牛奶任务",
            conversation: [],
            observations: [],
            toolCatalog: catalog
        )
        let urlRequest = try client.makeURLRequest(for: request)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { ($0["function"] as? [String: Any])?["name"] as? String == V2OpenAICompatibleAgentClient<DynamicToolTransport>.wireName(for: "core.tasks.create") })
        XCTAssertNil(body["tool_catalog_revision"])
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
        let content = String(
            data: try JSONSerialization.data(withJSONObject: [
                "action": "tool",
                "text": "",
                "query": "",
                "url": "",
                "tool": "core.tasks.create",
                "arguments": ["title": "买牛奶"]
            ], options: [.sortedKeys]),
            encoding: .utf8
        )!
        let result = try client.decodeResponse(
            Data(String(data: try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content]]]
            ], options: [.sortedKeys]), encoding: .utf8)!.utf8)
        )
        guard case let .toolCall(decoded) = result.action else {
            return XCTFail("expected dynamic tool call")
        }
        XCTAssertEqual(decoded.toolID, "core.tasks.create")
        XCTAssertEqual(decoded.modelCallID, nil)
        XCTAssertEqual(try V2ToolArguments.parse(decoded.argumentsJSON, using: catalog.tool("core.tasks.create")!.inputSchema).string("title"), "买牛奶")
    }

    func testAgentClientAcceptsOpenAIFunctionToolCall() throws {
        let client = V2OpenAICompatibleAgentClient(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "secret",
                model: "fixture",
                providerLabel: "fixture"
            ),
            transport: DynamicToolTransport()
        )
        let response: [String: Any] = [
            "id": "response-tool",
            "choices": [["message": [
                "tool_calls": [[
                    "id": "call-1",
                    "type": "function",
                    "function": ["name": "core.tasks.create", "arguments": #"{"title":"买牛奶"}"#]
                ]]
            ]]]
        ]
        let result = try client.decodeResponse(JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]))
        guard case let .toolCall(call) = result.action else {
            return XCTFail("expected function-style tool call")
        }
        XCTAssertEqual(call.toolID, "core.tasks.create")
        XCTAssertEqual(call.modelCallID, "call-1")
    }

    @MainActor
    func testExecutionRegistryRejectsStaleCatalogAndBindsHostIdentity() async throws {
        let runtime = V2ModuleRuntime()
        let registry = try V2ToolExecutionRegistry(runtime: runtime)
        try registry.register(V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.tasks.create" })!) { arguments, context in
            V2ToolExecutionResult(
                toolID: "core.tasks.create",
                state: .applied,
                operationID: context.operationID,
                idempotencyKey: context.idempotencyKey,
                summary: "已创建：" + (arguments.string("title") ?? "")
            )
        }
        let catalog = registry.catalog()
        let call = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"买牛奶"}"#.utf8))
        let context = V2ToolExecutionContext(traceID: "trace", assistantRequestID: "message", callOrdinal: 0, toolID: "core.tasks.create")
        let result = try await registry.execute(call, context: context, expectedCatalog: catalog)
        XCTAssertEqual(result.operationID, context.operationID)
        XCTAssertTrue(result.summary.contains("买牛奶"))

        var preferences = runtime.preferences
        preferences.disabled.insert("core.tasks")
        runtime.update(preferences: preferences)
        do {
            _ = try await registry.execute(call, context: context, expectedCatalog: catalog)
            XCTFail("expected stale catalog")
        } catch V2ToolRegistryError.staleCatalog {
            // Expected: disabling the owning module invalidates the catalog.
        }
    }

    @MainActor
    func testRegistryUsesCallerScopeAndKeepsConfirmationAtHostBoundary() async throws {
        let runtime = V2ModuleRuntime()
        let registry = try V2ToolExecutionRegistry(runtime: runtime)
        let task = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.tasks.create" })
        )
        let query = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.tasks.query" })
        )
        let payment = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.finance.markPaid" })
        )
        var writes = 0
        try registry.register(task) { _, context in
            writes += 1
            return V2ToolExecutionResult(
                toolID: task.id,
                state: .applied,
                operationID: context.operationID,
                idempotencyKey: context.idempotencyKey,
                summary: "已创建"
            )
        }
        try registry.register(query) { _, context in
            V2ToolExecutionResult(
                toolID: query.id,
                state: .applied,
                operationID: context.operationID,
                idempotencyKey: context.idempotencyKey,
                summary: "查询完成"
            )
        }
        try registry.register(payment) { _, context in
            writes += 1
            return V2ToolExecutionResult(
                toolID: payment.id,
                state: .applied,
                operationID: context.operationID,
                idempotencyKey: context.idempotencyKey,
                summary: "已标记"
            )
        }

        let pluginCall = V2AgentToolCall(
            toolID: task.id,
            argumentsJSON: Data(#"{"title":"插件不应创建任务"}"#.utf8)
        )
        let pluginContext = V2ToolExecutionContext(
            traceID: "trace-plugin",
            assistantRequestID: "message-plugin",
            callOrdinal: 0,
            toolID: task.id,
            actor: .plugin
        )
        do {
            _ = try await registry.execute(
                pluginCall,
                context: pluginContext,
                expectedCatalog: registry.catalog(caller: .plugin)
            )
            XCTFail("plugin should not receive task creation")
        } catch V2ToolSchemaError.unknownTool {
            XCTAssertEqual(writes, 0)
        }

        let queryCall = V2AgentToolCall(
            toolID: query.id,
            argumentsJSON: Data(#"{"query":"今天","limit":1}"#.utf8)
        )
        let backgroundContext = V2ToolExecutionContext(
            traceID: "trace-background",
            assistantRequestID: "message-background",
            callOrdinal: 0,
            toolID: query.id,
            actor: .background
        )
        let queryResult = try await registry.execute(
            queryCall,
            context: backgroundContext,
            expectedCatalog: registry.catalog(caller: .background)
        )
        XCTAssertEqual(queryResult.state, .applied)
        XCTAssertEqual(writes, 0)

        let paymentCall = V2AgentToolCall(
            toolID: payment.id,
            argumentsJSON: Data(#"{"planReference":"ChatGPT","dueDate":"2026-10-01"}"#.utf8)
        )
        let hostContext = V2ToolExecutionContext(
            traceID: "trace-host",
            assistantRequestID: "message-host",
            callOrdinal: 0,
            toolID: payment.id
        )
        let paymentResult = try await registry.execute(paymentCall, context: hostContext)
        XCTAssertEqual(paymentResult.state, .applied)
        XCTAssertEqual(writes, 1)
    }

    @MainActor
    func testUndoRechecksCurrentModuleAvailability() async throws {
        let runtime = V2ModuleRuntime()
        let registry = try V2ToolExecutionRegistry(runtime: runtime)
        let descriptor = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.tasks.create" })
        )
        try registry.register(descriptor) { _, context in
            V2ToolExecutionResult(
                toolID: descriptor.id,
                state: .applied,
                operationID: context.operationID,
                idempotencyKey: context.idempotencyKey,
                summary: "已创建",
                undoReference: "undo"
            )
        }
        try registry.registerUndo(for: descriptor) { result, context in
            V2ToolExecutionResult(
                toolID: result.toolID,
                state: .undone,
                operationID: context.operationID,
                idempotencyKey: context.idempotencyKey,
                summary: "已撤销"
            )
        }
        let call = V2AgentToolCall(toolID: descriptor.id, argumentsJSON: Data(#"{"title":"买牛奶"}"#.utf8))
        let context = V2ToolExecutionContext(
            traceID: "trace-undo",
            assistantRequestID: "message-undo",
            callOrdinal: 0,
            toolID: descriptor.id
        )
        let result = try await registry.execute(call, context: context)
        var preferences = runtime.preferences
        preferences.disabled.insert("core.tasks")
        runtime.update(preferences: preferences)
        do {
            _ = try await registry.undo(result)
            XCTFail("undo should be blocked after the module is disabled")
        } catch V2ToolRegistryError.undoUnavailable {
            // Expected: an undo must pass through the current module gate.
        }
    }

    func testFinancialSourcePolicyRequiresEvidenceAndExposesConfirmationMetadata() throws {
        let runtime = V2ModuleRuntime()
        let descriptor = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.ledger.createPending" })
        )
        XCTAssertEqual(descriptor.confirmationPolicy, .automatic)
        let call = V2AgentToolCall(
            toolID: descriptor.id,
            argumentsJSON: Data(#"{"description":"午餐","amount":38,"currency":"CNY","date":"2026-09-10"}"#.utf8)
        )
        let (_, arguments) = try V2ToolCatalogBuilder.make(runtime: runtime).validate(call)

        let missingDate = V2ToolSourcePolicy.missingInformation(
            for: descriptor,
            arguments: arguments,
            context: V2ToolExecutionContext(
                traceID: "trace-missing",
                assistantRequestID: "message-missing",
                callOrdinal: 0,
                toolID: descriptor.id,
                submittedText: "午餐花了 38 元"
            )
        )
        XCTAssertNotNil(missingDate)

        let hallucinatedAmount = V2ToolSourcePolicy.missingInformation(
            for: descriptor,
            arguments: try V2ToolArguments.parse(
                Data(#"{"description":"午餐","amount":380,"currency":"CNY","date":"2026-09-10"}"#.utf8),
                using: descriptor.inputSchema
            ),
            context: V2ToolExecutionContext(
                traceID: "trace-hallucinated",
                assistantRequestID: "message-hallucinated",
                callOrdinal: 0,
                toolID: descriptor.id,
                submittedText: "午餐花了 38 元，2026-09-10"
            )
        )
        XCTAssertNotNil(hallucinatedAmount)

        let evidenced = V2ToolSourcePolicy.missingInformation(
            for: descriptor,
            arguments: arguments,
            context: V2ToolExecutionContext(
                traceID: "trace-evidenced",
                assistantRequestID: "message-evidenced",
                callOrdinal: 0,
                toolID: descriptor.id,
                submittedText: "午餐花了 38 元，2026-09-10"
            )
        )
        XCTAssertNil(evidenced)

        let proposal = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.ledger.proposeCategory" })
        )
        XCTAssertEqual(proposal.confirmationPolicy, .humanAlways)
        let payment = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.finance.markPaid" })
        )
        XCTAssertEqual(payment.confirmationPolicy, .humanAlways)
    }

    func testDateCurrencyAndIntentPoliciesRejectAmbiguousEvidence() throws {
        let finance = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.finance.createPlan" })
        )
        let financeArgs = try V2ToolArguments.parse(
            Data(#"{"title":"ChatGPT","amount":20,"currency":"USD","dueDate":"2026-10-01","kind":"subscription"}"#.utf8),
            using: finance.inputSchema
        )
        let discussionMessage = V2ToolSourcePolicy.missingInformation(
            for: finance,
            arguments: financeArgs,
            context: V2ToolExecutionContext(
                traceID: "trace-discussion",
                assistantRequestID: "message-discussion",
                callOrdinal: 0,
                toolID: finance.id,
                submittedText: "我们讨论一下 ChatGPT 每月 20 美元，2026-10-01 要不要订阅。",
                intent: .discussion
            )
        )
        XCTAssertNotNil(discussionMessage)

        let ambiguousCurrency = V2ToolSourcePolicy.missingInformation(
            for: finance,
            arguments: financeArgs,
            context: V2ToolExecutionContext(
                traceID: "trace-currency",
                assistantRequestID: "message-currency",
                callOrdinal: 0,
                toolID: finance.id,
                submittedText: "ChatGPT 每月 20 美元，2026-10-01。"
            )
        )
        XCTAssertNil(ambiguousCurrency)

        let ledger = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.ledger.createPending" })
        )
        XCTAssertThrowsError(
            try V2ToolArguments.parse(
                Data(#"{"description":"午餐","amount":38,"currency":"CNY","date":"今天"}"#.utf8),
                using: ledger.inputSchema
            )
        ) { error in
            guard case V2ToolSchemaError.invalidField("date", _) = error else {
                return XCTFail("expected strict ISO date validation, got \(error)")
            }
        }

        let markPaid = try XCTUnwrap(
            V2ToolCatalogBuilder.builtinTools.first(where: { $0.id == "core.finance.markPaid" })
        )
        let paidArgs = try V2ToolArguments.parse(
            Data(#"{"planReference":"ChatGPT","dueDate":"2026-10-01"}"#.utf8),
            using: markPaid.inputSchema
        )
        let unpaid = V2ToolSourcePolicy.missingInformation(
            for: markPaid,
            arguments: paidArgs,
            context: V2ToolExecutionContext(
                traceID: "trace-unpaid",
                assistantRequestID: "message-unpaid",
                callOrdinal: 0,
                toolID: markPaid.id,
                submittedText: "ChatGPT 到期日是 2026-10-01。"
            )
        )
        XCTAssertNotNil(unpaid)
    }

    func testExecutionResultRetainsSafeRetryPayloadWithoutChangingIdentity() throws {
        let call = V2AgentToolCall(
            toolID: "core.tasks.create",
            argumentsJSON: Data(#"{"title":"买牛奶"}"#.utf8),
            modelCallID: "provider-call"
        )
        let context = V2ToolExecutionContext(
            traceID: "trace",
            assistantRequestID: "message",
            attemptID: "attempt-1",
            callOrdinal: 2,
            toolID: call.toolID
        )
        let result = V2ToolExecutionResult(
            toolID: call.toolID,
            state: .failed,
            operationID: context.operationID,
            idempotencyKey: context.idempotencyKey,
            summary: "暂时失败"
        ).bound(to: call, context: context)
        let restored = try JSONDecoder().decode(
            V2ToolExecutionResult.self,
            from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(restored.operationID, context.operationID)
        XCTAssertEqual(restored.idempotencyKey, context.idempotencyKey)
        XCTAssertEqual(restored.argumentsJSON, call.argumentsJSON)
        XCTAssertEqual(restored.assistantRequestID, "message")
        XCTAssertEqual(restored.callOrdinal, 2)
    }
}

private struct DynamicToolTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
