import Foundation
import SwiftUI
import ToughTrialV2Core

@MainActor
final class V2AppStore: ObservableObject {
    @Published var state: V2PrototypeState
    @Published var isPlanPresented = false
    @Published var zenSession: V2ActiveSession?
    @Published var errorMessage: String?
    @Published private(set) var pendingPlanDrafts: [V2PlanDraftRecord] = []
    @Published private(set) var recallDate = Date()
    @Published var recallText = ""
    @Published private(set) var recallCandidates: [V2RecallReferenceCandidate] = []
    @Published private(set) var selectedRecallCandidateIDs = Set<String>()
    @Published private(set) var savedRecallEntry: V2RecallEntry?

    private let engine: V2Engine
    private let calendar: Calendar
    private let canWrite: Bool
    private let startupErrorMessage: String?
    private var focusedSessionID: String?
    private var zenSessionID: String?

    init(
        engine injectedEngine: V2Engine? = nil,
        initialState: V2PrototypeState = .empty(),
        calendar: Calendar = .current
    ) {
        self.state = initialState
        self.calendar = calendar

        if let injectedEngine {
            self.engine = injectedEngine
            self.canWrite = true
            self.startupErrorMessage = nil
            self.errorMessage = nil
        } else {
            do {
                let url = try V2JSONSnapshotStore.defaultFileURL()
                self.engine = try V2Engine.load(from: V2JSONSnapshotStore(fileURL: url))
                self.canWrite = true
                self.startupErrorMessage = nil
                self.errorMessage = nil
            } catch {
                let message = "本地数据无法读取，原文件已保留。修复前不会写入新数据。"
                self.engine = V2Engine()
                self.canWrite = false
                self.startupErrorMessage = message
                self.errorMessage = message
            }
        }

        refreshProjection(at: Date())
        loadRecallDay(Date(), now: Date())
    }

    func openPlanAgent() { isPlanPresented = true }
    func closePlanAgent() { isPlanPresented = false }

    var planDraftCount: Int {
        let durableIDs = Set(pendingPlanDrafts.map(\.id))
        guard let currentID = state.currentPlanDraft?.id else { return durableIDs.count }
        return durableIDs.contains(currentID) ? durableIDs.count : durableIDs.count + 1
    }

    func setPlanScope(_ scope: String?) {
        state.setPlanScope(scope)
    }

    func beginPlanPrompt(_ prompt: String, at date: Date = Date()) {
        state.beginPlanPrompt(prompt, scope: state.planScope, at: date, calendar: calendar)
    }

    func confirmPlanClarification(_ response: String, at date: Date = Date()) {
        state.confirmPlanClarification(response, at: date, calendar: calendar)
    }

    func saveCurrentPlanDraft(at date: Date = Date()) {
        guard let draft = state.currentPlanDraft else { return }
        let record = planDraftRecord(from: draft, at: date)
        guard mutate(at: date, {
            try engine.savePlanDraft(record, at: date, calendar: calendar)
        }) != nil else {
            return
        }
        state.saveCurrentPlanDraft()
    }

    func acceptCurrentPlanDraft(at date: Date = Date()) {
        guard let draft = state.currentPlanDraft else { return }
        let record = planDraftRecord(from: draft, at: date)
        guard mutate(at: date, {
            _ = try engine.savePlanDraft(record, at: date, calendar: calendar)
            return try engine.acceptPlanDraft(id: record.id, at: date, calendar: calendar)
        }) != nil else {
            return
        }
        state.completeCurrentPlanDraftAcceptance()
    }

    func selectRecallDate(_ date: Date, now: Date = Date()) {
        loadRecallDay(date, now: now)
    }

    func toggleRecallReference(_ candidate: V2RecallReferenceCandidate) {
        if selectedRecallCandidateIDs.contains(candidate.id) {
            selectedRecallCandidateIDs.remove(candidate.id)
        } else {
            selectedRecallCandidateIDs.insert(candidate.id)
        }
    }

    func isRecallReferenceSelected(_ candidate: V2RecallReferenceCandidate) -> Bool {
        selectedRecallCandidateIDs.contains(candidate.id)
    }

    @discardableResult
    func saveRecall(at date: Date = Date()) -> Bool {
        let references = selectedRecallReferences()
        guard let entry = mutate(at: date, {
            try engine.saveRecallEntry(
                date: recallDate,
                text: recallText,
                references: references,
                at: date,
                calendar: calendar
            )
        }) else {
            return false
        }
        savedRecallEntry = entry
        return true
    }

    func runClock() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            refreshProjection(at: Date())
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func selectTodayItem(_ item: V2TimelineItem) {
        state.selectedTaskID = item.kind == .task ? item.taskID : nil
    }

    func clearTodaySelection() {
        state.selectedTaskID = nil
    }

    func focusSession(_ id: String) {
        focusedSessionID = id
        if let session = state.activeSessions.first(where: { $0.id == id }) {
            state.selectedTaskID = session.taskID
        }
        refreshProjection(at: Date())
    }

    @discardableResult
    func quickAddTodayTask(title: String, at date: Date = Date()) -> Bool {
        guard let created = mutate(at: date, {
            try engine.quickInsertTodayTask(title: title, at: date, calendar: calendar)
        }) else {
            return false
        }
        state.selectedTaskID = created.task.id
        return true
    }

    @discardableResult
    func quickAddScheduledTask(title: String, on date: Date) -> Bool {
        guard let created = mutate(at: Date(), {
            try engine.quickInsertScheduledTask(title: title, on: date, calendar: calendar)
        }) else {
            return false
        }
        state.selectedTaskID = created.task.id
        return true
    }

    func startTodayItem(
        _ item: V2TimelineItem,
        source: V2ExecutionSegment.Source = .normal,
        at date: Date = Date()
    ) {
        guard item.kind == .task else { return }
        guard let segment = mutate(at: date, {
            try engine.startExecution(
                taskID: item.taskID,
                title: item.title,
                source: source,
                at: date
            )
        }) else {
            return
        }
        focusedSessionID = segment.logicalSessionID
        state.selectedTaskID = item.taskID
        refreshProjection(at: date)
    }

    func toggleSession(_ id: String, at date: Date = Date()) {
        guard let session = state.activeSessions.first(where: { $0.id == id }) else { return }
        switch session.status {
        case .running:
            _ = mutate(at: date) {
                try engine.pauseExecutionSession(sessionID: id, at: date)
            }
        case .paused:
            _ = mutate(at: date) {
                try engine.resumeExecutionSession(sessionID: id, at: date)
            }
        }
    }

    @discardableResult
    func endSession(_ id: String, at date: Date = Date()) -> Bool {
        let result: Void? = mutate(at: date) {
            try engine.stopExecutionSession(sessionID: id, at: date)
        }
        return result != nil
    }

    func completeTodayItem(_ item: V2TimelineItem, at date: Date = Date()) {
        guard item.kind == .task, let taskID = item.taskID else { return }
        _ = mutate(at: date) {
            try engine.completeTask(id: taskID, at: date)
        }
    }

    func restoreTodayItem(_ item: V2TimelineItem, at date: Date = Date()) {
        guard item.kind == .task, let taskID = item.taskID else { return }
        _ = mutate(at: date) {
            try engine.restoreTask(id: taskID, at: date)
        }
        state.selectedTaskID = taskID
    }

    func startZen(taskID: String?, title: String, at date: Date = Date()) {
        if let taskID,
           let existing = state.activeSessions.first(where: { $0.taskID == taskID }) {
            focusedSessionID = existing.id
            zenSessionID = existing.id
            zenSession = existing
            return
        }

        guard let segment = mutate(at: date, {
            try engine.startExecution(
                taskID: taskID,
                title: title,
                source: .zen,
                at: date
            )
        }) else {
            return
        }
        focusedSessionID = segment.logicalSessionID
        zenSessionID = segment.logicalSessionID
        refreshProjection(at: date)
    }

    func finishZen(at date: Date = Date()) {
        guard let zenSessionID else { return }
        guard endSession(zenSessionID, at: date) else { return }
        self.zenSessionID = nil
        zenSession = nil
    }

    func toggleZenSession(at date: Date = Date()) {
        guard let zenSessionID else { return }
        toggleSession(zenSessionID, at: date)
    }

    func closeZen() {
        zenSessionID = nil
        zenSession = nil
    }

    private func refreshProjection(at now: Date) {
        let today = engine.todaySnapshot(date: now, now: now, calendar: calendar)
        pendingPlanDrafts = engine.snapshot.planDrafts
            .filter { $0.status == .draft }
            .sorted { $0.updatedAt > $1.updatedAt }
        var next = state
        next.tasks = projectedTasks(through: now)
        next.timelineItems = today.items.map { item in
            V2TimelineItem(
                id: item.id,
                kind: item.kind == .task ? .task : .executionRecord,
                timeLabel: item.plannedAt.map(Self.shortTime) ?? "今天",
                title: item.title,
                detail: Self.todayDetail(for: item),
                taskID: item.taskID,
                isDone: item.isDone
            )
        }
        next.scheduledTasks = projectedSchedule()

        var sessions = today.sessions.map { session in
            let currentSeconds = max(0, Int(session.currentDuration.rounded(.down)))
            let totalSeconds = max(0, Int(session.totalDuration.rounded(.down)))
            return V2ActiveSession(
                id: session.id,
                taskID: session.taskID,
                title: session.title,
                startedAtLabel: Self.shortTime(session.startedAt),
                currentElapsed: currentSeconds / 60,
                totalElapsed: totalSeconds / 60,
                currentElapsedSeconds: currentSeconds,
                totalElapsedSeconds: totalSeconds,
                status: session.status == .running ? .running : .paused
            )
        }
        if let focusedSessionID,
           let focusedIndex = sessions.firstIndex(where: { $0.id == focusedSessionID }) {
            let focused = sessions.remove(at: focusedIndex)
            sessions.insert(focused, at: 0)
        } else {
            focusedSessionID = sessions.first?.id
        }
        next.activeSessions = sessions

        if let selectedTaskID = next.selectedTaskID,
           !next.flattenTasks().contains(where: { $0.id == selectedTaskID }) {
            next.selectedTaskID = nil
        }
        state = next

        if let zenSessionID {
            zenSession = sessions.first(where: { $0.id == zenSessionID })
            if zenSession == nil {
                self.zenSessionID = nil
            }
        }
    }

    private func loadRecallDay(_ date: Date, now: Date) {
        recallDate = calendar.startOfDay(for: date)
        let evidence = engine.recallEvidence(date: recallDate, now: now, calendar: calendar)
        recallCandidates = engine.recallReferenceCandidates(
            date: recallDate,
            now: now,
            calendar: calendar
        )
        savedRecallEntry = evidence.savedEntry
        recallText = evidence.savedEntry?.text ?? ""
        selectedRecallCandidateIDs = Set(
            recallCandidates
                .filter { candidate in
                    guard let entry = evidence.savedEntry else { return false }
                    return Self.references(candidate.references, areIncludedIn: entry)
                }
                .map(\.id)
        )
    }

    private func selectedRecallReferences() -> V2RecallReferences {
        let selected = recallCandidates.filter { selectedRecallCandidateIDs.contains($0.id) }
        return V2RecallReferences(
            taskIDs: Self.unique(selected.flatMap(\.references.taskIDs)),
            segmentIDs: Self.unique(selected.flatMap(\.references.segmentIDs)),
            planItemIDs: Self.unique(selected.flatMap(\.references.planItemIDs))
        )
    }

    private func planDraftRecord(from draft: V2PlanDraft, at date: Date) -> V2PlanDraftRecord {
        V2PlanDraftRecord(
            id: draft.id,
            mode: .scheduleOnly,
            userPrompt: draft.userPrompt,
            summary: "\(draft.title)：\(draft.summary)",
            proposedPlanItems: draft.scheduleItems.map { item in
                V2ProposedPlanItem(
                    id: item.id,
                    date: item.date,
                    startAt: item.startAt,
                    endAt: item.endAt,
                    title: item.title
                )
            },
            createdAt: date,
            updatedAt: date
        )
    }

    private func projectedTasks(through now: Date) -> [V2TaskNode] {
        let tasks = engine.snapshot.tasks.filter { $0.status != .archived }
        let contextByID = Dictionary(uniqueKeysWithValues: engine.snapshot.taskContexts.map { ($0.id, $0) })
        let roots = tasks.filter { task in
            guard let parentID = task.parentID else { return true }
            return !tasks.contains(where: { $0.id == parentID })
        }

        func node(_ task: V2Task, visited: Set<String>) -> V2TaskNode {
            let context = task.contextID.flatMap { contextByID[$0] }
            let children: [V2TaskNode]
            if visited.contains(task.id) {
                children = []
            } else {
                let nextVisited = visited.union([task.id])
                children = tasks
                    .filter { $0.parentID == task.id }
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { node($0, visited: nextVisited) }
            }
            return V2TaskNode(
                id: task.id,
                title: task.title,
                subtitle: task.note,
                goal: context?.title ?? "未归类",
                colorName: context?.colorName ?? "teal",
                status: Self.prototypeStatus(task.status),
                spentMinutes: Int(engine.spentDuration(taskID: task.id, through: now) / 60),
                children: children
            )
        }

        return roots
            .sorted { $0.createdAt < $1.createdAt }
            .map { node($0, visited: []) }
    }

    private func projectedSchedule() -> [V2ScheduledTask] {
        let taskByID = Dictionary(uniqueKeysWithValues: engine.snapshot.tasks.map { ($0.id, $0) })
        return engine.snapshot.planItems.compactMap { item in
            guard item.status != .canceled else { return nil }
            let task = item.taskID.flatMap { taskByID[$0] }
            let placement: V2SchedulePlacement
            if let startAt = item.startAt {
                let components = calendar.dateComponents([.hour, .minute], from: startAt)
                let startMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                let duration = item.endAt.map {
                    max(15, Int($0.timeIntervalSince(startAt) / 60))
                } ?? 30
                placement = .timed(startMinute: startMinute, durationMinutes: duration)
            } else {
                placement = .allDay
            }
            return V2ScheduledTask(
                id: item.id,
                title: task?.title ?? item.title,
                detail: item.startAt == nil ? "仅确定日期，时间可以之后再安排。" : "已放在时间轴。",
                taskID: item.taskID,
                date: item.date,
                placement: placement,
                isDone: task?.status == .done
            )
        }
    }

    private func mutate<Result>(at date: Date, _ operation: () throws -> Result) -> Result? {
        guard canWrite else {
            errorMessage = startupErrorMessage
            return nil
        }
        do {
            let result = try operation()
            errorMessage = nil
            refreshProjection(at: date)
            return result
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private static func prototypeStatus(_ status: V2Task.Status) -> V2TaskNode.Status {
        switch status {
        case .notStarted, .archived:
            .planned
        case .active:
            .active
        case .paused:
            .paused
        case .done:
            .done
        }
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        if seconds >= 3_600 {
            return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分钟"
        }
        if seconds >= 60 {
            return "\(seconds / 60)分钟"
        }
        return "\(seconds)秒"
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func references(
        _ references: V2RecallReferences,
        areIncludedIn entry: V2RecallEntry
    ) -> Bool {
        let hasReference = !references.taskIDs.isEmpty ||
            !references.segmentIDs.isEmpty ||
            !references.planItemIDs.isEmpty
        guard hasReference else { return false }
        return Set(references.taskIDs).isSubset(of: Set(entry.referencedTaskIDs)) &&
            Set(references.segmentIDs).isSubset(of: Set(entry.referencedSegmentIDs)) &&
            Set(references.planItemIDs).isSubset(of: Set(entry.referencedPlanItemIDs))
    }

    private static func todayDetail(for item: V2TodayItemSnapshot) -> String {
        switch item.kind {
        case .task where item.spentDuration > 0:
            return "今天已记录 \(durationText(item.spentDuration))。"
        case .task:
            return "今天要处理的任务。"
        case .executionRecord:
            return "记录了 \(durationText(item.spentDuration)) 的执行时间。"
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case V2EngineError.taskCompleted(_):
            return "这个任务已经完成，恢复后才能再次开始。"
        case V2EngineError.taskAlreadyRunning(_):
            return "这个任务已经在计时。"
        case V2EngineError.blankTitle:
            return "任务名称不能为空。"
        case V2EngineError.blankRecallText:
            return "写下一点内容后再保存。"
        default:
            return "操作没有保存，请稍后再试。"
        }
    }
}
