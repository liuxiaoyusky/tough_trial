import Foundation
import ToughTrialV2Core

func checkExternalConnectorFixtureProtocol() async throws {
    let connector = V2FixtureExternalConnector()
    let session = V2ExternalConnectorSession()
    let engine = V2Engine()
    let initialTasks = engine.snapshot.tasks

    let firstPage = try await session.syncPage(from: connector, cursor: nil)
    require(firstPage.insertedCount == 2, "The first fixture page should insert two observations")
    require(
        firstPage.nextCursor != nil,
        "The first fixture page should advance to the second page"
    )
    require(session.cursor == firstPage.nextCursor, "A valid page should advance the session cursor")
    require(session.observations.count == 2, "The first fixture page should retain two observations")
    require(
        engine.snapshot.tasks == initialTasks,
        "Observing external data must not create durable tasks"
    )

    let observationsAfterFirstPull = session.observations
    let replay = try await session.syncPage(from: connector, cursor: nil)
    require(replay.insertedCount == 0, "Replaying the same cursor should not insert observations")
    require(replay.updatedCount == 0, "Replaying unchanged observations should not update them")
    require(replay.unchangedCount == 2, "Replaying the same cursor should be idempotent")
    require(
        session.observations == observationsAfterFirstPull,
        "Replaying the same cursor should leave retained observations unchanged"
    )
    require(
        session.cursor == firstPage.nextCursor,
        "Replaying the first page should retain its next cursor"
    )

    let invalidCursor = V2ConnectorCursor(rawValue: "invalid-fixture-cursor")
    let cursorBeforeInvalidCursor = session.cursor
    let observationsBeforeInvalidCursor = session.observations
    do {
        _ = try await session.syncPage(from: connector, cursor: invalidCursor)
        fatalError("An invalid opaque cursor should fail")
    } catch V2ExternalConnectorError.invalidCursor(let rawValue) {
        require(
            rawValue == invalidCursor.rawValue,
            "The cursor error should preserve the rejected opaque value"
        )
    }
    require(
        session.cursor == cursorBeforeInvalidCursor,
        "An invalid opaque cursor must not mutate the retained cursor"
    )
    require(
        session.observations == observationsBeforeInvalidCursor,
        "An invalid opaque cursor must not mutate retained observations"
    )

    guard let secondCursor = firstPage.nextCursor else {
        fatalError("The fixed fixture should contain a second page")
    }
    let secondPage = try await session.syncPage(from: connector, cursor: secondCursor)
    require(secondPage.insertedCount == 1, "The second fixture page should insert one observation")
    require(secondPage.nextCursor == nil, "The second fixture page should complete pagination")
    require(session.observations.count == 3, "Both fixture pages should retain three observations")

    var invalidPages = V2FixtureExternalConnector.standardPages
    let invalidKey = V2ExternalObjectKey(
        provider: .fixture,
        containerID: "stage-0",
        externalID: "invalid-title"
    )
    invalidPages[1].append(
        V2ExternalObservation(
            key: invalidKey,
            title: "   ",
            versionMarker: "v1",
            location: "fixture://stage-0/invalid-title"
        )
    )
    let invalidConnector = V2FixtureExternalConnector(pages: invalidPages)
    let atomicSession = V2ExternalConnectorSession()
    let atomicFirstPage = try await atomicSession.syncPage(from: invalidConnector, cursor: nil)
    let cursorBeforeInvalidPage = atomicSession.cursor
    let observationsBeforeInvalidPage = atomicSession.observations

    do {
        _ = try await atomicSession.syncPage(
            from: invalidConnector,
            cursor: atomicFirstPage.nextCursor
        )
        fatalError("A page containing an invalid observation should fail")
    } catch V2ExternalConnectorError.blankObservationTitle(let key) {
        require(key == invalidKey, "The validation error should identify the invalid observation")
    }

    require(
        atomicSession.cursor == cursorBeforeInvalidPage,
        "A failed page must not advance the cursor"
    )
    require(
        atomicSession.observations == observationsBeforeInvalidPage,
        "A failed page must not retain any partial observations"
    )
    require(
        atomicSession.observations[V2FixtureExternalConnector.standardPages[1][0].key] == nil,
        "A valid observation preceding an invalid one must also roll back"
    )

    let firstKey = V2FixtureExternalConnector.standardPages[0][0].key
    let proposal = try session.proposeTask(for: firstKey)
    require(
        engine.snapshot.tasks == initialTasks,
        "Creating an unconfirmed proposal must not create durable tasks"
    )

    let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let created = try session.confirmTaskProposal(
        id: proposal.id,
        with: engine,
        at: confirmedAt
    )
    require(engine.snapshot.tasks.count == 1, "Confirming a proposal should create one durable task")
    require(created.sourceReference?.kind == .fixture, "The task should preserve its fixture source kind")
    require(
        created.sourceReference?.key == firstKey.sourceKey,
        "The task should preserve its external source key"
    )
    require(
        created.sourceReference?.location == proposal.sourceReference.location,
        "The task should preserve its external source location"
    )

    let repeated = try session.confirmTaskProposal(
        id: proposal.id,
        with: engine,
        at: confirmedAt.addingTimeInterval(60)
    )
    require(repeated.id == created.id, "Repeated confirmation should return the original task")
    require(engine.snapshot.tasks.count == 1, "Repeated confirmation must not create a duplicate task")

    let staleKey = V2FixtureExternalConnector.standardPages[0][1].key
    let staleProposal = try session.proposeTask(for: staleKey)
    var updatedPages = V2FixtureExternalConnector.standardPages
    updatedPages[0][1].versionMarker = "v2"
    updatedPages[0][1].updatedAt = confirmedAt.addingTimeInterval(120)
    let updatedConnector = V2FixtureExternalConnector(pages: updatedPages)
    _ = try await session.syncPage(from: updatedConnector, cursor: nil)

    do {
        _ = try session.confirmTaskProposal(
            id: staleProposal.id,
            with: engine,
            at: confirmedAt.addingTimeInterval(180)
        )
        fatalError("A proposal based on an older source version should be rejected")
    } catch V2ExternalConnectorError.staleProposal(let proposalID) {
        require(proposalID == staleProposal.id, "The stale error should identify the old proposal")
    }

    require(
        engine.snapshot.tasks.count == 1,
        "Rejecting a stale proposal must not create another durable task"
    )
}
