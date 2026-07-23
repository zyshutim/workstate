import Foundation

public enum CollaborationEntryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case userPersona
    case collaboratorPersona
    case preference
    case rule
    case loop
    case prohibition

    public var id: String { rawValue }
}

public enum CollaborationEntryStatus: String, Codable, CaseIterable, Sendable {
    case active
    case candidate
    case superseded
}

public struct CollaborationProfileEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: CollaborationEntryKind
    public var status: CollaborationEntryStatus
    public var title: String
    public var detail: String
    public var scope: String
    public var evidence: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var supersedesID: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        kind: CollaborationEntryKind,
        status: CollaborationEntryStatus,
        title: String,
        detail: String,
        scope: String = "global",
        evidence: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        supersedesID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.scope = scope
        self.evidence = evidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.supersedesID = supersedesID
    }
}

public struct CollaborationProfileRevision: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Date
    public var summary: String
    public var entryIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        timestamp: Date = Date(),
        summary: String,
        entryIDs: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.summary = summary
        self.entryIDs = entryIDs
    }
}

public struct CollaborationProfile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var entries: [CollaborationProfileEntry]
    public var revisions: [CollaborationProfileRevision]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        entries: [CollaborationProfileEntry] = [],
        revisions: [CollaborationProfileRevision] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.revisions = revisions
        self.updatedAt = updatedAt
    }

    public var activeGuidance: [String] {
        entries
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { "\($0.title)：\($0.detail)" }
    }
}

public struct CollaborationProfileRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("collaboration-profile.json")
    }

    public func load() throws -> CollaborationProfile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CollaborationProfile()
        }
        let profile = try WorkstateCoding.makeDecoder().decode(
            CollaborationProfile.self,
            from: Data(contentsOf: url)
        )
        guard profile.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState(
                "Unsupported collaboration profile schema \(profile.schemaVersion)"
            )
        }
        return profile
    }

    public func save(_ profile: CollaborationProfile) throws {
        guard profile.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState("Expected collaboration profile schema 1")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder().encode(profile).write(to: url, options: .atomic)
    }
}

public struct CollaborationProfileMutation: Codable, Equatable, Sendable {
    public var action: String
    public var authority: String
    public var id: String
    public var kind: String
    public var status: String
    public var title: String
    public var detail: String
    public var scope: String
    public var evidence: [String]
    public var supersedesId: String

    public init(
        action: String,
        authority: String,
        id: String,
        kind: String,
        status: String,
        title: String,
        detail: String,
        scope: String = "global",
        evidence: [String] = [],
        supersedesId: String = ""
    ) {
        self.action = action
        self.authority = authority
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.scope = scope
        self.evidence = evidence
        self.supersedesId = supersedesId
    }
}

public struct CollaborationProfileApplier: Sendable {
    public init() {}

    public func apply(
        _ mutations: [CollaborationProfileMutation],
        to profile: CollaborationProfile,
        now: Date = Date()
    ) throws -> CollaborationProfile {
        var updated = profile
        var changedIDs: [String] = []
        for mutation in mutations {
            guard let kind = CollaborationEntryKind(rawValue: mutation.kind),
                  let status = CollaborationEntryStatus(rawValue: mutation.status),
                  mutation.authority == "explicit_user" || mutation.authority == "inference",
                  mutation.action == "create"
                    || mutation.action == "update"
                    || mutation.action == "supersede" else {
                throw WorkstateStorageError.invalidState(
                    "Collaboration Steward returned an unsupported mutation"
                )
            }
            if mutation.authority == "inference",
               mutation.action != "create" || status != .candidate {
                throw WorkstateStorageError.invalidState(
                    "Inferred collaboration changes may only create candidate entries"
                )
            }
            let existingIndex = updated.entries.firstIndex { $0.id == mutation.id }
            if mutation.action == "create" {
                guard existingIndex == nil else {
                    throw WorkstateStorageError.invalidState(
                        "Collaboration Steward tried to recreate \(mutation.id)"
                    )
                }
                updated.entries.append(
                    CollaborationProfileEntry(
                        id: mutation.id,
                        kind: kind,
                        status: status,
                        title: mutation.title,
                        detail: mutation.detail,
                        scope: mutation.scope,
                        evidence: mutation.evidence,
                        createdAt: now,
                        updatedAt: now,
                        supersedesID: mutation.supersedesId.isEmpty ? nil : mutation.supersedesId
                    )
                )
            } else {
                guard let existingIndex else {
                    throw WorkstateStorageError.invalidState(
                        "Collaboration Steward referenced unknown entry \(mutation.id)"
                    )
                }
                updated.entries[existingIndex].kind = kind
                updated.entries[existingIndex].status = mutation.action == "supersede"
                    ? .superseded
                    : status
                updated.entries[existingIndex].title = mutation.title
                updated.entries[existingIndex].detail = mutation.detail
                updated.entries[existingIndex].scope = mutation.scope
                updated.entries[existingIndex].evidence = mutation.evidence
                updated.entries[existingIndex].updatedAt = now
                updated.entries[existingIndex].supersedesID = mutation.supersedesId.isEmpty
                    ? nil
                    : mutation.supersedesId
            }
            changedIDs.append(mutation.id)
        }
        if !changedIDs.isEmpty {
            updated.updatedAt = now
            updated.revisions.append(
                CollaborationProfileRevision(
                    timestamp: now,
                    summary: "协作档案更新",
                    entryIDs: changedIDs
                )
            )
        }
        return updated
    }
}

public struct CollaborationMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var role: ProjectOwnerMessageRole
    public var text: String
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        role: ProjectOwnerMessageRole,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct CollaborationConversation: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var messages: [CollaborationMessage]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        messages: [CollaborationMessage] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

public struct CollaborationConversationRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("collaboration-conversation.json")
    }

    public func load() throws -> CollaborationConversation {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CollaborationConversation()
        }
        return try WorkstateCoding.makeDecoder().decode(
            CollaborationConversation.self,
            from: Data(contentsOf: url)
        )
    }

    public func save(_ conversation: CollaborationConversation) throws {
        guard conversation.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState("Expected collaboration conversation schema 1")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder().encode(conversation).write(to: url, options: .atomic)
    }
}
