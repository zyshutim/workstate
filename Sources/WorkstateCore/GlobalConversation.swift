import Foundation

public enum GlobalChatMessageRole: String, Codable, Equatable, Sendable {
    case user
    case owner
    case system
}

public struct GlobalChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var role: GlobalChatMessageRole
    public var text: String
    public var timestamp: Date
    public var projectID: String?
    public var projectName: String?
    public var topicID: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        role: GlobalChatMessageRole,
        text: String,
        timestamp: Date = Date(),
        projectID: String? = nil,
        projectName: String? = nil,
        topicID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.projectID = projectID
        self.projectName = projectName
        self.topicID = topicID
    }
}

public struct GlobalConversation: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var messages: [GlobalChatMessage]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        messages: [GlobalChatMessage] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

public struct GlobalConversationRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("global-conversation.json")
    }

    public func load() throws -> GlobalConversation {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GlobalConversation()
        }
        let conversation = try WorkstateCoding.makeDecoder().decode(
            GlobalConversation.self,
            from: Data(contentsOf: url)
        )
        guard conversation.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState(
                "Unsupported global conversation schema \(conversation.schemaVersion)"
            )
        }
        return conversation
    }

    public func save(_ conversation: GlobalConversation) throws {
        guard conversation.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState("Expected global conversation schema 1")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder()
            .encode(conversation)
            .write(to: url, options: .atomic)
    }
}
