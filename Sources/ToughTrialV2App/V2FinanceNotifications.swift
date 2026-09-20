import Foundation
import UserNotifications
import ToughTrialV2Core

@MainActor
final class V2FinanceNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = V2FinanceNotifications()
    @Published var selectedPlanID: String?
    @Published private(set) var status = "提醒尚未启用"
    private var isRefreshing = false
    private var queued: (plans: [V2FinancePlan], permission: Bool, now: Date)?
    override private init() { super.init(); UNUserNotificationCenter.current().delegate = self }

    @discardableResult
    func refresh(_ plans: [V2FinancePlan], requestPermission: Bool = false, now: Date = Date()) async -> Bool {
        if isRefreshing {
            queued = (plans, requestPermission || queued?.permission == true, now)
            return false
        }
        isRefreshing = true
        defer { isRefreshing = false }
        var result = await schedule(plans, requestPermission: requestPermission, now: now)
        while let next = queued {
            queued = nil
            result = await schedule(next.plans, requestPermission: next.permission, now: next.now)
        }
        return result
    }
    private func schedule(_ plans: [V2FinancePlan], requestPermission: Bool, now: Date) async -> Bool {
        let ticket = try? V2PluginStore.shared.ticket(["finance"])
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("v2-finance-") }.map(\.identifier))
        guard let ticket, (try? V2PluginStore.shared.validate(ticket)) != nil else { status = "功能已停用，付款提醒已暂停"; return false }
        let requests = Self.reminders(for: plans, now: now)
        if requests.isEmpty && !requestPermission { status = "当前没有待安排的未来提醒"; return true }
        let settings = await center.notificationSettings()
        guard (try? V2PluginStore.shared.validate(ticket)) != nil else { status = "提醒已暂停"; return false }
        if settings.authorizationStatus == .notDetermined && requestPermission {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { status = "通知权限请求未完成，计划仍已保存"; return false }
        }
        let granted = await center.notificationSettings().authorizationStatus
        guard (try? V2PluginStore.shared.validate(ticket)) != nil else { status = "提醒已暂停"; return false }
        guard granted == .authorized || granted == .provisional else { status = "通知未授权；计划已保存，可在系统设置中开启"; return false }
        let otherCount = pending.filter { !$0.identifier.hasPrefix("v2-finance-") }.count
        let selected = requests.sorted { $0.1 < $1.1 }.prefix(min(28, max(0, 60 - otherCount)))
        var count = 0
        do {
            for (phase, date, plan) in selected {
                try V2PluginStore.shared.validate(ticket)
                let content = UNMutableNotificationContent()
                content.title = "\(plan.title) · \(phase == "due" ? "今天到期" : "即将到期")"
                content.body = "\(plan.currency) \(plan.amount) · \(plan.dueDate)\n" + (plan.prompt.isEmpty ? "核对账单后，在对应应用处理。完成后再标记已支付。" : plan.prompt)
                content.sound = .default; content.userInfo = ["financePlanID": plan.id]
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                components.timeZone = calendar.timeZone
                try await center.add(.init(identifier: "v2-finance-\(plan.id)-\(phase)", content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                guard (try? V2PluginStore.shared.validate(ticket)) != nil else {
                    let current = await center.pendingNotificationRequests()
                    center.removePendingNotificationRequests(withIdentifiers: current.filter { $0.identifier.hasPrefix("v2-finance-") }.map(\.identifier))
                    status = "提醒已暂停"; return false
                }
                count += 1
            }
            status = "已安排 \(count) 条本地提醒" + (requests.count > count ? "，较远提醒会在下次打开时补排" : "；打开应用时更新")
            return true
        } catch { status = "部分提醒未能安排；计划已保存，下次打开会重试"; return false }
    }
    static func reminders(for plans: [V2FinancePlan], now: Date) -> [(String, Date, V2FinancePlan)] {
        var requests: [(String, Date, V2FinancePlan)] = []
        for plan in plans where plan.isActive && plan.reminderEnabled {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
            guard let day = V2CaptureContract.date(plan.dueDate, timeZone: calendar.timeZone),
                  let due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            if due > now { requests.append(("due", due, plan)) }
            if plan.reminderDays > 0, let early = calendar.date(byAdding: .day, value: -plan.reminderDays, to: due), early > now {
                requests.append(("early", early, plan))
            }
        }
        return requests
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["financePlanID"] as? String
        if let id { await MainActor.run { self.selectedPlanID = id } }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
