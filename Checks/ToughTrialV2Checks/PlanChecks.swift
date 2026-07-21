import Foundation
import ToughTrialV2Core

func checkSchedulePlanDraftLifecycle() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(
        year: 2027,
        month: 2,
        day: 1,
        hour: 9
    ))!
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-plan-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let engine = try V2Engine.load(from: store)
    let task = try engine.createTask(title: "Run 10 km", at: base)
    let draft = V2PlanDraftRecord(
        id: "weekly-running-draft",
        mode: .scheduleOnly,
        userPrompt: "This week I want to run 10 km",
        summary: "3 km + 3 km + 4 km",
        proposedPlanItems: [
            V2ProposedPlanItem(
                id: "run-one",
                date: base.addingTimeInterval(86_400),
                taskID: task.id,
                title: "Run 3 km"
            ),
            V2ProposedPlanItem(
                id: "run-two",
                date: base.addingTimeInterval(3 * 86_400),
                taskID: task.id,
                title: "Run 3 km"
            ),
            V2ProposedPlanItem(
                id: "run-three",
                date: base.addingTimeInterval(5 * 86_400),
                startAt: base.addingTimeInterval(5 * 86_400 + 10 * 3_600),
                endAt: base.addingTimeInterval(5 * 86_400 + 11 * 3_600),
                taskID: task.id,
                title: "Run 4 km"
            )
        ],
        createdAt: base,
        updatedAt: base
    )

    let taskCountBeforeSave = engine.snapshot.tasks.count
    let firstSaved = try engine.savePlanDraft(draft, at: base.addingTimeInterval(10), calendar: calendar)
    require(engine.snapshot.tasks.count == taskCountBeforeSave, "Saving a schedule draft must not create tasks")
    require(engine.snapshot.planItems.isEmpty, "Saving a schedule draft must not create plan items")

    var revisedDraft = draft
    revisedDraft.summary = "Run three times, with the longest run last"
    let revisedSaved = try engine.savePlanDraft(
        revisedDraft,
        at: base.addingTimeInterval(15),
        calendar: calendar
    )
    require(engine.snapshot.planDrafts.count == 1, "Saving a revised draft should replace instead of duplicate")
    require(revisedSaved.createdAt == firstSaved.createdAt, "Revising a draft should preserve its creation time")
    require(revisedSaved.summary == revisedDraft.summary, "The latest draft content should replace the previous version")

    let reopened = try V2Engine.load(from: store)
    let pendingWorkspace = reopened.planningWorkspaceSnapshot(
        range: DateInterval(start: base, duration: 8 * 86_400)
    )
    require(pendingWorkspace.pendingDrafts.map(\.id) == [draft.id], "A pending draft should survive restart")
    require(pendingWorkspace.planItems.isEmpty, "A pending draft must remain separate from the schedule")

    let acceptance = try reopened.acceptPlanDraft(
        id: draft.id,
        at: base.addingTimeInterval(20),
        calendar: calendar
    )
    require(acceptance.createdTasks.isEmpty, "scheduleOnly must not create tasks")
    require(acceptance.createdPlanItems.count == 3, "A periodic target should materialize as multiple plan items")
    require(
        acceptance.createdPlanItems.allSatisfy { $0.taskID == task.id && $0.sourceDraftID == draft.id },
        "Accepted schedule items should retain task and draft provenance"
    )
    require(acceptance.createdPlanItems[0].startAt == nil, "A plan item may keep only a date")

    let acceptedWorkspace = reopened.planningWorkspaceSnapshot(
        range: DateInterval(start: base, duration: 8 * 86_400)
    )
    require(acceptedWorkspace.pendingDrafts.isEmpty, "Accepted drafts should leave the pending workspace")
    require(acceptedWorkspace.planItems.count == 3, "Accepted items should appear in the planning workspace")

    let reopenedAccepted = try V2Engine.load(from: store)
    require(reopenedAccepted.snapshot.planItems.count == 3, "Accepted plan items should survive restart")
    do {
        _ = try reopenedAccepted.acceptPlanDraft(id: draft.id, at: base.addingTimeInterval(30))
        fatalError("Expected accepted draft protection")
    } catch let error as V2EngineError {
        require(error == .planDraftNotEditable(draft.id), "A draft must not be accepted twice")
    }
}

func checkBreakdownPlanDraftCreatesTreeAtomically() throws {
    let engine = V2Engine()
    let base = Date(timeIntervalSince1970: 1_802_000_000)
    let context = try engine.createTaskContext(title: "Creator growth", colorName: "blue", at: base)
    let root = try engine.createTask(
        title: "Stable praise",
        contextID: context.id,
        kind: .goal,
        at: base
    )
    let draft = V2PlanDraftRecord(
        id: "topic-breakdown-draft",
        mode: .breakdownOnly,
        userPrompt: "Break down the topic library",
        summary: "Create a branch and a concrete first action",
        proposedTaskChanges: [
            V2ProposedTaskChange(
                id: "collect-examples",
                title: "Collect benchmark posts",
                parentID: "topic-library"
            ),
            V2ProposedTaskChange(
                id: "topic-library",
                title: "Topic library",
                parentID: root.id,
                contextID: context.id
            )
        ],
        createdAt: base,
        updatedAt: base
    )

    let taskCountBeforeSave = engine.snapshot.tasks.count
    _ = try engine.savePlanDraft(draft, at: base.addingTimeInterval(10))
    require(engine.snapshot.tasks.count == taskCountBeforeSave, "Saving a breakdown draft must not change the task tree")

    let acceptance = try engine.acceptPlanDraft(id: draft.id, at: base.addingTimeInterval(20))
    require(acceptance.createdPlanItems.isEmpty, "breakdownOnly must not create schedule items")
    require(acceptance.createdTasks.count == 2, "The accepted breakdown should create both proposed tasks")

    let branch = acceptance.createdTasks.first { $0.title == "Topic library" }
    let leaf = acceptance.createdTasks.first { $0.title == "Collect benchmark posts" }
    require(branch?.parentID == root.id, "The proposed branch should attach to the existing goal")
    require(leaf?.parentID == branch?.id, "Temporary proposal IDs should resolve even when the child appears first")
    require(leaf?.contextID == context.id, "A child should inherit its resolved parent's context")
    require(engine.snapshot.planItems.isEmpty, "Breakdown acceptance should leave the schedule unchanged")
}

func checkPlanDraftFailureRollsBackAndDiscardStaysClean() throws {
    let engine = V2Engine()
    let base = Date(timeIntervalSince1970: 1_803_000_000)
    let task = try engine.createTask(title: "Submit report", at: base)
    let draft = V2PlanDraftRecord(
        id: "fragile-schedule-draft",
        mode: .scheduleOnly,
        userPrompt: "Put this on Friday",
        summary: "One date-only item",
        proposedPlanItems: [
            V2ProposedPlanItem(
                id: "report-friday",
                date: base.addingTimeInterval(86_400),
                taskID: task.id,
                title: task.title
            )
        ],
        createdAt: base,
        updatedAt: base
    )
    _ = try engine.savePlanDraft(draft, at: base.addingTimeInterval(10))
    try engine.archiveTask(id: task.id, at: base.addingTimeInterval(20))

    let snapshotBeforeFailure = engine.snapshot
    do {
        _ = try engine.acceptPlanDraft(id: draft.id, at: base.addingTimeInterval(30))
        fatalError("Expected archived task protection")
    } catch let error as V2EngineError {
        require(error == .taskArchived(task.id), "Acceptance should reject an archived task reference")
    }
    require(engine.snapshot == snapshotBeforeFailure, "Failed acceptance must roll back every proposed write")

    let discarded = try engine.discardPlanDraft(id: draft.id, at: base.addingTimeInterval(40))
    require(discarded.status == .discarded, "Discard should resolve the draft without accepting it")
    require(engine.snapshot.planItems.isEmpty, "Discarding a draft must not create plan items")
    do {
        _ = try engine.acceptPlanDraft(id: draft.id, at: base.addingTimeInterval(50))
        fatalError("Expected discarded draft protection")
    } catch let error as V2EngineError {
        require(error == .planDraftNotEditable(draft.id), "Discarded drafts must not be accepted later")
    }

    let mixedDraft = V2PlanDraftRecord(
        id: "mixed-not-yet-supported",
        mode: .mixed,
        userPrompt: "Break it down and schedule it",
        summary: "A future phase",
        createdAt: base,
        updatedAt: base
    )
    let snapshotBeforeMixed = engine.snapshot
    do {
        _ = try engine.savePlanDraft(mixedDraft, at: base.addingTimeInterval(60))
        fatalError("Expected mixed mode boundary")
    } catch let error as V2EngineError {
        require(error == .unsupportedPlanMode(.mixed), "Mixed mode should remain an explicit later phase")
    }
    require(engine.snapshot == snapshotBeforeMixed, "Unsupported modes must not mutate durable state")
}
