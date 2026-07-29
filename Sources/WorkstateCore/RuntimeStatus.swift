import Foundation

public enum RuntimeActivity: String, Codable, CaseIterable, Sendable {
    case stopped
    case idle
    case scanning
    case analyzing
    case failed
}

public struct RuntimeSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var activity: RuntimeActivity
    public var detail: String
    public var pendingEvidenceCount: Int
    public var unboundConversationCount: Int
    public var liveActivities: [LiveProjectActivity]

    public init(
        updatedAt: Date = Date(),
        activity: RuntimeActivity = .stopped,
        detail: String = "",
        pendingEvidenceCount: Int = 0,
        unboundConversationCount: Int = 0,
        liveActivities: [LiveProjectActivity] = []
    ) {
        self.updatedAt = updatedAt
        self.activity = activity
        self.detail = detail
        self.pendingEvidenceCount = pendingEvidenceCount
        self.unboundConversationCount = unboundConversationCount
        self.liveActivities = liveActivities
    }

    public func isFresh(now: Date = Date(), maximumAge: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(updatedAt) <= maximumAge
    }
}

public struct RuntimeStatusRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("runtime-status.json")
    }

    public func load() throws -> RuntimeSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RuntimeSnapshot()
        }
        return try WorkstateCoding.makeDecoder().decode(
            RuntimeSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    public func saveIfChanged(_ snapshot: RuntimeSnapshot) throws -> Bool {
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try load()
            if existing.activity == snapshot.activity,
               existing.detail == snapshot.detail,
               existing.pendingEvidenceCount == snapshot.pendingEvidenceCount,
               existing.unboundConversationCount == snapshot.unboundConversationCount,
               existing.liveActivities == snapshot.liveActivities {
                return false
            }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder().encode(snapshot).write(to: url, options: .atomic)
        return true
    }
}

public struct DaemonStatusRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("daemon-status.json")
    }

    public func load() throws -> DaemonSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DaemonSnapshot()
        }
        return try WorkstateCoding.makeDecoder().decode(
            DaemonSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    public func saveIfChanged(_ snapshot: DaemonSnapshot) throws -> Bool {
        if FileManager.default.fileExists(atPath: url.path),
           try load() == snapshot {
            return false
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder()
            .encode(snapshot)
            .write(to: url, options: .atomic)
        return true
    }
}
