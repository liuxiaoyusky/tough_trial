import Foundation
import ToughTrialV2Core

extension V2AppStore {
    func bindDynamicTools(to dependencies: inout V2AssistantDependencies) {
        dependencies.toolExecutorForSnapshot = { [weak self] snapshot in
            guard let self else { return { _, _ in throw V2AssistantTurnError.toolUnavailable } }
            var pinned = self.makeBaseAssistantDependencies()
            pinned.modelSnapshot = { snapshot }
            self.bindDynamicTools(to: &pinned)
            return pinned.executeTool
        }
        let modelSnapshot = dependencies.modelSnapshot
        dependencies.toolCatalog = { [weak self] in
            guard let self else { throw V2AssistantTurnError.toolUnavailable }
            let base = self.engine.registeredToolCatalog()
            return V2ToolCatalogBuilder.make(runtime: self.engine.moduleRuntime,
                additional: base.tools.filter { !Set(V2ToolCatalogBuilder.builtinTools.map(\.id)).contains($0.id) } + V2AssistantContextTools.descriptors,
                registeredToolIDs: Set(base.tools.map(\.id)).union(V2AssistantContextTools.ids))
        }
        dependencies.contextMemories = { [weak self] reference, date in
            guard let self, self.engine.moduleRuntime.availability("core.notes").isActive else { return [] }
            return self.memoryEngine.activeRecords(taskID: reference?.id, contextID: reference?.contextID, at: date)
        }
        dependencies.allMemoryRecords = { [weak self] in
            guard let self, self.engine.moduleRuntime.availability("core.notes").isActive else { return [] }
            return self.memoryEngine.snapshot.records
        }
        dependencies.recoverToolOperations = { [weak self] requestID in
            self?.engine.snapshot.toolOperations.filter { $0.result.assistantRequestID == requestID }.map(\.result) ?? []
        }
        dependencies.executeTool = { [weak self] call, context in
            guard let self, self.canWrite else { throw V2AssistantTurnError.persistenceUnavailable }
            let catalog = self.engine.registeredToolCatalog()
            let (descriptor, _) = try catalog.validate(call)
            let ticket = try self.engine.moduleRuntime.ticket(for: descriptor.requiredModules + ["core.assistant"])
            var proposal: V2ScheduleProposal?
            if call.toolID == "core.tasks.schedule",
               self.engine.snapshot.toolOperations.contains(where: { $0.id == context.operationID }) == false {
                guard context.intent == .explicitWrite else {
                    return .init(toolID: call.toolID, state: .blocked, operationID: context.operationID,
                        idempotencyKey: context.idempotencyKey, summary: "本轮没有明确的日程修改请求，未改动任务。").bound(to: call, context: context)
                }
                let baseline = self.engine.snapshot
                let model = try modelSnapshot()
                let outcome = try await model.generateSchedule(.init(userText: context.submittedText,
                    conversation: context.conversation, snapshot: baseline, referenceDate: Date(), timeZoneIdentifier: self.calendar.timeZone.identifier,
                    context: context.assistantContext ?? .init()))
                try self.engine.moduleRuntime.validate(ticket)
                guard baseline.tasks == self.engine.snapshot.tasks, baseline.planItems == self.engine.snapshot.planItems,
                      baseline.taskContexts == self.engine.snapshot.taskContexts,
                      baseline.executionSegments == self.engine.snapshot.executionSegments else { throw V2RegisteredToolError.conflict }
                switch outcome {
                case let .proposal(value): proposal = V2AssistantScheduleContext.preservingToday(value,
                    userText: context.submittedText, at: Date(), timeZoneIdentifier: self.calendar.timeZone.identifier)
                case let .clarification(question):
                    return .init(toolID: call.toolID, state: .needsInformation, operationID: context.operationID,
                        idempotencyKey: context.idempotencyKey, summary: question).bound(to: call, context: context)
                }
            }
            try self.engine.moduleRuntime.validate(ticket)
            let result: V2ToolExecutionResult
            do {
                result = try self.engine.executeRegisteredTool(call, context: context,
                    requiresConfirmation: V2ScheduleSettings.requiresConfirmation,
                    scheduleProposal: proposal, calendar: self.calendar)
            } catch {
                // Keep a retryable card; a committed receipt always wins after a
                // response/save interruption, so retry never repeats a write.
                if let saved = self.engine.snapshot.toolOperations.first(where: { $0.id == context.operationID }) {
                    return saved.result
                }
                let state: V2ToolExecutionState = error is V2RegisteredToolError ? .needsInformation : .failed
                let failed = V2ToolExecutionResult(toolID: call.toolID, state: state, operationID: context.operationID,
                    idempotencyKey: context.idempotencyKey, summary: (error as? LocalizedError)?.errorDescription ?? "操作尚未保存，请重试。")
                    .bound(to: call, context: context)
                self.didExecuteTool(failed)
                return failed
            }
            self.didExecuteTool(result)
            return result
        }
        dependencies.confirmTool = { [weak self] result in
            guard let self, self.canWrite else { throw V2AssistantTurnError.persistenceUnavailable }
            try self.engine.moduleRuntime.require(["core.assistant"])
            let updated = try self.engine.confirmRegisteredTool(operationID: result.operationID, calendar: self.calendar)
            self.didExecuteTool(updated)
            return updated
        }
        dependencies.undoTool = { [weak self] result in
            guard let self, self.canWrite else { throw V2AssistantTurnError.persistenceUnavailable }
            try self.engine.moduleRuntime.require(["core.assistant"])
            let updated = try self.engine.undoRegisteredTool(operationID: result.operationID)
            self.didExecuteTool(updated)
            return updated
        }
    }

    private func didExecuteTool(_ result: V2ToolExecutionResult) {
        if result.toolID.hasPrefix("core.tasks.") {
            highlightedScheduleIDs = result.state == .applied ? Set(result.entityReferences) : []
        }
        refreshProjection(at: Date())
        V2UsageTrace.shared.record(.init(kind: result.state == .applied ? .commandApplied : result.state == .pendingConfirmation ? .commandProposed : result.state == .undone ? .commandUndone : .commandBlocked,
            source: .assistant, operationID: result.operationID,
            moduleID: result.toolID.split(separator: ".").prefix(2).joined(separator: "."),
            commandID: result.toolID, traceID: result.traceID))
        Task { [weak self] in await self?.drainModuleOutbox() }
    }
}
