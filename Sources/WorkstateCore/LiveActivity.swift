import Foundation

public struct LiveProjectActivity: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var projectID: String
    public var threadID: String
    public var turnID: String
    public var title: String
    public var updatedAt: Date

    public init(
        id: String,
        projectID: String,
        threadID: String,
        turnID: String,
        title: String,
        updatedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.threadID = threadID
        self.turnID = turnID
        self.title = title
        self.updatedAt = updatedAt
    }
}

public struct LiveActivitySnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var activities: [LiveProjectActivity]

    public init(updatedAt: Date = Date(), activities: [LiveProjectActivity] = []) {
        self.updatedAt = updatedAt
        self.activities = activities
    }
}

public struct LiveActivityRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("live-activities.json")
    }

    public func load() throws -> LiveActivitySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LiveActivitySnapshot()
        }
        return try WorkstateCoding.makeDecoder().decode(
            LiveActivitySnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    public func save(_ snapshot: LiveActivitySnapshot) throws -> Bool {
        if FileManager.default.fileExists(atPath: url.path),
           try load().activities == snapshot.activities {
            return false
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try WorkstateCoding.makeEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
        return true
    }
}
