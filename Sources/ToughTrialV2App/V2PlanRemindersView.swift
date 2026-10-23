import SwiftUI
import UserNotifications
import ToughTrialV2Core
#if os(iOS)
import UIKit
#endif

struct V2PlanRemindersView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var authorization = UNAuthorizationStatus.notDetermined
    @State private var editingItem: V2PlanItem?
    @State private var receiptID: String?
    @State private var feedback: String?
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(permissionTitle, systemImage: authorization == .denied ? "bell.slash" : "bell")
                            .font(.headline)
                            .accessibilityIdentifier("today.reminders.permission")
                        Text("在计划时间提醒。没有具体时间的任务，可以在下方直接设置。")
                            .font(.subheadline).foregroundStyle(V2Theme.secondary)
                        if authorization == .denied {
                            Button("打开系统通知设置") { openNotificationSettings() }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("today.reminders.settings")
                        } else if authorization == .notDetermined {
                            Button("开启通知") { Task { await enableNotifications() } }
                                .frame(minHeight: 44).disabled(isUpdating)
                                .accessibilityIdentifier("today.reminders.enable")
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))

                    Text("今日及未来规划").font(V2Theme.TypeRole.titleLarge)
                    if store.planReminderItems().isEmpty {
                        Text("还没有待规划的任务。先从今天右下角 ＋ 添加任务，再来设置提醒时间。")
                            .foregroundStyle(V2Theme.secondary)
                            .accessibilityIdentifier("today.reminders.empty")
                    }
                    ForEach(store.planReminderItems()) { item in
                        Button { editingItem = item } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title).font(.headline).foregroundStyle(V2Theme.ink)
                                    Text(timeLabel(item))
                                        .font(.subheadline).foregroundStyle(V2Theme.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: item.startAt == nil ? "bell.badge" : "chevron.right")
                            }
                            .padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.reminders.plan.\(item.title)")
                    }
                    if let feedback {
                        HStack(alignment: .top) {
                            Text(feedback).font(.subheadline).foregroundStyle(V2Theme.secondary)
                                .accessibilityIdentifier("today.reminders.feedback")
                            Spacer()
                            if let receiptID {
                                Button("撤销") {
                                    if store.undoTaskChange(receiptID: receiptID) {
                                        self.receiptID = nil; self.feedback = "已撤销时间修改。"
                                    } else { self.feedback = store.errorMessage }
                                }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("today.reminders.undo")
                            }
                        }
                    }
                    if isUpdating { ProgressView("正在更新提醒…") }
                }
                .padding(22)
            }
            .background(V2Theme.page).foregroundStyle(V2Theme.ink).tint(V2Theme.blue)
            .navigationTitle("计划提醒")
            .v2InlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("today.reminders.close")
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { editingItem != nil }, set: { if !$0 { editingItem = nil } }
            )) {
                if let editingItem {
                    V2PlanReminderEditor(store: store, item: editingItem) { receipt, hasTime in
                        receiptID = receipt.id
                        feedback = hasTime ? "计划时间已保存。" : "已清除提醒时间，任务仍在规划中。"
                        self.editingItem = nil
                        if hasTime { Task { await enableNotifications() } }
                    }
                }
            }
            .task { await refreshAuthorization() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshAuthorization() } }
            }
        }
        .preferredColorScheme(.light)
    }

    private var permissionTitle: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: "通知已开启"
        case .denied: "通知未开启，计划时间仍会保留"
        default: "开启通知后即可收到提醒"
        }
    }

    private func timeLabel(_ item: V2PlanItem) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = store.calendar.timeZone
        formatter.dateFormat = item.startAt == nil ? "M月d日 · 未设提醒时间" : "M月d日 HH:mm"
        let label = formatter.string(from: item.startAt ?? item.date)
        return item.startAt.map { $0 <= Date() } == true ? label + " · 时间已过" : label
    }

    private func enableNotifications() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            let count = try await store.enablePlanReminders()
            feedback = count == 0 ? "通知已开启，选择任务设置提醒时间。" : "已为最近 \(count) 个计划设置提醒。"
        } catch {
            feedback = (error as? LocalizedError)?.errorDescription ?? "计划已保留，提醒暂时无法更新，请重试。"
        }
        authorization = await store.notificationService.authorizationStatus()
    }

    private func refreshAuthorization() async {
        authorization = await store.notificationService.authorizationStatus()
        guard authorization == .authorized || authorization == .provisional, !isUpdating else { return }
        do {
            try await store.notificationService.rebuildOwned(planItems: store.planReminderItems(),
                now: Date(), calendar: store.calendar)
        } catch { feedback = "计划已保留，提醒暂时未能更新。重新打开此页可重试。" }
    }

    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
        #endif
    }
}

private struct V2PlanReminderEditor: View {
    @ObservedObject var store: V2AppStore
    let item: V2PlanItem
    let onSaved: (V2ScheduleReceipt, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startAt: Date
    @State private var issue: String?

    init(store: V2AppStore, item: V2PlanItem, onSaved: @escaping (V2ScheduleReceipt, Bool) -> Void) {
        self.store = store; self.item = item; self.onSaved = onSaved
        let candidate = item.startAt ?? store.calendar.date(bySettingHour: store.calendar.component(.hour, from: Date()),
            minute: store.calendar.component(.minute, from: Date()), second: 0, of: item.date) ?? item.date
        _startAt = State(initialValue: candidate > Date() ? candidate : Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(item.title).font(V2Theme.TypeRole.titleLarge)
            Text("在这个时间提醒你开始。保存会同时更新任务的计划时间。")
                .font(.subheadline).foregroundStyle(V2Theme.secondary)
            DatePicker("提醒时间", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                .frame(maxWidth: .infinity)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.timeZone, store.calendar.timeZone)
                .accessibilityLabel("提醒时间")
                .accessibilityIdentifier("today.reminders.time")
            if startAt <= Date() {
                Text("请选择稍后的时间。")
                    .font(.subheadline).foregroundStyle(V2Theme.ColorRole.destructive)
            }
            if let issue {
                Text(issue).font(.subheadline).foregroundStyle(V2Theme.ColorRole.destructive)
                    .accessibilityIdentifier("today.reminders.error")
            }
            Button("保存提醒时间") { save(startAt) }
                .font(.headline).foregroundStyle(V2Theme.ColorRole.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(V2Theme.blue, in: RoundedRectangle(cornerRadius: 16))
                .disabled(startAt <= Date())
                .opacity(startAt <= Date() ? 0.45 : 1)
                .accessibilityIdentifier("today.reminders.save")
            if item.startAt != nil {
                Button("清除提醒时间") { save(nil) }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("today.reminders.clear")
            }
            Spacer(minLength: 0)
        }
        .padding(22).background(V2Theme.page).foregroundStyle(V2Theme.ink).tint(V2Theme.blue)
        .navigationTitle("设置计划提醒").v2InlineNavigationTitle()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityIdentifier("today.reminders.cancel")
            }
        }
    }

    private func save(_ date: Date?) {
        if let receipt = store.setPlanReminder(item, startAt: date) { onSaved(receipt, date != nil) }
        else { issue = store.errorMessage; store.dismissError() }
    }
}
