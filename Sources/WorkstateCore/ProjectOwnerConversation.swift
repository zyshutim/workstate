import Foundation

public enum ProjectOwnerMessageRole: String, Codable, Equatable, Sendable {
    case user
    case owner
}

public struct ProjectOwnerMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var role: ProjectOwnerMessageRole
    public var text: String
    public var timestamp: Date
    public var topicID: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        role: ProjectOwnerMessageRole,
        text: String,
        timestamp: Date = Date(),
        topicID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.topicID = topicID
    }
}

public enum ProjectOwnerTurnStatus: String, Codable, Equatable, Sendable {
    case pending
    case applied
    case failed
}

public struct ProjectOwnerTurnRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var projectID: String
    public var topicID: String?
    public var userMessageID: String
    public var ownerMessageID: String?
    public var status: ProjectOwnerTurnStatus
    public var runtimeThreadID: String?
    public var error: String
    public var timestamp: Date

    public init(
        id: String,
        projectID: String,
        topicID: String? = nil,
        userMessageID: String,
        ownerMessageID: String? = nil,
        status: ProjectOwnerTurnStatus,
        runtimeThreadID: String? = nil,
        error: String = "",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.topicID = topicID
        self.userMessageID = userMessageID
        self.ownerMessageID = ownerMessageID
        self.status = status
        self.runtimeThreadID = runtimeThreadID
        self.error = error
        self.timestamp = timestamp
    }
}

public struct ProjectOwnerTurnRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("owner-turns.jsonl")
    }

    public func append(_ record: ProjectOwnerTurnRecord) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try rotateIfNeeded()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func rotateIfNeeded(maximumBytes: Int = 2 * 1024 * 1024) throws {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= maximumBytes else { return }
        let previous = url.deletingPathExtension().appendingPathExtension("previous.jsonl")
        if FileManager.default.fileExists(atPath: previous.path) {
            try FileManager.default.removeItem(at: previous)
        }
        try FileManager.default.moveItem(at: url, to: previous)
    }
}

public struct ProjectOwnerConversation: Codable, Equatable, Sendable {
    public var projectID: String
    public var messages: [ProjectOwnerMessage]
    public var updatedAt: Date

    public init(
        projectID: String,
        messages: [ProjectOwnerMessage] = [],
        updatedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

public struct ProjectOwnerConversationRepository: Sendable {
    public let root: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        self.root = root.appendingPathComponent("owner-conversations", isDirectory: true)
    }

    public func load(projectID: String) throws -> ProjectOwnerConversation {
        let url = try conversationURL(projectID: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectOwnerConversation(projectID: projectID)
        }
        return try WorkstateCoding.makeDecoder().decode(
            ProjectOwnerConversation.self,
            from: Data(contentsOf: url)
        )
    }

    public func save(_ conversation: ProjectOwnerConversation) throws {
        let url = try conversationURL(projectID: conversation.projectID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try WorkstateCoding.makeEncoder()
            .encode(conversation)
            .write(to: url, options: .atomic)
    }

    private func conversationURL(projectID: String) throws -> URL {
        guard !projectID.isEmpty,
              projectID != ".",
              projectID != "..",
              !projectID.contains("/"),
              !projectID.contains(":") else {
            throw WorkstateStorageError.invalidState("Invalid Project Owner conversation id: \(projectID)")
        }
        return root.appendingPathComponent("\(projectID).json")
    }
}
