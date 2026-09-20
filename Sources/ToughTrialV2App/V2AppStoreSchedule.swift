import Foundation
import SwiftUI
import ToughTrialV2Core

extension V2AppStore {
    func makeAssistantDependencies() -> V2AssistantDependencies {
        var dependencies = makeBaseAssistantDependencies()
        dependencies.selectedModelSnapshot = { [weak self] selection in
            guard let self else { throw V2AssistantTurnError.scheduleUnavailable }
            return try self.assistantModelSnapshot(selection: selection)
        }
        dependencies.selectedProviderStatus = { [weak self] selection in
            guard let self, let provider = V2AIProviderPreset(rawValue: selection.providerID) else {
                return .init(isConfigured: false, providerLabel: "AI 未连接", message: "会话服务不可用，请重新选择。")
            }
            var settings = self.aiProviderProfile(for: provider)
            settings.model = selection.model; settings.thinking = selection.thinking; settings.isEnabled = true
            do {
                _ = try settings.agentConfiguration()
                return .init(isConfigured: true, providerLabel: provider.title, message: nil)
            } catch { return .init(isConfigured: false, providerLabel: provider.title, message: error.localizedDescription) }
        }
        let baseModel = dependencies.modelSnapshot
        let environment = ProcessInfo.processInfo.environment
        let testing = environment["TOUGH_TRIAL_UI_TESTING"] == "1" || environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1"
        dependencies.modelSnapshot = { [weak self] in
            guard let self else { throw V2AssistantTurnError.scheduleUnavailable }
            var model = try baseModel()
            if testing {
                let respond = model.respond
                model.respond = { request in
                    if environment["TOUGH_TRIAL_UI_TEST_TASK_CARDS"] == "1" {
                        if !request.observations.isEmpty {
                            return .init(action: .answer(text: "修改已保存。"), providerLabel: "UI 测试 Agent", model: "deterministic-ui-test")
                        }
                        return .init(action: .toolCall(.init(toolID: "core.tasks.schedule", argumentsJSON: Data(#"{"request":"整理今日待办"}"#.utf8), modelCallID: "ui-schedule")), providerLabel: "UI 测试 Agent", model: "deterministic-ui-test")
                    }
                    if environment["TOUGH_TRIAL_UI_TEST_DYNAMIC_TOOLS"] == "1" {
                        if let observation = request.observations.last {
                            return .init(action: .answer(text: observation.summary), providerLabel: "UI 测试 Agent", model: "deterministic-ui-test")
                        }
                        let call: V2AgentToolCall
                        if request.userText.contains("已付款") {
                            call = .init(toolID: "core.finance.markPaid", argumentsJSON: Data(#"{"planReference":"Test Subscription","dueDate":"2026-10-10"}"#.utf8))
                        } else if request.userText.contains("订阅") {
                            call = .init(toolID: "core.finance.createPlan", argumentsJSON: Data(#"{"title":"Test Subscription","amount":"20","currency":"USD","dueDate":"2026-10-10","kind":"subscription","recurrence":"monthly"}"#.utf8))
                        } else {
                            call = .init(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"Tool Test Task","note":"回家路上"}"#.utf8))
                        }
                        return .init(action: .toolCall(call), providerLabel: "UI 测试 Agent", model: "deterministic-ui-test")
                    }
                    if environment["TOUGH_TRIAL_UI_TEST_SLOW_SCHEDULE"] == "1" {
                        try await Task.sleep(for: .seconds(4))
                    }
                    if request.userText.contains("新增") || request.userText.contains("延期") || request.userText.contains("完成任务") {
                        return .init(action: .schedule(query: request.userText), providerLabel: "UI 测试 Agent", model: "deterministic-ui-test")
                    }
                    return try await respond(request)
                }
                model.generateSchedule = { request in
                    if environment["TOUGH_TRIAL_UI_TEST_TASK_CARDS"] == "1" {
                        if request.userText.contains("请调整任务"), let task = request.snapshot.tasks.first(where: { task in
                            (request.context.quotedMessages ?? []).contains { $0.excerpt.contains("任务 ID：" + task.id + "\n") }
                        }) {
                            return .proposal(.init(summary: "修改任务备注", operations: [.init(kind: .updateTask, targetID: task.id, note: "修改后备注")]))
                        }
                        return .proposal(.init(summary: "三件待办", operations: ["整理电脑文件", "学习部署流程", "准备演示文稿"].enumerated().map {
                            .init(kind: .createTask, localID: "ui-task-\($0.offset)", title: $0.element, note: "保留源文件和输入细节")
                        }))
                    }
                    if environment["TOUGH_TRIAL_UI_TEST_SLOW_SCHEDULE"] == "1" {
                        try await Task.sleep(for: .seconds(10))
                    }
                    return .proposal(.init(summary: "新增测试任务", operations: [.init(kind: .createTask, localID: "new-task", title: "日程执行测试", note: "保留输入中的要求")]))
                }
            } else {
                model.thinking = self.aiProviderSettings.thinking
                let client = V2OpenAICompatibleScheduleClient(configuration: try self.aiProviderSettings.agentConfiguration())
                model.generateSchedule = { request in try await client.generate(request) }
            }
            return model
        }
        if testing {
            let fixtureSnapshot = dependencies.modelSnapshot
            let fixtureStatus = dependencies.providerStatus
            dependencies.selectedModelSnapshot = { _ in try fixtureSnapshot() }
            dependencies.selectedProviderStatus = { _ in fixtureStatus() }
        }
        dependencies.toggleTaskCompletion = { [weak self] taskID, planItemID, date in
            guard let self, self.canWrite else { throw V2AssistantTurnError.scheduleUnavailable }
            try self.engine.toggleAssistantTaskCompletion(taskID: taskID, planItemID: planItemID, at: date)
            self.refreshProjection(at: date)
        }
        dependencies.scheduleSnapshot = { [weak self] in
            guard let snapshot = self?.engine.snapshot else { return .empty }
            return .init(taskContexts: snapshot.taskContexts, tasks: snapshot.tasks,
                         planItems: snapshot.planItems, executionSegments: snapshot.executionSegments)
        }
        dependencies.applySchedule = { [weak self] proposal, baseline, requestID, date in
            guard let self, self.canWrite else { throw V2AssistantTurnError.scheduleUnavailable }
            let receipt: V2ScheduleReceipt
            do {
                receipt = try self.engine.applyScheduleProposal(proposal, requestID: requestID,
                    at: date, calendar: self.calendar, expectedSnapshot: baseline)
            } catch { throw V2ScheduleUIError(underlying: error) }
            self.highlightedScheduleIDs = Set(receipt.changes.map(\.entityID))
            self.refreshProjection(at: date)
            self.refreshScheduleReminders(receipt, at: date)
            return receipt
        }
        dependencies.scheduleReceipt = { [weak self] requestID in
            self?.engine.snapshot.scheduleReceipts.first { $0.requestID == requestID }
        }
        dependencies.undoSchedule = { [weak self] id, date in
            guard let self, self.canWrite else { throw V2AssistantTurnError.scheduleUnavailable }
            let receipt: V2ScheduleReceipt
            do { receipt = try self.engine.undoScheduleReceipt(id: id, at: date) }
            catch { throw V2ScheduleUIError(underlying: error) }
            self.highlightedScheduleIDs = []
            self.refreshProjection(at: date)
            self.refreshScheduleReminders(receipt, at: date)
            return receipt
        }
        dependencies.confirmsSchedule = { V2ScheduleSettings.requiresConfirmation }
        dependencies.timeZoneIdentifier = { [weak self] in self?.calendar.timeZone.identifier ?? TimeZone.current.identifier }
        bindDynamicTools(to: &dependencies)
        return dependencies
    }

    func refreshScheduleReminders(_ receipt: V2ScheduleReceipt, at date: Date) {
        let taskIDs = Set(receipt.changes.filter { $0.entityKind == .task }.map(\.entityID))
        let planIDs = Set(receipt.changes.filter { $0.entityKind == .planItem }.map(\.entityID))
        let previous = scheduleReminderTask
        scheduleReminderTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let snapshot = self.engine.snapshot
            let affected = planIDs.union(snapshot.planItems.filter { $0.taskID.map(taskIDs.contains) == true }.map(\.id))
            let eligible = snapshot.planItems.filter { item in
                guard affected.contains(item.id) else { return false }
                let task = snapshot.tasks.first { $0.id == item.taskID }
                return task?.status != .done && task?.status != .archived
            }
            do {
                try await self.notificationService.replaceIfAuthorized(planItems: eligible,
                    affectedIDs: affected, now: Date(), calendar: self.calendar)
            } catch { self.errorMessage = "日程已保存，提醒暂时未能更新。" }
        }
    }

}

enum V2ScheduleSettings {
    static var requiresConfirmation: Bool {
        ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_STRICT_SCHEDULE"] == "1"
            || defaults.bool(forKey: "schedule.requiresConfirmation")
    }
    static var defaults: UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        if environment["TOUGH_TRIAL_UI_TESTING"] == "1" || environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1" {
            return UserDefaults(suiteName: "schedule-tests-\(ProcessInfo.processInfo.processIdentifier)")!
        }
        return .standard
    }
}

struct V2ScheduleSettingsView: View {
    @AppStorage("schedule.requiresConfirmation", store: V2ScheduleSettings.defaults) private var requiresConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Toggle("修改前确认", isOn: $requiresConfirmation)
                    .accessibilityIdentifier("schedule.requiresConfirmation")
            } footer: {
                Text("默认直接执行你要求的日程修改，展示实际变化并提供撤销。开启后，每次会先展示修改内容，点确认才执行。")
            }
        }
        .navigationTitle("日程修改")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
}

struct V2ScheduleUIError: LocalizedError {
    let underlying: Error
    var errorDescription: String? {
        switch underlying {
        case V2EngineError.staleScheduleProposal:
            "相关日程在整理期间已更改。请重新提交这次要求，以最新日程为准。"
        case V2EngineError.scheduleReceiptConflict, V2EngineError.scheduleReceiptDanglingReference:
            "相关任务后来有了修改或新记录，暂时无法整次撤销，以免覆盖后来的内容。"
        case V2EngineError.taskNotFound, V2EngineError.planItemNotFound:
            "这次修改引用的任务或安排已不存在，请重新指定。"
        case V2EngineError.taskArchived:
            "相关任务已经归档，无法直接修改。"
        case V2EngineError.invalidScheduleOperation, V2EngineError.invalidPlanTimeRange,
             V2EngineError.taskHierarchyCycle, V2EngineError.blankTitle:
            "这次修改的任务关系或时间不完整，尚未执行。请补充具体要求。"
        default:
            "这次日程操作未保存，请稍后重试。"
        }
    }
}
