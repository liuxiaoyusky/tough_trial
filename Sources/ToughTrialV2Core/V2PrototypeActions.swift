import Foundation

public extension V2PrototypeState {
    @discardableResult
    mutating func startSession(taskID: String?, title: String, startedAtLabel: String) -> Bool {
        if let taskID, !flattenTasks().contains(where: { $0.id == taskID }) {
            return false
        }

        if let taskID, activeSessions.contains(where: { $0.taskID == taskID }) {
            return false
        }

        let sessionTaskID = taskID ?? "manual"
        activeSessions.append(
            V2ActiveSession(
                id: "session-\(sessionTaskID)-\(timelineItems.count + activeSessions.count + 1)",
                taskID: taskID,
                title: title,
                startedAtLabel: startedAtLabel,
                currentElapsed: 0,
                totalElapsed: 0,
                status: .running
            )
        )

        if let taskID {
            selectedTaskID = taskID
            updateTask(taskID) { task in
                task.status = .active
            }
        }

        return true
    }

    mutating func toggleSession(_ id: String) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[index].status = activeSessions[index].status == .running ? .paused : .running

        if let taskID = activeSessions[index].taskID {
            let status = activeSessions[index].status
            updateTask(taskID) { task in
                task.status = status == .paused ? .paused : .active
            }
        }
    }

    @discardableResult
    mutating func focusActiveSession(_ id: String) -> Bool {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return false }
        let session = activeSessions.remove(at: index)
        activeSessions.insert(session, at: 0)
        selectedTaskID = session.taskID
        return true
    }

    mutating func endSession(_ id: String, totalElapsed: Int, endLabel: String) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = activeSessions.remove(at: index)

        if let taskID = session.taskID {
            updateTask(taskID) { task in
                task.spentMinutes += totalElapsed
                task.status = .planned
            }
        }

        timelineItems.append(
            V2TimelineItem(
                id: "timeline-session-\(timelineItems.count + 1)",
                timeLabel: endLabel,
                title: session.title,
                detail: "记录一次 \(totalElapsed) 分钟执行。",
                taskID: session.taskID,
                isDone: false
            )
        )
    }

    @discardableResult
    mutating func completeTimelineItem(_ id: String) -> Bool {
        guard let index = timelineItems.firstIndex(where: { $0.id == id }) else { return false }
        timelineItems[index].isDone = true

        if let taskID = timelineItems[index].taskID {
            updateTask(taskID) { task in
                task.status = .done
            }
        }

        return true
    }

    @discardableResult
    mutating func restoreTimelineItem(_ id: String) -> Bool {
        guard let index = timelineItems.firstIndex(where: { $0.id == id }) else { return false }
        timelineItems[index].isDone = false

        if let taskID = timelineItems[index].taskID {
            let liveStatus = activeSessions.first { $0.taskID == taskID }?.status
            updateTask(taskID) { task in
                switch liveStatus {
                case .running:
                    task.status = .active
                case .paused:
                    task.status = .paused
                case nil:
                    task.status = .planned
                }
            }
        }

        return true
    }

    mutating func quickAddTodayTask(title: String) {
        let taskID = "task-quick-\(flattenTasks().count + 1)"
        tasks.append(
            V2TaskNode(
                id: taskID,
                title: title,
                subtitle: "快速加入今天",
                goal: "先记录，再决定是否展开",
                colorName: "teal",
                status: .planned,
                spentMinutes: 0
            )
        )
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-quick-\(timelineItems.count + 1)",
                timeLabel: "今天",
                title: title,
                detail: "快速加入今天，可并行处理，不打断当前执行。",
                taskID: taskID,
                isDone: false
            )
        )
        selectedTaskID = taskID
    }

    mutating func quickAddScheduledTask(
        title: String,
        on date: Date,
        calendar: Calendar = .current
    ) {
        let taskID = "task-scheduled-\(flattenTasks().count + 1)"
        let day = calendar.startOfDay(for: date)
        tasks.append(
            V2TaskNode(
                id: taskID,
                title: title,
                subtitle: "已放到 \(Self.scheduleDateLabel(day, calendar: calendar))",
                goal: "",
                colorName: "teal",
                status: .planned,
                spentMinutes: 0
            )
        )
        scheduledTasks.append(
            V2ScheduledTask(
                id: "schedule-quick-\(scheduledTasks.count + 1)",
                title: title,
                detail: "仅确定日期，时间可以之后再安排。",
                taskID: taskID,
                date: day,
                placement: .allDay,
                isDone: false
            )
        )
        selectedTaskID = taskID
    }

    mutating func setPlanScope(_ scope: String?) {
        planScope = scope
    }

    mutating func beginPlanPrompt(
        _ prompt: String,
        scope: String? = nil,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if currentPlanDraft != nil {
            reviseCurrentPlanDraft(trimmed, at: date, calendar: calendar)
            return
        }

        planMessages.append(V2PlanMessage(id: "plan-user-\(planMessages.count + 1)", role: .user, text: trimmed))
        planScope = scope ?? Self.inferredPlanScope(from: trimmed) ?? planScope
        planConversationPhase = .clarifying
        planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(planMessages.count + 1)",
                role: .agent,
                text: Self.planClarification(for: trimmed)
            )
        )
    }

    mutating func confirmPlanClarification(
        _ response: String,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard planConversationPhase == .clarifying,
              let prompt = planMessages.last(where: { $0.role == .user })?.text else { return }

        let draft = Self.makePlanDraft(
            userPrompt: prompt,
            response: response,
            scope: planScope,
            at: date,
            calendar: calendar
        )
        currentPlanDraft = draft
        planConversationPhase = .reviewingDraft
        if planMessages.last?.role == .agent {
            planMessages.removeLast()
        }
        planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(planMessages.count + 1)",
                role: .agent,
                text: Self.draftIntroduction(for: draft)
            )
        )
    }

    mutating func reviseCurrentPlanDraft(
        _ prompt: String,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let currentPlanDraft else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        planMessages.append(V2PlanMessage(id: "plan-user-\(planMessages.count + 1)", role: .user, text: trimmed))
        self.currentPlanDraft = Self.makePlanDraft(
            id: currentPlanDraft.id,
            userPrompt: currentPlanDraft.userPrompt,
            response: trimmed,
            scope: planScope,
            at: date,
            calendar: calendar
        )
        planConversationPhase = .reviewingDraft
        planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(planMessages.count + 1)",
                role: .agent,
                text: "我已根据补充调整草稿。你可以继续修改，或直接加入计划。"
            )
        )
    }

    // Compatibility path for core checks and non-conversational callers.
    mutating func sendPlanPrompt(_ prompt: String) {
        beginPlanPrompt(prompt)
        confirmPlanClarification("可以")
    }

    mutating func saveCurrentPlanDraft() {
        guard let draft = currentPlanDraft else { return }
        if let index = savedPlanDrafts.firstIndex(where: { $0.id == draft.id }) {
            savedPlanDrafts[index] = draft
        } else {
            savedPlanDrafts.append(draft)
        }
    }

    mutating func completeCurrentPlanDraftAcceptance() {
        guard currentPlanDraft != nil else { return }
        saveCurrentPlanDraft()
        currentPlanDraft = nil
        planConversationPhase = .complete
        planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(planMessages.count + 1)",
                role: .agent,
                text: "已加入计划。之后的实际执行仍由你决定。"
            )
        )
    }

    mutating func acceptCurrentPlanDraft() {
        guard let draft = currentPlanDraft else { return }
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-plan-\(timelineItems.count + 1)",
                timeLabel: "计划",
                title: draft.title,
                detail: draft.summary,
                taskID: nil,
                isDone: false
            )
        )
        completeCurrentPlanDraftAcceptance()
    }

    func recallDraft(for date: String) -> String {
        recallDraftsByDate[date] ?? (date == "今天" ? recallDraft : "")
    }

    mutating func setRecallDraft(_ draft: String, for date: String) {
        recallDraftsByDate[date] = draft
        if date == "今天" {
            recallDraft = draft
        }
    }

    func selectedRecallReferenceIDs(for date: String) -> [String] {
        selectedRecallReferenceIDsByDate[date] ?? (date == "今天" ? selectedRecallReferenceIDs : [])
    }

    func appliedRecallText(for date: String) -> String {
        appliedRecallTextsByDate[date] ?? (date == "今天" ? appliedRecallText : "")
    }

    mutating func insertRecallReference(_ id: String) {
        insertRecallReference(id, for: "今天")
    }

    mutating func insertRecallReference(_ id: String, for date: String) {
        guard let reference = recallReferences.first(where: { $0.id == id }) else { return }
        var selectedIDs = selectedRecallReferenceIDs(for: date)
        if !selectedIDs.contains(id) {
            selectedIDs.append(id)
            selectedRecallReferenceIDsByDate[date] = selectedIDs
            if date == "今天" {
                selectedRecallReferenceIDs = selectedIDs
            }
            appendRecallEvidence(reference, for: date)
        }
    }

    mutating func applyRecallDraft() {
        applyRecallDraft(for: "今天")
    }

    mutating func applyRecallDraft(for date: String) {
        let draft = recallDraft(for: date)
        appliedRecallTextsByDate[date] = draft
        if date == "今天" {
            appliedRecallText = draft
        }
    }

    mutating func toggleRecallFullscreen() {
        isRecallFullscreen.toggle()
    }
}

private extension V2PrototypeState {
    static func inferredPlanScope(from prompt: String) -> String? {
        if prompt.contains("明天") { return "明天" }
        if prompt.contains("今天") { return "今天" }
        if prompt.contains("这周") || prompt.contains("本周") || prompt.contains("一周") { return "本周" }
        if prompt.contains("这几天") || prompt.contains("三天") || prompt.contains("3天") { return "近三日" }
        if prompt.contains("这个月") || prompt.contains("本月") { return "本月" }
        return nil
    }

    static func planClarification(for prompt: String) -> String {
        if prompt.contains("跑") || prompt.contains("公里") {
            let target = kilometerTarget(from: prompt)
            let first = max(1, target / 3)
            let second = max(1, target / 3)
            let third = max(1, target - first - second)
            return "分三次会比较轻松：\(first) + \(second) + \(third) 公里，最长的一次放在周末。这样安排可以吗？"
        }
        return "我可以先给一个轻量安排，只确定最重要的推进点，其余时间保留弹性。这样可以吗？"
    }

    static func draftIntroduction(for draft: V2PlanDraft) -> String {
        if draft.userPrompt.contains("跑") || draft.userPrompt.contains("公里") {
            return "可以，先拆成\(draft.scheduleItems.count)次轻量安排。你可以继续补充限制，或者直接确认。"
        }
        return "可以，我先整理成一份轻量草稿。你可以继续补充限制，或者直接确认。"
    }

    static func makePlanDraft(
        id: String = UUID().uuidString,
        userPrompt: String,
        response: String,
        scope: String?,
        at date: Date,
        calendar: Calendar
    ) -> V2PlanDraft {
        if userPrompt.contains("跑") || userPrompt.contains("公里") {
            return makeRunningDraft(
                id: id,
                userPrompt: userPrompt,
                response: response,
                scope: scope,
                at: date,
                calendar: calendar
            )
        }

        let baseDate = planBaseDate(for: scope, at: date, calendar: calendar)
        let firstDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let secondDate = calendar.date(byAdding: .day, value: 3, to: baseDate) ?? baseDate
        return V2PlanDraft(
            id: id,
            userPrompt: userPrompt,
            title: "\(scope ?? "近期")安排 · 2 个推进点",
            summary: "先安排最重要的推进，其余时间保留弹性。",
            decisions: ["只形成草稿", "确认后再写入正式计划"],
            scheduleItems: [
                makeScheduleItem(id: "\(id)-1", date: firstDate, hour: 10, minute: 0, title: "推进当前最重要的一步", calendar: calendar),
                makeScheduleItem(id: "\(id)-2", date: secondDate, hour: 16, minute: 0, title: "回看进展并决定下一步", calendar: calendar)
            ]
        )
    }

    static func makeRunningDraft(
        id: String,
        userPrompt: String,
        response: String,
        scope: String?,
        at date: Date,
        calendar: Calendar
    ) -> V2PlanDraft {
        let target = kilometerTarget(from: userPrompt)
        let useTwoRuns = response.contains("两次")
        let distances: [Int]
        let offsets: [Int]
        let times: [(Int, Int)]

        if useTwoRuns {
            let first = max(1, target / 2)
            distances = [first, max(1, target - first)]
            offsets = [1, 4]
            times = [(19, 0), (9, 0)]
        } else {
            let first = max(1, target / 3)
            let second = max(1, target / 3)
            distances = [first, second, max(1, target - first - second)]
            offsets = [0, 2, 5]
            times = [(19, 0), (19, 30), (9, 0)]
        }

        let baseDate = planBaseDate(for: scope, at: date, calendar: calendar)
        let items = distances.indices.map { index -> V2PlanDraftScheduleItem in
            let runDate = calendar.date(byAdding: .day, value: offsets[index], to: baseDate) ?? baseDate
            let pace = index == distances.indices.last ? "慢跑" : "轻松跑"
            return makeScheduleItem(
                id: "\(id)-\(index + 1)",
                date: runDate,
                hour: times[index].0,
                minute: times[index].1,
                title: "\(pace) \(distances[index]) 公里",
                calendar: calendar
            )
        }

        return V2PlanDraft(
            id: id,
            userPrompt: userPrompt,
            title: "\(scope ?? "近期")跑步 · \(items.count) 次",
            summary: "合计 \(target) 公里，保留两天空档",
            decisions: ["按轻量节奏拆分", "最长的一次放在周末附近"],
            scheduleItems: items
        )
    }

    static func makeScheduleItem(
        id: String,
        date: Date,
        hour: Int,
        minute: Int,
        title: String,
        calendar: Calendar
    ) -> V2PlanDraftScheduleItem {
        let startAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        return V2PlanDraftScheduleItem(
            id: id,
            date: calendar.startOfDay(for: date),
            startAt: startAt,
            endAt: startAt.flatMap { calendar.date(byAdding: .minute, value: 45, to: $0) },
            title: title
        )
    }

    static func planBaseDate(for scope: String?, at date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        if scope == "明天" {
            return calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    static func kilometerTarget(from prompt: String) -> Int {
        guard let range = prompt.range(of: #"\d+\s*公里"#, options: .regularExpression) else {
            return 10
        }
        return Int(prompt[range].filter(\.isNumber)) ?? 10
    }

    static func scheduleDateLabel(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    mutating func updateTask(_ id: String, mutate: (inout V2TaskNode) -> Void) {
        updateTask(id, in: &tasks, mutate: mutate)
    }

    func updateTask(_ id: String, in nodes: inout [V2TaskNode], mutate: (inout V2TaskNode) -> Void) {
        for index in nodes.indices {
            if nodes[index].id == id {
                mutate(&nodes[index])
                return
            }
            updateTask(id, in: &nodes[index].children, mutate: mutate)
        }
    }

    mutating func appendRecallEvidence(_ reference: V2RecallReference, for date: String) {
        let evidence = "[\(reference.kind.rawValue)] \(reference.title)：\(reference.detail)"
        let currentDraft = recallDraft(for: date)
        if currentDraft.isEmpty {
            setRecallDraft(evidence, for: date)
        } else {
            setRecallDraft("\(currentDraft)\n\(evidence)", for: date)
        }
    }
}
