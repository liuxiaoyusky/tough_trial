import Foundation
import ToughTrialV2Core

func checkTaskImportIsIdempotentAndBuildsHierarchy() throws {
    let base = Date(timeIntervalSince1970: 1_800_100_000)
    let rootSource = V2TaskImportSource(
        kind: .localCatalog,
        key: "context-root:fund",
        updatedAt: base
    )
    let childSource = V2TaskImportSource(
        kind: .feishuBase,
        key: "base:table:record",
        location: "https://example.test/base",
        updatedAt: base
    )
    let manifest = V2TaskImportManifest(
        generatedAt: base,
        contexts: [
            V2TaskImportContext(key: "fund", title: "基金", colorName: "blue")
        ],
        tasks: [
            V2TaskImportRecord(
                source: rootSource,
                contextKey: "fund",
                title: "基金",
                kind: .goal,
                status: .notStarted,
                createdAt: base,
                updatedAt: base
            ),
            V2TaskImportRecord(
                source: childSource,
                parentSource: V2TaskImportSourceIdentity(
                    kind: rootSource.kind,
                    key: rootSource.key
                ),
                contextKey: "fund",
                title: "Read annual report",
                kind: .commitment,
                status: .active,
                createdAt: base,
                updatedAt: base
            )
        ]
    )
    let engine = V2Engine()

    let first = try engine.syncImportedTasks(manifest)
    require(first.createdContexts == 1, "First import should create its context")
    require(first.createdTasks == 2, "First import should create root and child")
    require(engine.snapshot.planItems.isEmpty, "Task import must not schedule Today")

    let root = engine.snapshot.tasks.first {
        $0.sourceReference?.key == rootSource.key
    }
    let child = engine.snapshot.tasks.first {
        $0.sourceReference?.key == childSource.key
    }
    require(root != nil, "Imported root should retain its source identity")
    require(child?.parentID == root?.id, "Imported parent source should resolve to task hierarchy")
    require(child?.status == .active, "Imported external status should be retained")

    let second = try engine.syncImportedTasks(manifest)
    require(second.createdContexts == 0, "Repeated import should reuse its context")
    require(second.createdTasks == 0, "Repeated import should not duplicate tasks")
    require(second.updatedTasks == 0, "Unchanged repeated import should be a no-op")
    require(second.unchangedTasks == 2, "Repeated import should report unchanged tasks")
    require(engine.snapshot.tasks.count == 2, "Repeated import should keep a stable task count")
}

func checkTaskImportPreservesCompletionAndRollsBackInvalidHierarchy() throws {
    let base = Date(timeIntervalSince1970: 1_800_110_000)
    let rootSource = V2TaskImportSource(
        kind: .localCatalog,
        key: "context-root:ai",
        updatedAt: base
    )
    let childSource = V2TaskImportSource(
        kind: .obsidianMarkdown,
        key: "personal:task",
        updatedAt: base
    )
    let context = V2TaskImportContext(key: "ai", title: "AI", colorName: "violet")
    let rootRecord = V2TaskImportRecord(
        source: rootSource,
        contextKey: "ai",
        title: "AI",
        kind: .goal,
        status: .notStarted,
        createdAt: base,
        updatedAt: base
    )
    let childRecord = V2TaskImportRecord(
        source: childSource,
        parentSource: V2TaskImportSourceIdentity(
            kind: rootSource.kind,
            key: rootSource.key
        ),
        contextKey: "ai",
        title: "Build workflow",
        kind: .goal,
        status: .notStarted,
        createdAt: base,
        updatedAt: base
    )
    let engine = V2Engine()
    _ = try engine.syncImportedTasks(
        V2TaskImportManifest(
            generatedAt: base,
            contexts: [context],
            tasks: [rootRecord, childRecord]
        )
    )

    let childID = engine.snapshot.tasks.first {
        $0.sourceReference?.key == childSource.key
    }!.id
    _ = try engine.completeTask(id: childID, at: base.addingTimeInterval(60))

    var updatedChild = childRecord
    updatedChild.title = "Build reliable workflow"
    updatedChild.status = .active
    updatedChild.updatedAt = base.addingTimeInterval(120)
    let updateSummary = try engine.syncImportedTasks(
        V2TaskImportManifest(
            generatedAt: base.addingTimeInterval(120),
            contexts: [context],
            tasks: [rootRecord, updatedChild]
        )
    )
    let locallyCompleted = engine.snapshot.tasks.first { $0.id == childID }
    require(locallyCompleted?.title == updatedChild.title, "Source metadata may refresh")
    require(locallyCompleted?.status == .done, "External active state must not reopen local completion")
    require(updateSummary.preservedLocalStatuses == 1, "Import should report preserved local completion")

    let beforeInvalidImport = engine.snapshot
    let invalid = V2TaskImportRecord(
        source: V2TaskImportSource(
            kind: .obsidianMarkdown,
            key: "personal:invalid",
            updatedAt: base
        ),
        parentSource: V2TaskImportSourceIdentity(
            kind: rootSource.kind,
            key: rootSource.key
        ),
        contextKey: nil,
        title: "Invalid isolated child",
        kind: .maintenance,
        status: .notStarted,
        createdAt: base,
        updatedAt: base
    )

    do {
        _ = try engine.syncImportedTasks(
            V2TaskImportManifest(
                generatedAt: base,
                contexts: [context],
                tasks: [rootRecord, invalid]
            )
        )
        fatalError("Expected parent context mismatch")
    } catch let error as V2TaskImportError {
        require(
            error == .parentContextMismatch(invalid.source.identity),
            "Invalid cross-context parent should be rejected"
        )
    }
    require(engine.snapshot == beforeInvalidImport, "Failed import should roll back atomically")
}

func checkLegacyTaskWithoutSourceReferenceStillDecodes() throws {
    let json = """
    {
      "id": "legacy",
      "contextID": null,
      "parentID": null,
      "title": "Legacy task",
      "note": "",
      "kind": "goal",
      "status": "notStarted",
      "createdAt": 100,
      "updatedAt": 100,
      "completedAt": null,
      "archivedAt": null
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let task = try decoder.decode(V2Task.self, from: Data(json.utf8))

    require(task.id == "legacy", "Legacy task should decode")
    require(task.sourceReference == nil, "Legacy task should default source reference to nil")
}
