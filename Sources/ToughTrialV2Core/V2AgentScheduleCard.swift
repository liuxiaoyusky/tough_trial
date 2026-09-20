import Foundation

/// The proposed values and their baseline survive app restarts while confirmation is pending.
public struct V2AgentScheduleCard: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, applied, cancelled }
    public var id: String { requestID }
    public var requestID: String
    public var proposal: V2ScheduleProposal
    public var baseline: V2AppSnapshot
    public var status: Status
    public var receiptID: String?

    public init(requestID: String, proposal: V2ScheduleProposal, baseline: V2AppSnapshot,
                status: Status = .pending, receiptID: String? = nil) {
        self.requestID = requestID
        self.proposal = proposal
        self.baseline = baseline
        self.status = status
        self.receiptID = receiptID
    }
}

/// One task presentation, regardless of how many create/schedule operations produced it.
public struct V2AssistantTaskPreview: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var note: String
    public var day: String?
    public var operationIndex: Int?
    public var taskID: String?
}

extension V2AgentScheduleCard {
    public func taskPreviews(receipt: V2ScheduleReceipt? = nil, timeZoneIdentifier: String = TimeZone.current.identifier) -> [V2AssistantTaskPreview] {
        if let receipt {
            return receipt.changes.compactMap { change in
                guard change.beforeTask == nil, let task = change.afterTask else { return nil }
                let plan = receipt.changes.compactMap(\.afterPlanItem).first { $0.taskID == task.id }
                return .init(id: task.id, title: task.title, note: task.note,
                    day: plan.map { V2CaptureContract.localDate($0.date, timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current) },
                    operationIndex: nil, taskID: task.id)
            }
        }
        return proposal.operations.enumerated().compactMap { index, operation in
            guard operation.kind == .createTask else { return nil }
            let plan = operation.localID.flatMap { id in proposal.operations.first { $0.kind == .scheduleTask && $0.targetID == id } }
            return .init(id: operation.localID ?? "operation-\(index)", title: operation.title ?? "任务", note: operation.note ?? "",
                day: plan?.day, operationIndex: index, taskID: nil)
        }
    }
}
