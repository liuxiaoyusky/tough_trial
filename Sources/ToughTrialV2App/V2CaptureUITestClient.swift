#if DEBUG
import Foundation
import ToughTrialV2Core

/// Explicit test launch flag only. Production always uses the configured AI client.
struct V2CaptureUITestClient: V2CaptureClient {
    func extract(_ entry: V2CaptureEntry, categories: [V2LedgerCategory]) async throws -> V2CaptureProposal {
        let evidence = [V2CaptureEvidence(blockID: entry.blocks[0].id, quote: entry.blocks[0].text ?? "")]
        let environment = ProcessInfo.processInfo.environment
        if environment["TOUGH_TRIAL_UI_TEST_LEDGER_FAIL_ONCE"] == "1" {
            if await V2CaptureUITestFailureOnce.shared.consume() { throw V2CaptureError.providerFailure }
            return .init(captureID: entry.id, sourceRevision: entry.revision, items: [
                .init(candidateID: "ledger-review", kind: .ledger, evidence: evidence,
                      payload: .init(text: "午饭", amount: "38", currency: "CNY", direction: .expense,
                                     categoryName: "餐饮", localDate: "2026-09-08"))
            ])
        }
        if environment["TOUGH_TRIAL_UI_TEST_LEDGER_MISSING"] == "1" {
            return .init(captureID: entry.id, sourceRevision: entry.revision, items: [
                .init(candidateID: "unresolved-bill", kind: .other, evidence: evidence,
                      payload: .init(text: entry.text))
            ])
        }
        if environment["TOUGH_TRIAL_UI_TEST_LEDGER"] == "1" {
            return .init(captureID: entry.id, sourceRevision: entry.revision, items: [
                .init(candidateID: "ledger-review", kind: .ledger, evidence: evidence,
                      payload: .init(text: "午饭", amount: "38", currency: "CNY", direction: .expense,
                                     categoryName: "餐饮", localDate: "2026-09-08"))
            ])
        }
        return .init(captureID: entry.id, sourceRevision: entry.revision, items: [
            .init(candidateID: "bill", kind: .ledger, evidence: evidence,
                  payload: .init(text: "午餐", amount: "38", currency: "CNY", direction: .expense, categoryName: "餐饮")),
            .init(candidateID: "reflection", kind: .recall, evidence: evidence,
                  payload: .init(text: "今天沟通很顺畅，下次先列出重点。", localDate: V2CaptureContract.localDate(entry.recordedAt, timeZone: .current))),
            .init(candidateID: "idea", kind: .inspiration, evidence: evidence, payload: .init(text: "拍一期早餐视频", title: "早餐视频")),
            .init(candidateID: "task", kind: .task, evidence: evidence,
                  payload: .init(text: "整理采访提纲", operations: [.init(kind: .createTask, localID: "outline", title: "整理采访提纲")]))
        ])
    }
}

private actor V2CaptureUITestFailureOnce {
    static let shared = V2CaptureUITestFailureOnce()
    private var consumed = false

    func consume() -> Bool {
        guard !consumed else { return false }
        consumed = true
        return true
    }
}
#endif
