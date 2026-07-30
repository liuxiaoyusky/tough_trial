import Foundation

public struct DemoTask: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var progressLabel: String
    public var progressRatio: Double
    public var estimatedMinutes: Int?

    public init(
        id: UUID,
        title: String,
        detail: String,
        progressLabel: String,
        progressRatio: Double,
        estimatedMinutes: Int?
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.progressLabel = progressLabel
        self.progressRatio = progressRatio
        self.estimatedMinutes = estimatedMinutes
    }
}

public struct DemoTimelineEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var timeLabel: String
    public var title: String
    public var note: String
    public var linkedTaskID: UUID?
    public var isUncertain: Bool
    public var estimatedMinutes: Int?
    public var isParallel: Bool

    public init(
        id: UUID,
        timeLabel: String,
        title: String,
        note: String,
        linkedTaskID: UUID?,
        isUncertain: Bool = false,
        estimatedMinutes: Int?,
        isParallel: Bool = false
    ) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.note = note
        self.linkedTaskID = linkedTaskID
        self.isUncertain = isUncertain
        self.estimatedMinutes = estimatedMinutes
        self.isParallel = isParallel
    }
}

public struct FocusCandidate: Sendable, Equatable {
    public var title: String
    public var detail: String
}

public struct InteractiveDemoState: Sendable, Equatable {
    public enum SampleIDs {
        public static let commuteEvent = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        public static let writingEvent = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        public static let readingEvent = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        public static let recallEvent = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        public static let writingTask = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        public static let readingTask = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        public static let runningTask = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        public static let swiftUITask = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
        public static let photosTask = UUID(uuidString: "20000000-0000-0000-0000-000000000005")!
    }

    public var tasks: [DemoTask]
    public var todayEvents: [DemoTimelineEntry]
    public var planEvents: [DemoTimelineEntry]
    public var backlogTasks: [DemoTask]
    public var completedTodayTitles: [String]
    public var selectedTodayEventID: UUID?
    public var selectedFocusTaskID: UUID?
    public var manualFocusTitle: String?
    public var selectedDurationMinutes: Int

    public init(
        tasks: [DemoTask],
        todayEvents: [DemoTimelineEntry],
        planEvents: [DemoTimelineEntry],
        backlogTasks: [DemoTask],
        completedTodayTitles: [String] = [],
        selectedTodayEventID: UUID?,
        selectedFocusTaskID: UUID?,
        manualFocusTitle: String? = nil,
        selectedDurationMinutes: Int = 25
    ) {
        self.tasks = tasks
        self.todayEvents = todayEvents
        self.planEvents = planEvents
        self.backlogTasks = backlogTasks
        self.completedTodayTitles = completedTodayTitles
        self.selectedTodayEventID = selectedTodayEventID
        self.selectedFocusTaskID = selectedFocusTaskID
        self.manualFocusTitle = manualFocusTitle
        self.selectedDurationMinutes = selectedDurationMinutes
    }

    public var focusCandidate: FocusCandidate? {
        if let task = tasks.first(where: { $0.id == selectedFocusTaskID }) {
            return FocusCandidate(title: task.title, detail: task.detail)
        }

        if let manualFocusTitle {
            return FocusCandidate(title: manualFocusTitle, detail: "来自时间线")
        }

        return nil
    }

    public static func sample() -> InteractiveDemoState {
        let writing = DemoTask(
            id: SampleIDs.writingTask,
            title: "写作提纲",
            detail: "一次性任务 · 今天 14:00",
            progressLabel: "今天",
            progressRatio: 0.62,
            estimatedMinutes: 25
        )
        let reading = DemoTask(
            id: SampleIDs.readingTask,
            title: "读完这本书",
            detail: "累计任务 · 按页数记录",
            progressLabel: "50/1000",
            progressRatio: 0.05,
            estimatedMinutes: 40
        )
        let running = DemoTask(
            id: SampleIDs.runningTask,
            title: "本周跑 5 次 3 公里",
            detail: "系列任务 · 本周目标",
            progressLabel: "2/5",
            progressRatio: 0.4,
            estimatedMinutes: 55
        )
        let swiftUI = DemoTask(
            id: SampleIDs.swiftUITask,
            title: "学 SwiftUI",
            detail: "长期任务 · 建议拆小后再安排",
            progressLabel: "新",
            progressRatio: 0,
            estimatedMinutes: nil
        )
        let photos = DemoTask(
            id: SampleIDs.photosTask,
            title: "整理相册",
            detail: "低优先级 · 可改天",
            progressLabel: "列表",
            progressRatio: 0,
            estimatedMinutes: nil
        )

        return InteractiveDemoState(
            tasks: [running, writing, reading, swiftUI, photos],
            todayEvents: [
                DemoTimelineEntry(
                    id: SampleIDs.commuteEvent,
                    timeLabel: "10:30",
                    title: "出门",
                    note: "通勤通常约 28 分钟",
                    linkedTaskID: nil,
                    estimatedMinutes: 28
                ),
                DemoTimelineEntry(
                    id: SampleIDs.writingEvent,
                    timeLabel: "14:00",
                    title: "写作提纲",
                    note: "已选为专注候选 · 关联任务",
                    linkedTaskID: SampleIDs.writingTask,
                    estimatedMinutes: 25
                ),
                DemoTimelineEntry(
                    id: SampleIDs.readingEvent,
                    timeLabel: "16:20",
                    title: "读书 20 页",
                    note: "进度：50 / 1000 页",
                    linkedTaskID: SampleIDs.readingTask,
                    estimatedMinutes: 20
                ),
                DemoTimelineEntry(
                    id: SampleIDs.recallEvent,
                    timeLabel: "今晚",
                    title: "回想",
                    note: "可引用今天的完成记录",
                    linkedTaskID: nil,
                    estimatedMinutes: nil
                )
            ],
            planEvents: [
                DemoTimelineEntry(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                    timeLabel: "09:30",
                    title: "长跑",
                    note: "AI 排入 · 预计 55 分钟",
                    linkedTaskID: SampleIDs.runningTask,
                    estimatedMinutes: 55
                ),
                DemoTimelineEntry(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                    timeLabel: "??:??",
                    title: "读书 40 页",
                    note: "未定时间 · 可拖入合适空档",
                    linkedTaskID: SampleIDs.readingTask,
                    isUncertain: true,
                    estimatedMinutes: nil
                ),
                DemoTimelineEntry(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                    timeLabel: "15:00",
                    title: "回邮件",
                    note: "25 分钟",
                    linkedTaskID: nil,
                    estimatedMinutes: 25,
                    isParallel: true
                ),
                DemoTimelineEntry(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
                    timeLabel: "15:00",
                    title: "整理资料",
                    note: "可并行",
                    linkedTaskID: nil,
                    estimatedMinutes: 25,
                    isParallel: true
                )
            ],
            backlogTasks: [swiftUI, photos],
            selectedTodayEventID: SampleIDs.writingEvent,
            selectedFocusTaskID: SampleIDs.writingTask
        )
    }

    public func filteredTasks(matching query: String) -> [DemoTask] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return tasks
        }

        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmedQuery)
                || task.detail.localizedCaseInsensitiveContains(trimmedQuery)
                || task.progressLabel.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    public mutating func selectTodayEvent(id: UUID) {
        guard let event = todayEvents.first(where: { $0.id == id }) else {
            return
        }

        selectedTodayEventID = id

        if let linkedTaskID = event.linkedTaskID {
            selectedFocusTaskID = linkedTaskID
            manualFocusTitle = nil
        } else {
            selectedFocusTaskID = nil
            manualFocusTitle = event.title
        }
    }

    public mutating func selectFocus(taskID: UUID) {
        selectedFocusTaskID = taskID
        manualFocusTitle = nil
        selectedTodayEventID = todayEvents.first(where: { $0.linkedTaskID == taskID })?.id
    }

    public mutating func selectDuration(minutes: Int) {
        selectedDurationMinutes = minutes
    }

    public mutating func completeFocusCandidate(atLabel timeLabel: String) {
        guard let candidate = focusCandidate else {
            return
        }

        if !completedTodayTitles.contains(candidate.title) {
            completedTodayTitles.append(candidate.title)
        }

        let alreadyOnToday = todayEvents.contains { event in
            event.title == candidate.title || event.linkedTaskID == selectedFocusTaskID
        }

        guard !alreadyOnToday else {
            return
        }

        todayEvents.append(
            DemoTimelineEntry(
                id: UUID(),
                timeLabel: timeLabel,
                title: candidate.title,
                note: "刚完成 · 已补进今天",
                linkedTaskID: selectedFocusTaskID,
                estimatedMinutes: selectedDurationMinutes
            )
        )
    }

    public mutating func applyAIPlanning() {
        planEvents = planEvents.map { event in
            var event = event

            if event.estimatedMinutes == nil {
                event.estimatedMinutes = inferredDurationMinutes(for: event.title)
                event.note = "AI 已初始化时长 · 预计 \(event.estimatedMinutes ?? 25) 分钟"
            }

            return event
        }

        guard let chosenTask = backlogTasks.first else {
            return
        }

        backlogTasks.removeFirst()
        planEvents.append(
            DemoTimelineEntry(
                id: UUID(),
                timeLabel: "17:10",
                title: chosenTask.title,
                note: "AI 排入 · 预计 \(chosenTask.estimatedMinutes ?? 35) 分钟",
                linkedTaskID: chosenTask.id,
                estimatedMinutes: chosenTask.estimatedMinutes ?? 35
            )
        )
    }

    public mutating func moveBacklogTaskToTimeline(taskID: UUID, timeLabel: String) {
        guard let taskIndex = backlogTasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        let task = backlogTasks.remove(at: taskIndex)
        planEvents.append(
            DemoTimelineEntry(
                id: UUID(),
                timeLabel: timeLabel,
                title: task.title,
                note: "手动排入 · 预计 \(task.estimatedMinutes ?? 25) 分钟",
                linkedTaskID: task.id,
                estimatedMinutes: task.estimatedMinutes ?? 25
            )
        )
    }

    private func inferredDurationMinutes(for title: String) -> Int {
        if title.contains("读书") {
            return 40
        }

        return 25
    }
}

public struct ZenSession: Sendable, Equatable {
    public let taskTitle: String?
    public let durationMinutes: Int
    public private(set) var remainingSeconds: Int
    public private(set) var isRunning: Bool

    public init(taskTitle: String?, durationMinutes: Int) {
        self.taskTitle = taskTitle
        self.durationMinutes = durationMinutes
        self.remainingSeconds = max(0, durationMinutes * 60)
        self.isRunning = true
    }

    public var isComplete: Bool {
        remainingSeconds == 0
    }

    public var displayTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }

    public mutating func tick(seconds: Int) {
        guard isRunning, !isComplete else {
            return
        }

        remainingSeconds = max(0, remainingSeconds - max(0, seconds))

        if isComplete {
            isRunning = false
        }
    }

    public mutating func pause() {
        isRunning = false
    }

    public mutating func resume() {
        guard !isComplete else {
            return
        }

        isRunning = true
    }
}
