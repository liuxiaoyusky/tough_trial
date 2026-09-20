import Foundation

public enum V2AssistantScheduleContext {
    public static func requestsToday(_ text: String) -> Bool {
        text.contains("今天") && !["未排期", "不排期", "不要排", "别排", "不安排", "不在今天", "不是今天"].contains(where: text.contains)
    }
    /// Explicit today capture uses the same plan records as manual Today input.
    /// This fills an omitted plan operation, never invents a clock time.
    public static func preservingToday(_ proposal: V2ScheduleProposal, userText: String, at date: Date,
                                       timeZoneIdentifier: String) -> V2ScheduleProposal {
        guard requestsToday(userText) else { return proposal }
        let day = V2CaptureContract.localDate(date, timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current)
        var result = proposal
        var localIDs = Set(proposal.operations.compactMap(\.localID))
        for index in proposal.operations.indices where proposal.operations[index].kind == .createTask {
            var id = result.operations[index].localID
            if id == nil {
                var suffix = index
                while localIDs.contains("host_today_\(suffix)") { suffix += 1 }
                id = "host_today_\(suffix)"; result.operations[index].localID = id; localIDs.insert(id!)
            }
            guard !result.operations.contains(where: { $0.kind == .scheduleTask && $0.targetID == id }) else { continue }
            result.operations.append(.init(kind: .scheduleTask, targetID: id, day: day))
        }
        return result
    }
}
