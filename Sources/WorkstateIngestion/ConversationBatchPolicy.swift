import Foundation

public enum ConversationBatchTrigger: String, Codable, CaseIterable, Sendable {
    case quietPeriod
    case manual
    case handoff
    case ownerContext
    case dailyBrief
    case safetySize
}

public struct PendingConversationActivity: Equatable, Sendable {
    public var pointerCount: Int
    public var oldestCompletedAt: Date?
    public var latestCompletedAt: Date?
    public var estimatedSourceBytes: UInt64

    public init(
        pointerCount: Int,
        oldestCompletedAt: Date?,
        latestCompletedAt: Date?,
        estimatedSourceBytes: UInt64
    ) {
        self.pointerCount = pointerCount
        self.oldestCompletedAt = oldestCompletedAt
        self.latestCompletedAt = latestCompletedAt
        self.estimatedSourceBytes = estimatedSourceBytes
    }
}

public struct ConversationBatchPolicy: Equatable, Sendable {
    public var quietInterval: TimeInterval
    public var maximumEstimatedSourceBytes: UInt64

    public init(
        quietInterval: TimeInterval = 30 * 60,
        maximumEstimatedSourceBytes: UInt64 = 256 * 1024
    ) {
        precondition(quietInterval > 0, "Batch quiet interval must be positive")
        precondition(
            maximumEstimatedSourceBytes > 0,
            "Batch source byte boundary must be positive"
        )
        self.quietInterval = quietInterval
        self.maximumEstimatedSourceBytes = maximumEstimatedSourceBytes
    }

    public func automaticTrigger(
        for activity: PendingConversationActivity,
        now: Date = Date()
    ) -> ConversationBatchTrigger? {
        guard activity.pointerCount > 0 else { return nil }
        guard let latestCompletedAt = activity.latestCompletedAt,
              now.timeIntervalSince(latestCompletedAt) >= quietInterval else {
            return nil
        }
        return .quietPeriod
    }
}

public struct ConversationBatchWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var trigger: ConversationBatchTrigger
    public var createdAt: Date
    public var highWaterTimestamp: Date
    public var pointerIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        trigger: ConversationBatchTrigger,
        createdAt: Date = Date(),
        highWaterTimestamp: Date,
        pointerIDs: [String]
    ) {
        precondition(!pointerIDs.isEmpty, "A conversation batch must contain source pointers")
        self.id = id
        self.trigger = trigger
        self.createdAt = createdAt
        self.highWaterTimestamp = highWaterTimestamp
        self.pointerIDs = pointerIDs
    }
}
