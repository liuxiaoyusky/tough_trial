import SwiftUI
import ToughTrialV2Core

struct V2AssistantScheduleCardView: View {
    let card: V2AgentScheduleCard
    @ObservedObject var store: V2AssistantStore

    let onEditTask: (V2AssistantTaskPreview) -> Void
    private var receipt: V2ScheduleReceipt? { store.receipt(for: card) }
    private var tasks: [V2AssistantTaskPreview] { card.taskPreviews(receipt: receipt) }
    private var stateLabel: String {
        receipt?.undoneAt != nil ? "已撤销" : receipt != nil ? "已保存" : card.status == .cancelled ? "已取消" : "待确认 · 尚未保存"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(tasks.isEmpty ? "日程修改" : "\(tasks.count) 件待办", systemImage: "checklist")
                    .font(V2Theme.TypeRole.labelLarge)
                Spacer()
                Text(stateLabel).font(V2Theme.TypeRole.labelSmall).foregroundStyle(V2Theme.secondary)
            }
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        if receipt != nil, receipt?.undoneAt == nil, let current = store.currentTask(task), current.status != .archived {
                            Button { store.toggleTaskCompletion(task, card: card) } label: {
                                Image(systemName: current.status == .done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(V2Theme.blue)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("schedule.task.toggle.\(task.id)")
                            .accessibilityLabel(current.status == .done ? "恢复待办：\(current.title)" : "完成任务：\(current.title)")
                            .accessibilityValue(current.status == .done ? "已完成" : "待办")
                            .disabled(store.isRunningTurn)
                        } else {
                            Text("\((tasks.firstIndex { $0.id == task.id } ?? 0) + 1).")
                                .font(.headline).foregroundStyle(V2Theme.secondary).accessibilityHidden(true)
                        }
                        Text(store.currentTask(task)?.title ?? task.title).font(.headline)
                            .strikethrough(receipt?.undoneAt == nil && store.currentTask(task)?.status == .done)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if card.status != .cancelled && receipt?.undoneAt == nil {
                            Button(receipt == nil ? "编辑" : "调整") { onEditTask(task) }
                                .font(.subheadline).frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("schedule.task.edit.\(task.id)")
                                .disabled(store.isRunningTurn)
                        }
                    }
                    if !task.note.isEmpty { Text(task.note).font(.subheadline).foregroundStyle(V2Theme.secondary) }
                    Label(task.day ?? "未排期", systemImage: "calendar")
                        .font(.caption).foregroundStyle(V2Theme.secondary)
                    if let time = timeDescription(task) { Text(time).font(.caption).foregroundStyle(V2Theme.secondary) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V2Theme.blue.opacity(0.15)))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("schedule.task.\(task.id)")
            }
            if let receipt {
                ForEach(Array(receipt.changes.enumerated()), id: \.offset) { _, change in
                    if !isRepresented(change) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let before = beforeDescription(change), before != afterDescription(change) {
                                Text(before).strikethrough().foregroundStyle(.secondary)
                            }
                            Text(afterDescription(change)).foregroundStyle(V2Theme.ink)
                        }.font(.subheadline)
                    }
                }
                if receipt.undoneAt == nil {
                    Button("撤销这次修改") { store.undoSchedule(card) }
                        .accessibilityIdentifier("schedule.undo").disabled(store.isRunningTurn)
                }
            } else {
                if tasks.isEmpty { Text(card.proposal.summary).font(.subheadline) }
                ForEach(Array(card.proposal.operations.enumerated()), id: \.offset) { _, operation in
                    if operation.kind != .createTask && !(operation.kind == .scheduleTask && tasks.contains { $0.id == operation.targetID }) {
                        Text(operationDescription(operation)).font(.subheadline)
                    }
                }
                if card.status == .pending {
                    HStack {
                        Button(tasks.isEmpty ? "确认修改" : "确认保存") { store.confirmSchedule(card) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("schedule.confirm")
                        Button("取消") { store.cancelSchedule(card) }.accessibilityIdentifier("schedule.cancel")
                    }.disabled(store.isRunningTurn)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2Theme.blue.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
        .onAppear { store.objectWillChange.send() }

    }

    private func isRepresented(_ change: V2ScheduleChange) -> Bool {
        tasks.contains { $0.taskID == change.afterTask?.id || ($0.taskID != nil && $0.taskID == change.afterPlanItem?.taskID) }
    }

    private func timeDescription(_ task: V2AssistantTaskPreview) -> String? {
        if let receipt, let plan = receipt.changes.compactMap(\.afterPlanItem).first(where: { $0.taskID == task.taskID }), let start = plan.startAt {
            return start.formatted(date: .omitted, time: .shortened) + (plan.endAt.map { "–" + $0.formatted(date: .omitted, time: .shortened) } ?? "")
        }
        guard let op = card.proposal.operations.first(where: { $0.kind == .scheduleTask && $0.targetID == task.id }) else { return nil }
        var fields: [String] = []
        if let minute = op.startMinute { fields.append(String(format: "%02d:%02d", minute / 60, minute % 60)) }
        if let duration = op.durationMinutes { fields.append("\(duration) 分钟") }
        return fields.isEmpty ? nil : fields.joined(separator: " · ")
    }

    private func beforeDescription(_ change: V2ScheduleChange) -> String? {
        if let task = change.beforeTask { return taskDescription(task) }
        return change.beforePlanItem.map(planDescription)
    }

    private func afterDescription(_ change: V2ScheduleChange) -> String {
        if let task = change.afterTask { return taskDescription(task) }
        if let plan = change.afterPlanItem { return planDescription(plan) }
        return "已移除"
    }

    private func taskDescription(_ task: V2Task) -> String {
        let status: String
        switch task.status {
        case .done: status = "完成"
        case .archived: status = "归档"
        case .active: status = "进行中"
        case .paused: status = "暂停"
        case .notStarted: status = "待办"
        }
        return "\(status) · \(task.title)" + (task.note.isEmpty ? "" : "\n\(task.note)")
    }

    private func planDescription(_ plan: V2PlanItem) -> String {
        let time = plan.startAt.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        let end = plan.endAt.map { "–" + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        let status = plan.status == .canceled ? "（取消排期）" : plan.status == .completed ? "（完成）" : ""
        return "\(plan.title) · \(plan.date.formatted(date: .abbreviated, time: .omitted))\(time)\(end)\(status)"
    }

    private func operationDescription(_ op: V2ScheduleOperation) -> String {
        let targetID = op.targetID ?? op.localID
        let target = card.baseline.tasks.first { $0.id == targetID }?.title
            ?? card.baseline.planItems.first { $0.id == targetID }?.title
            ?? card.proposal.operations.first { $0.kind == .createTask && $0.localID == targetID && $0.localID != nil }?.title
            ?? op.title ?? "任务"
        let label: String
        switch op.kind {
        case .createTask: label = "新增"
        case .updateTask: label = "修改"
        case .scheduleTask: label = "排期"
        case .reschedulePlanItem: label = "调整时间"
        case .cancelPlanItem: label = "取消排期"
        case .completeTask: label = "完成"
        case .restoreTask: label = "恢复待办"
        case .archiveTask: label = "归档"
        }
        var fields = ["\(label) · \(target)"]
        if let title = op.title, title != target { fields.append("标题：\(title)") }
        if let note = op.note { fields.append(note.isEmpty ? "清空备注" : "备注：\(note)") }
        if let day = op.day { fields.append("日期：\(day)") }
        if let minute = op.startMinute { fields.append(String(format: "开始：%02d:%02d", minute / 60, minute % 60)) }
        if let duration = op.durationMinutes { fields.append("时长：\(duration) 分钟") }
        if op.clearTime { fields.append("取消具体时间") }
        if op.clearParent { fields.append("移出父任务") }
        if op.clearContext { fields.append("移出任务分组") }
        if let parent = op.parentID {
            let title = card.baseline.tasks.first { $0.id == parent }?.title
                ?? card.proposal.operations.first { $0.localID == parent }?.title ?? parent
            fields.append("属于：\(title)")
        }
        if let context = op.contextID { fields.append("分组：\(card.baseline.taskContexts.first { $0.id == context }?.title ?? context)") }
        return fields.joined(separator: "\n")
    }
}

struct V2AssistantTaskEditor: View {
    let task: V2AssistantTaskPreview
    let isSaved: Bool
    @ObservedObject var store: V2AssistantStore
    let save: (String, String, String?, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var scheduled: Bool
    @State private var day: Date
    @State private var instruction = ""
    private let initialDay: Date

    init(task: V2AssistantTaskPreview, isSaved: Bool, store: V2AssistantStore,
         save: @escaping (String, String, String?, String) -> Bool) {
        self.task = task; self.isSaved = isSaved; self.store = store; self.save = save
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let initial = task.day.flatMap { formatter.date(from: $0) } ?? Date()
        initialDay = initial
        _scheduled = State(initialValue: task.day != nil); _day = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            if isSaved {
                adjustment
            } else {
                V2TaskEditor(mode: .proposal, title: task.title, note: task.note,
                    additionalDirty: scheduled != (task.day != nil) || (scheduled && !Calendar.current.isDate(day, inSameDayAs: initialDay)),
                    onSave: { title, note in
                        if save(title, note, scheduled ? V2CaptureContract.localDate(day, timeZone: .current) : nil, "") {
                            dismiss(); return nil
                        }
                        return store.operationErrorMessage ?? "修改未保存，请重试。"
                    }, onCancel: { dismiss() }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("安排日期", isOn: $scheduled).accessibilityIdentifier("schedule.task.scheduled")
                            if scheduled {
                                DatePicker("日期", selection: $day, displayedComponents: .date)
                                    .accessibilityIdentifier("schedule.task.date")
                            }
                        }
                        Text("修改只更新这张待确认卡片，确认保存后才加入任务。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
            }
        }
        .presentationDetents([.large])
    }

    private var adjustment: some View {
        Form {
            Section(task.title) {
                TextField("例如：拆成几个步骤，或改到明天", text: $instruction, axis: .vertical)
                    .lineLimit(3...8).accessibilityIdentifier("schedule.task.adjustment")
            }
            if let error = store.operationErrorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("调整任务")
        .v2InlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityIdentifier("schedule.task.cancelEditing")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("发送") { if save(task.title, task.note, task.day, instruction) { dismiss() } }
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("schedule.task.save")
            }
        }
    }
}

struct V2AssistantTaskEditorContext: Identifiable {
    let card: V2AgentScheduleCard
    let task: V2AssistantTaskPreview
    var id: String { card.id + ":" + task.id }
}
