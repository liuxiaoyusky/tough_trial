#if os(iOS)
import ActivityKit
import Foundation

public struct V2FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var isRunning: Bool
        public var segmentStartedAt: Date?
        public var accumulatedSeconds: Int

        public init(
            title: String,
            isRunning: Bool,
            segmentStartedAt: Date?,
            accumulatedSeconds: Int
        ) {
            self.title = title
            self.isRunning = isRunning
            self.segmentStartedAt = segmentStartedAt
            self.accumulatedSeconds = accumulatedSeconds
        }
    }

    public var sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}
#endif
