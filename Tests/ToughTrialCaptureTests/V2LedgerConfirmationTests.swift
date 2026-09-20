import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2LedgerConfirmationTests: XCTestCase {
    func testLedgerCandidateCanBeCorrectedBeforeConfirmationAndKeepsCorrectionTrace() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(
            text: "午饭花了三十八，不对，是三十五，昨天的",
            at: Date(timeIntervalSince1970: 1_789_307_200),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        let candidate = V2CaptureCandidate(
            candidateID: "lunch",
            kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午饭", amount: "38", currency: "CNY", direction: .expense, localDate: "2026-09-08")
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture"
        )

        let corrected = try engine.reviseLedgerCandidate(
            batchID: batch.id,
            candidateID: candidate.candidateID,
            sourceRevision: batch.proposal.sourceRevision,
            draft: .init(text: "午饭", amount: "35", currency: "CNY", direction: .expense, localDate: "2026-09-08"),
            at: source.recordedAt
        )

        XCTAssertEqual(corrected.payload.amount, "35")
        XCTAssertEqual(engine.snapshot.capture.batches.last?.proposal.items.first?.payload.amount, "38")
        XCTAssertEqual(engine.snapshot.capture.batches.last?.effectiveCandidate(for: candidate.candidateID)?.payload.amount, "35")
        XCTAssertEqual(engine.snapshot.capture.batches.last?.corrections.map(\.field), [.amount])
        XCTAssertEqual(engine.snapshot.capture.batches.last?.corrections.first?.candidateID, candidate.candidateID)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
    }

    func testConfirmLedgerCandidateCommitsCurrentCorrectionAtomicallyAndIsIdempotent() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "午饭 38 CNY", at: Date(), timeZone: .current)
        let candidate = V2CaptureCandidate(
            candidateID: "atomic-lunch",
            kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午饭", amount: "38", currency: "CNY", direction: .expense)
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture"
        )

        let draft = V2LedgerCandidateDraft(
            text: "午饭",
            amount: "35",
            currency: "CNY",
            direction: .expense
        )
        let saved = try engine.confirmLedgerCandidate(
            batchID: batch.id,
            candidateID: candidate.candidateID,
            sourceRevision: batch.proposal.sourceRevision,
            draft: draft
        )

        XCTAssertEqual(saved.status, .needsConfirmation)
        XCTAssertEqual(engine.snapshot.capture.ledger.map(\.amount), ["35"])
        XCTAssertEqual(engine.snapshot.capture.batches.last?.proposal.items.first?.payload.amount, "38")
        XCTAssertEqual(engine.snapshot.capture.batches.last?.effectiveCandidate(for: candidate.candidateID)?.payload.amount, "35")
        XCTAssertEqual(engine.snapshot.capture.batches.last?.corrections.first?.candidateID, candidate.candidateID)

        let repeated = try engine.confirmLedgerCandidate(
            batchID: batch.id,
            candidateID: candidate.candidateID,
            sourceRevision: batch.proposal.sourceRevision,
            draft: draft
        )
        XCTAssertEqual(repeated, saved)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
    }

    func testMissingLedgerFieldCanBeCompletedAndRetriedWithoutDuplicateLedgerRows() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "午饭花了三十五", at: Date(), timeZone: .current)
        let candidate = V2CaptureCandidate(
            candidateID: "missing-currency",
            kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午饭", amount: "35", direction: .expense)
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture"
        )

        let pending = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID)
        XCTAssertEqual(pending.status, .needsInformation)
        XCTAssertEqual(pending.error, .unknownCurrency)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)

        _ = try engine.reviseLedgerCandidate(
            batchID: batch.id,
            candidateID: candidate.candidateID,
            sourceRevision: batch.proposal.sourceRevision,
            draft: .init(text: "午饭", amount: "35", currency: "CNY", direction: .expense)
        )
        let saved = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID)
        XCTAssertEqual(saved.status, .needsConfirmation)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.amount, "35")

        let repeated = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID)
        XCTAssertEqual(repeated, saved)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
    }

    func testLedgerCandidateCorrectionAfterApplyCannotOverwriteSavedLedger() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "咖啡 20 CNY", at: Date())
        let candidate = V2CaptureCandidate(
            candidateID: "coffee",
            kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "咖啡", amount: "20", currency: "CNY", direction: .expense)
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture"
        )
        let receipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID)
        XCTAssertEqual(receipt.status, .needsConfirmation)

        XCTAssertThrowsError(try engine.reviseLedgerCandidate(
            batchID: batch.id,
            candidateID: candidate.candidateID,
            sourceRevision: batch.proposal.sourceRevision,
            draft: .init(text: "咖啡", amount: "25", currency: "CNY", direction: .expense)
        )) { error in
            XCTAssertEqual(error as? V2CaptureError, .staleTarget)
        }
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.amount, "20")
    }

    func testMixedTaskOrRecallCannotBeConvertedIntoLedger() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "整理发票并记录今天", at: Date())
        let task = V2CaptureCandidate(
            candidateID: "task-candidate",
            kind: .task,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "整理发票", operations: [.init(kind: .createTask, localID: "invoice", title: "整理发票")])
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [task]),
            model: "fixture"
        )
        let draft = V2LedgerCandidateDraft(text: "发票", amount: "35", currency: "CNY", direction: .expense)

        XCTAssertThrowsError(try engine.reviseLedgerCandidate(
            batchID: batch.id, candidateID: task.candidateID,
            sourceRevision: source.revision, draft: draft
        )) { error in
            XCTAssertEqual(error as? V2CaptureError, .invalidSchema)
        }
        XCTAssertThrowsError(try engine.confirmLedgerCandidate(
            batchID: batch.id, candidateID: task.candidateID,
            sourceRevision: source.revision, draft: draft
        )) { error in
            XCTAssertEqual(error as? V2CaptureError, .invalidSchema)
        }
        XCTAssertEqual(engine.snapshot.capture.batches.last?.effectiveCandidate(for: task.candidateID), task)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
    }

    func testOtherCanBeExplicitlyCompletedAsLedgerWithoutCarryingNoteFields() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "晚餐花费记一下", at: Date())
        let other = V2CaptureCandidate(
            candidateID: "other-candidate",
            kind: .other,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: source.text)
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [other]),
            model: "fixture"
        )

        let saved = try engine.confirmLedgerCandidate(
            batchID: batch.id,
            candidateID: other.candidateID,
            sourceRevision: source.revision,
            draft: .init(text: "晚餐", amount: "88", currency: "CNY", direction: .expense)
        )

        XCTAssertEqual(saved.status, .needsConfirmation)
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.text, "晚餐")
        XCTAssertNil(engine.snapshot.capture.batches.last?.effectiveCandidate(for: other.candidateID)?.payload.title)
        XCTAssertNil(engine.snapshot.capture.batches.last?.effectiveCandidate(for: other.candidateID)?.payload.operations)
        XCTAssertEqual(engine.snapshot.capture.batches.last?.proposal.items.first?.kind, .other)
    }

    func testConfirmLedgerCandidatePersistenceFailureLeavesSnapshotUnchanged() throws {
        let memory = V2Engine()
        let source = try memory.saveCapture(text: "午饭 38 CNY", at: Date())
        let candidate = V2CaptureCandidate(
            candidateID: "write-failure",
            kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午饭", amount: "38", currency: "CNY", direction: .expense)
        )
        let batch = try memory.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture"
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine(
            snapshot: memory.snapshot,
            store: V2JSONSnapshotStore(fileURL: directory),
            reconcileExecutions: false
        )
        let before = engine.snapshot

        XCTAssertThrowsError(try engine.confirmLedgerCandidate(
            batchID: batch.id,
            candidateID: candidate.candidateID,
            sourceRevision: batch.proposal.sourceRevision,
            draft: .init(text: "午饭", amount: "35", currency: "CNY", direction: .expense)
        ))
        XCTAssertEqual(engine.snapshot, before)
    }

    func testManualLedgerWithoutDatePreservesNilDate() throws {
        let engine = V2Engine()
        let entry = try engine.createManualLedgerEntry(
            amount: "18",
            currency: "CNY",
            direction: .expense,
            text: "咖啡",
            localDate: nil
        )
        XCTAssertNil(entry.localDate)
        XCTAssertNil(engine.snapshot.capture.ledger.first?.localDate)
    }
}
