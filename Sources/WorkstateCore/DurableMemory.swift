import Foundation

public enum DurableMemoryNamespace: String, Codable, CaseIterable, Sendable {
    case profile
    case preferences
    case topic
    case area
    case person
    case collaborationRules
    case collaborationLoops
    case collaborationProhibitions
}

public enum DurableMemoryAuthority: String, Codable, CaseIterable, Sendable {
    case userStated
    case userConfirmed
    case runtimeObserved
    case agentInferred
    case agentProposed

    public var isExplicitUserAuthority: Bool {
        self == .userStated || self == .userConfirmed
    }
}

public enum DurableMemoryLifecycle: String, Codable, CaseIterable, Sendable {
    case active
    case candidate
    case superseded
    case prohibited
}

public enum DurableMemoryScopeKind: String, Codable, CaseIterable, Sendable {
    case global
    case project
    case thread
    case custom
}

public struct DurableMemoryScope: Codable, Equatable, Hashable, Sendable {
    public var kind: DurableMemoryScopeKind
    public var identifier: String

    public init(kind: DurableMemoryScopeKind, identifier: String = "") {
        self.kind = kind
        self.identifier = identifier
    }

    public static let global = DurableMemoryScope(kind: .global)
}

public struct DurableMemoryDocumentKey: Codable, Equatable, Hashable, Sendable {
    public var namespace: DurableMemoryNamespace
    public var scope: DurableMemoryScope
    public var slug: String

    public init(
        namespace: DurableMemoryNamespace,
        scope: DurableMemoryScope,
        slug: String
    ) {
        self.namespace = namespace
        self.scope = scope
        self.slug = slug
    }
}

public struct DurableMemoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var authority: DurableMemoryAuthority
    public var lifecycle: DurableMemoryLifecycle
    public var evidencePointerIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var supersedesID: String?

    public init(
        id: String,
        text: String,
        authority: DurableMemoryAuthority,
        lifecycle: DurableMemoryLifecycle,
        evidencePointerIDs: [String],
        createdAt: Date,
        updatedAt: Date,
        supersedesID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.authority = authority
        self.lifecycle = lifecycle
        self.evidencePointerIDs = evidencePointerIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.supersedesID = supersedesID
    }
}

public struct DurableMemoryDocument: Codable, Equatable, Sendable {
    public var namespace: DurableMemoryNamespace
    public var slug: String
    public var description: String
    public var aliases: [String]
    public var scope: DurableMemoryScope
    public var version: Int
    public var entries: [DurableMemoryEntry]

    public init(
        namespace: DurableMemoryNamespace,
        slug: String,
        description: String,
        aliases: [String] = [],
        scope: DurableMemoryScope,
        version: Int,
        entries: [DurableMemoryEntry] = []
    ) {
        self.namespace = namespace
        self.slug = slug
        self.description = description
        self.aliases = aliases
        self.scope = scope
        self.version = version
        self.entries = entries
    }

    public var key: DurableMemoryDocumentKey {
        DurableMemoryDocumentKey(namespace: namespace, scope: scope, slug: slug)
    }
}

public struct DurableMemoryLibrary: Codable, Equatable, Sendable {
    public var documents: [DurableMemoryDocument]

    public init(documents: [DurableMemoryDocument] = []) {
        self.documents = documents
    }
}

public struct DurableMemoryEntryDraft: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var authority: DurableMemoryAuthority
    public var lifecycle: DurableMemoryLifecycle
    public var evidencePointerIDs: [String]

    public init(
        id: String,
        text: String,
        authority: DurableMemoryAuthority,
        lifecycle: DurableMemoryLifecycle,
        evidencePointerIDs: [String] = []
    ) {
        self.id = id
        self.text = text
        self.authority = authority
        self.lifecycle = lifecycle
        self.evidencePointerIDs = evidencePointerIDs
    }
}

public struct DurableMemoryDocumentDraft: Codable, Equatable, Sendable {
    public var namespace: DurableMemoryNamespace
    public var slug: String
    public var description: String
    public var aliases: [String]
    public var scope: DurableMemoryScope
    public var entries: [DurableMemoryEntryDraft]

    public init(
        namespace: DurableMemoryNamespace,
        slug: String,
        description: String,
        aliases: [String] = [],
        scope: DurableMemoryScope,
        entries: [DurableMemoryEntryDraft] = []
    ) {
        self.namespace = namespace
        self.slug = slug
        self.description = description
        self.aliases = aliases
        self.scope = scope
        self.entries = entries
    }

    public var key: DurableMemoryDocumentKey {
        DurableMemoryDocumentKey(namespace: namespace, scope: scope, slug: slug)
    }
}

public struct DurableMemoryDocumentPatch: Codable, Equatable, Sendable {
    public var description: String?
    public var aliases: [String]?

    public init(description: String? = nil, aliases: [String]? = nil) {
        self.description = description
        self.aliases = aliases
    }

    public var isEmpty: Bool {
        description == nil && aliases == nil
    }
}

public struct DurableMemoryEntryPatch: Codable, Equatable, Sendable {
    public var text: String?
    public var authority: DurableMemoryAuthority?
    public var evidencePointerIDs: [String]?

    public init(
        text: String? = nil,
        authority: DurableMemoryAuthority? = nil,
        evidencePointerIDs: [String]? = nil
    ) {
        self.text = text
        self.authority = authority
        self.evidencePointerIDs = evidencePointerIDs
    }

    public var isEmpty: Bool {
        text == nil && authority == nil && evidencePointerIDs == nil
    }
}

public enum DurableMemoryMutationOperation: Codable, Equatable, Sendable {
    case createDocument(DurableMemoryDocumentDraft)
    case updateDocument(
        document: DurableMemoryDocumentKey,
        patch: DurableMemoryDocumentPatch
    )
    case createEntry(
        document: DurableMemoryDocumentKey,
        entry: DurableMemoryEntryDraft
    )
    case updateEntry(
        document: DurableMemoryDocumentKey,
        entryID: String,
        patch: DurableMemoryEntryPatch
    )
    case supersedeEntry(
        document: DurableMemoryDocumentKey,
        entryID: String,
        replacement: DurableMemoryEntryDraft
    )
    case prohibitEntry(document: DurableMemoryDocumentKey, entryID: String)
    case deleteEntry(document: DurableMemoryDocumentKey, entryID: String)
}

public struct DurableMemoryMutation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var expectedDocumentVersion: Int?
    public var authorizedBy: DurableMemoryAuthority
    public var timestamp: Date
    public var operation: DurableMemoryMutationOperation

    public init(
        id: String,
        expectedDocumentVersion: Int? = nil,
        authorizedBy: DurableMemoryAuthority,
        timestamp: Date,
        operation: DurableMemoryMutationOperation
    ) {
        self.id = id
        self.expectedDocumentVersion = expectedDocumentVersion
        self.authorizedBy = authorizedBy
        self.timestamp = timestamp
        self.operation = operation
    }
}

public struct DurableMemoryMutationReceipt: Codable, Equatable, Sendable {
    public var mutationID: String
    public var document: DurableMemoryDocumentKey
    public var previousVersion: Int?
    public var newVersion: Int
    public var affectedEntryIDs: [String]

    public init(
        mutationID: String,
        document: DurableMemoryDocumentKey,
        previousVersion: Int?,
        newVersion: Int,
        affectedEntryIDs: [String]
    ) {
        self.mutationID = mutationID
        self.document = document
        self.previousVersion = previousVersion
        self.newVersion = newVersion
        self.affectedEntryIDs = affectedEntryIDs
    }
}

public struct DurableMemoryApplication: Codable, Equatable, Sendable {
    public var library: DurableMemoryLibrary
    public var receipt: DurableMemoryMutationReceipt

    public init(
        library: DurableMemoryLibrary,
        receipt: DurableMemoryMutationReceipt
    ) {
        self.library = library
        self.receipt = receipt
    }
}

public struct DurableMemorySelection: Codable, Equatable, Sendable {
    public var scopes: [DurableMemoryScope]
    public var namespaces: [DurableMemoryNamespace]
    public var aliases: [String]
    public var includeCandidates: Bool
    public var includeSuperseded: Bool

    public init(
        scopes: [DurableMemoryScope] = [],
        namespaces: [DurableMemoryNamespace] = [],
        aliases: [String] = [],
        includeCandidates: Bool = false,
        includeSuperseded: Bool = false
    ) {
        self.scopes = scopes
        self.namespaces = namespaces
        self.aliases = aliases
        self.includeCandidates = includeCandidates
        self.includeSuperseded = includeSuperseded
    }
}

public enum DurableMemoryError: Error, Codable, Equatable, Sendable {
    case invalidLibrary(String)
    case invalidDocument(document: DurableMemoryDocumentKey, reason: String)
    case invalidEntry(entryID: String, reason: String)
    case invalidMutation(mutationID: String, reason: String)
    case invalidSelection(String)
    case documentAlreadyExists(DurableMemoryDocumentKey)
    case documentNotFound(DurableMemoryDocumentKey)
    case entryAlreadyExists(entryID: String, document: DurableMemoryDocumentKey)
    case entryNotFound(entryID: String, document: DurableMemoryDocumentKey)
    case versionConflict(
        document: DurableMemoryDocumentKey,
        expected: Int,
        actual: Int
    )
    case unauthorized(
        operation: String,
        required: String,
        actual: DurableMemoryAuthority
    )
    case invalidAuthorityTransition(
        entryID: String,
        from: DurableMemoryAuthority,
        to: DurableMemoryAuthority
    )
    case invalidLifecycleTransition(
        entryID: String,
        from: DurableMemoryLifecycle,
        to: DurableMemoryLifecycle
    )
    case referencedEntryCannotBeDeleted(entryID: String, referencedByID: String)
}

extension DurableMemoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidLibrary(reason):
            return "Invalid durable-memory library: \(reason)"
        case let .invalidDocument(document, reason):
            return "Invalid durable-memory document \(Self.label(document)): \(reason)"
        case let .invalidEntry(entryID, reason):
            return "Invalid durable-memory entry \(entryID): \(reason)"
        case let .invalidMutation(mutationID, reason):
            return "Invalid durable-memory mutation \(mutationID): \(reason)"
        case let .invalidSelection(reason):
            return "Invalid durable-memory selection: \(reason)"
        case let .documentAlreadyExists(document):
            return "Durable-memory document already exists: \(Self.label(document))"
        case let .documentNotFound(document):
            return "Durable-memory document was not found: \(Self.label(document))"
        case let .entryAlreadyExists(entryID, document):
            return "Durable-memory entry \(entryID) already exists in \(Self.label(document))"
        case let .entryNotFound(entryID, document):
            return "Durable-memory entry \(entryID) was not found in \(Self.label(document))"
        case let .versionConflict(document, expected, actual):
            return "Durable-memory version conflict for \(Self.label(document)): expected \(expected), actual \(actual)"
        case let .unauthorized(operation, required, actual):
            return "Unauthorized durable-memory operation \(operation): requires \(required), got \(actual.rawValue)"
        case let .invalidAuthorityTransition(entryID, from, to):
            return "Invalid authority transition for \(entryID): \(from.rawValue) -> \(to.rawValue)"
        case let .invalidLifecycleTransition(entryID, from, to):
            return "Invalid lifecycle transition for \(entryID): \(from.rawValue) -> \(to.rawValue)"
        case let .referencedEntryCannotBeDeleted(entryID, referencedByID):
            return "Durable-memory entry \(entryID) cannot be deleted because \(referencedByID) supersedes it"
        }
    }

    private static func label(_ key: DurableMemoryDocumentKey) -> String {
        let scope = key.scope.identifier.isEmpty
            ? key.scope.kind.rawValue
            : "\(key.scope.kind.rawValue):\(key.scope.identifier)"
        return "\(key.namespace.rawValue)/\(scope)/\(key.slug)"
    }
}

public struct DurableMemoryEngine: Codable, Equatable, Sendable {
    public init() {}

    public func applying(
        _ mutation: DurableMemoryMutation,
        to library: DurableMemoryLibrary
    ) throws -> DurableMemoryApplication {
        try validate(library)
        try validateMutationEnvelope(mutation)

        var updated = library
        let receipt: DurableMemoryMutationReceipt

        switch mutation.operation {
        case let .createDocument(draft):
            guard mutation.expectedDocumentVersion == nil else {
                throw DurableMemoryError.invalidMutation(
                    mutationID: mutation.id,
                    reason: "createDocument must not declare an expected document version"
                )
            }
            try validateDocumentDraft(draft)
            guard documentIndex(for: draft.key, in: updated) == nil else {
                throw DurableMemoryError.documentAlreadyExists(draft.key)
            }

            var seenEntryIDs = Set<String>()
            var entries: [DurableMemoryEntry] = []
            for entryDraft in draft.entries {
                try validateEntryDraft(
                    entryDraft,
                    authorizedBy: mutation.authorizedBy,
                    operation: "createDocument"
                )
                guard seenEntryIDs.insert(entryDraft.id).inserted else {
                    throw DurableMemoryError.entryAlreadyExists(
                        entryID: entryDraft.id,
                        document: draft.key
                    )
                }
                try ensureEntryIDIsUnique(entryDraft.id, in: updated)
                entries.append(makeEntry(from: entryDraft, at: mutation.timestamp))
            }

            let document = DurableMemoryDocument(
                namespace: draft.namespace,
                slug: trimmed(draft.slug),
                description: trimmed(draft.description),
                aliases: normalizedValues(draft.aliases),
                scope: normalizedScope(draft.scope),
                version: 1,
                entries: entries
            )
            updated.documents.append(document)
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: document.key,
                previousVersion: nil,
                newVersion: document.version,
                affectedEntryIDs: entries.map(\.id)
            )

        case let .updateDocument(documentKey, patch):
            let documentIndex = try checkedDocumentIndex(
                for: documentKey,
                expectedVersion: mutation.expectedDocumentVersion,
                mutationID: mutation.id,
                in: updated
            )
            guard !patch.isEmpty else {
                throw DurableMemoryError.invalidMutation(
                    mutationID: mutation.id,
                    reason: "updateDocument patch is empty"
                )
            }
            if let description = patch.description {
                guard !trimmed(description).isEmpty else {
                    throw DurableMemoryError.invalidDocument(
                        document: documentKey,
                        reason: "description must not be empty"
                    )
                }
                updated.documents[documentIndex].description = trimmed(description)
            }
            if let aliases = patch.aliases {
                try validateAliases(aliases, document: documentKey)
                updated.documents[documentIndex].aliases = normalizedValues(aliases)
            }
            let previousVersion = updated.documents[documentIndex].version
            updated.documents[documentIndex].version = try nextVersion(
                after: previousVersion,
                document: updated.documents[documentIndex].key
            )
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: updated.documents[documentIndex].key,
                previousVersion: previousVersion,
                newVersion: updated.documents[documentIndex].version,
                affectedEntryIDs: []
            )

        case let .createEntry(documentKey, entryDraft):
            let documentIndex = try checkedDocumentIndex(
                for: documentKey,
                expectedVersion: mutation.expectedDocumentVersion,
                mutationID: mutation.id,
                in: updated
            )
            try validateEntryDraft(
                entryDraft,
                authorizedBy: mutation.authorizedBy,
                operation: "createEntry"
            )
            try ensureEntryIDIsUnique(entryDraft.id, in: updated)

            let previousVersion = updated.documents[documentIndex].version
            updated.documents[documentIndex].entries.append(
                makeEntry(from: entryDraft, at: mutation.timestamp)
            )
            updated.documents[documentIndex].version = try nextVersion(
                after: previousVersion,
                document: updated.documents[documentIndex].key
            )
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: updated.documents[documentIndex].key,
                previousVersion: previousVersion,
                newVersion: updated.documents[documentIndex].version,
                affectedEntryIDs: [entryDraft.id]
            )

        case let .updateEntry(documentKey, entryID, patch):
            let documentIndex = try checkedDocumentIndex(
                for: documentKey,
                expectedVersion: mutation.expectedDocumentVersion,
                mutationID: mutation.id,
                in: updated
            )
            guard !patch.isEmpty else {
                throw DurableMemoryError.invalidMutation(
                    mutationID: mutation.id,
                    reason: "updateEntry patch is empty"
                )
            }
            let entryIndex = try checkedEntryIndex(
                entryID,
                documentIndex: documentIndex,
                in: updated
            )
            let existing = updated.documents[documentIndex].entries[entryIndex]
            guard existing.lifecycle != .superseded else {
                throw DurableMemoryError.invalidLifecycleTransition(
                    entryID: entryID,
                    from: .superseded,
                    to: .superseded
                )
            }
            try requireMutationAuthority(
                mutation.authorizedBy,
                toModify: existing,
                operation: "updateEntry"
            )
            try validateTimestamp(mutation.timestamp, for: existing)

            if let text = patch.text {
                guard !trimmed(text).isEmpty else {
                    throw DurableMemoryError.invalidEntry(
                        entryID: entryID,
                        reason: "text must not be empty"
                    )
                }
                updated.documents[documentIndex].entries[entryIndex].text = trimmed(text)
            }
            if let authority = patch.authority {
                try validateAuthorityTransition(
                    entryID: entryID,
                    from: existing.authority,
                    to: authority,
                    authorizedBy: mutation.authorizedBy
                )
                updated.documents[documentIndex].entries[entryIndex].authority = authority
            }
            if let evidencePointerIDs = patch.evidencePointerIDs {
                try validateEvidencePointerIDs(evidencePointerIDs, entryID: entryID)
                updated.documents[documentIndex].entries[entryIndex].evidencePointerIDs = normalizedValues(
                    evidencePointerIDs
                )
            }
            let previousVersion = updated.documents[documentIndex].version
            updated.documents[documentIndex].entries[entryIndex].updatedAt = mutation.timestamp
            updated.documents[documentIndex].version = try nextVersion(
                after: previousVersion,
                document: updated.documents[documentIndex].key
            )
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: updated.documents[documentIndex].key,
                previousVersion: previousVersion,
                newVersion: updated.documents[documentIndex].version,
                affectedEntryIDs: [entryID]
            )

        case let .supersedeEntry(documentKey, entryID, replacement):
            let documentIndex = try checkedDocumentIndex(
                for: documentKey,
                expectedVersion: mutation.expectedDocumentVersion,
                mutationID: mutation.id,
                in: updated
            )
            let entryIndex = try checkedEntryIndex(
                entryID,
                documentIndex: documentIndex,
                in: updated
            )
            let existing = updated.documents[documentIndex].entries[entryIndex]
            guard existing.lifecycle != .superseded else {
                throw DurableMemoryError.invalidLifecycleTransition(
                    entryID: entryID,
                    from: .superseded,
                    to: .superseded
                )
            }
            try requireMutationAuthority(
                mutation.authorizedBy,
                toModify: existing,
                operation: "supersedeEntry"
            )
            try validateTimestamp(mutation.timestamp, for: existing)
            try validateEntryDraft(
                replacement,
                authorizedBy: mutation.authorizedBy,
                operation: "supersedeEntry"
            )
            guard replacement.id != entryID else {
                throw DurableMemoryError.invalidMutation(
                    mutationID: mutation.id,
                    reason: "a superseding entry must have a new id"
                )
            }
            try ensureEntryIDIsUnique(replacement.id, in: updated)

            let previousVersion = updated.documents[documentIndex].version
            updated.documents[documentIndex].entries[entryIndex].lifecycle = .superseded
            updated.documents[documentIndex].entries[entryIndex].updatedAt = mutation.timestamp
            var replacementEntry = makeEntry(from: replacement, at: mutation.timestamp)
            replacementEntry.supersedesID = entryID
            updated.documents[documentIndex].entries.append(replacementEntry)
            updated.documents[documentIndex].version = try nextVersion(
                after: previousVersion,
                document: updated.documents[documentIndex].key
            )
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: updated.documents[documentIndex].key,
                previousVersion: previousVersion,
                newVersion: updated.documents[documentIndex].version,
                affectedEntryIDs: [entryID, replacement.id]
            )

        case let .prohibitEntry(documentKey, entryID):
            let documentIndex = try checkedDocumentIndex(
                for: documentKey,
                expectedVersion: mutation.expectedDocumentVersion,
                mutationID: mutation.id,
                in: updated
            )
            guard mutation.authorizedBy.isExplicitUserAuthority else {
                throw DurableMemoryError.unauthorized(
                    operation: "prohibitEntry",
                    required: "explicit user authority",
                    actual: mutation.authorizedBy
                )
            }
            let entryIndex = try checkedEntryIndex(
                entryID,
                documentIndex: documentIndex,
                in: updated
            )
            let existing = updated.documents[documentIndex].entries[entryIndex]
            guard existing.lifecycle == .active || existing.lifecycle == .candidate else {
                throw DurableMemoryError.invalidLifecycleTransition(
                    entryID: entryID,
                    from: existing.lifecycle,
                    to: .prohibited
                )
            }
            try validateTimestamp(mutation.timestamp, for: existing)

            let previousVersion = updated.documents[documentIndex].version
            updated.documents[documentIndex].entries[entryIndex].lifecycle = .prohibited
            updated.documents[documentIndex].entries[entryIndex].updatedAt = mutation.timestamp
            updated.documents[documentIndex].version = try nextVersion(
                after: previousVersion,
                document: updated.documents[documentIndex].key
            )
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: updated.documents[documentIndex].key,
                previousVersion: previousVersion,
                newVersion: updated.documents[documentIndex].version,
                affectedEntryIDs: [entryID]
            )

        case let .deleteEntry(documentKey, entryID):
            let documentIndex = try checkedDocumentIndex(
                for: documentKey,
                expectedVersion: mutation.expectedDocumentVersion,
                mutationID: mutation.id,
                in: updated
            )
            guard mutation.authorizedBy.isExplicitUserAuthority else {
                throw DurableMemoryError.unauthorized(
                    operation: "deleteEntry",
                    required: "explicit user authority",
                    actual: mutation.authorizedBy
                )
            }
            let entryIndex = try checkedEntryIndex(
                entryID,
                documentIndex: documentIndex,
                in: updated
            )
            if let referencingEntry = updated.documents[documentIndex].entries.first(where: {
                $0.supersedesID == entryID
            }) {
                throw DurableMemoryError.referencedEntryCannotBeDeleted(
                    entryID: entryID,
                    referencedByID: referencingEntry.id
                )
            }

            let previousVersion = updated.documents[documentIndex].version
            updated.documents[documentIndex].entries.remove(at: entryIndex)
            updated.documents[documentIndex].version = try nextVersion(
                after: previousVersion,
                document: updated.documents[documentIndex].key
            )
            receipt = DurableMemoryMutationReceipt(
                mutationID: mutation.id,
                document: updated.documents[documentIndex].key,
                previousVersion: previousVersion,
                newVersion: updated.documents[documentIndex].version,
                affectedEntryIDs: [entryID]
            )
        }

        try validate(updated)
        return DurableMemoryApplication(library: updated, receipt: receipt)
    }

    public func retrieve(
        from library: DurableMemoryLibrary,
        matching selection: DurableMemorySelection = .init()
    ) throws -> [DurableMemoryDocument] {
        try validate(library)
        try validateSelection(selection)

        return library.documents.compactMap { document in
            let explicitlySelected = matchesSelection(document, selection: selection)
            let selectedEntries = document.entries.filter { entry in
                isGlobalDefault(entry, in: document)
                    || explicitlySelected && isVisible(entry, selection: selection)
            }
            guard !selectedEntries.isEmpty else { return nil }

            var selectedDocument = document
            selectedDocument.entries = selectedEntries.sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            return selectedDocument
        }
        .sorted { lhs, rhs in
            if lhs.namespace == rhs.namespace {
                return canonical(lhs.slug) < canonical(rhs.slug)
            }
            return lhs.namespace.rawValue < rhs.namespace.rawValue
        }
    }

    public func validate(_ library: DurableMemoryLibrary) throws {
        var documentIdentities = Set<String>()
        var entryLocations: [String: DurableMemoryDocumentKey] = [:]

        for document in library.documents {
            try validateDocument(document)
            let identity = canonicalIdentity(document.key)
            guard documentIdentities.insert(identity).inserted else {
                throw DurableMemoryError.documentAlreadyExists(document.key)
            }

            for entry in document.entries {
                if let existingDocument = entryLocations[entry.id] {
                    throw DurableMemoryError.entryAlreadyExists(
                        entryID: entry.id,
                        document: existingDocument
                    )
                }
                entryLocations[entry.id] = document.key
            }
        }
    }

    private func validateMutationEnvelope(_ mutation: DurableMemoryMutation) throws {
        guard !trimmed(mutation.id).isEmpty else {
            throw DurableMemoryError.invalidMutation(
                mutationID: mutation.id,
                reason: "id must not be empty"
            )
        }
    }

    private func validateDocument(_ document: DurableMemoryDocument) throws {
        try validateDocumentIdentity(
            key: document.key,
            description: document.description,
            aliases: document.aliases
        )
        guard document.version > 0 else {
            throw DurableMemoryError.invalidDocument(
                document: document.key,
                reason: "version must be greater than zero"
            )
        }

        var entryIDs = Set<String>()
        for entry in document.entries {
            try validateStoredEntry(entry)
            guard entryIDs.insert(entry.id).inserted else {
                throw DurableMemoryError.entryAlreadyExists(
                    entryID: entry.id,
                    document: document.key
                )
            }
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: document.entries.map { ($0.id, $0) })
        var supersededTargets = Set<String>()
        for entry in document.entries {
            if let supersedesID = entry.supersedesID {
                guard let supersededEntry = entriesByID[supersedesID] else {
                    throw DurableMemoryError.invalidEntry(
                        entryID: entry.id,
                        reason: "supersedes unknown entry \(supersedesID)"
                    )
                }
                guard supersededEntry.lifecycle == .superseded else {
                    throw DurableMemoryError.invalidEntry(
                        entryID: entry.id,
                        reason: "superseded target \(supersedesID) is not marked superseded"
                    )
                }
                guard supersededTargets.insert(supersedesID).inserted else {
                    throw DurableMemoryError.invalidEntry(
                        entryID: entry.id,
                        reason: "entry \(supersedesID) has more than one successor"
                    )
                }
            }
        }
        try validateSupersessionChains(entriesByID)
    }

    private func validateDocumentDraft(_ draft: DurableMemoryDocumentDraft) throws {
        try validateDocumentIdentity(
            key: draft.key,
            description: draft.description,
            aliases: draft.aliases
        )
    }

    private func validateDocumentIdentity(
        key: DurableMemoryDocumentKey,
        description: String,
        aliases: [String]
    ) throws {
        guard !trimmed(key.slug).isEmpty else {
            throw DurableMemoryError.invalidDocument(
                document: key,
                reason: "slug must not be empty"
            )
        }
        guard !trimmed(description).isEmpty else {
            throw DurableMemoryError.invalidDocument(
                document: key,
                reason: "description must not be empty"
            )
        }
        try validateScope(key.scope, document: key)
        try validateAliases(aliases, document: key)
    }

    private func validateScope(
        _ scope: DurableMemoryScope,
        document: DurableMemoryDocumentKey
    ) throws {
        let identifier = trimmed(scope.identifier)
        if scope.kind == .global, !identifier.isEmpty {
            throw DurableMemoryError.invalidDocument(
                document: document,
                reason: "global scope must not have an identifier"
            )
        }
        if scope.kind != .global, identifier.isEmpty {
            throw DurableMemoryError.invalidDocument(
                document: document,
                reason: "\(scope.kind.rawValue) scope requires an identifier"
            )
        }
    }

    private func validateAliases(
        _ aliases: [String],
        document: DurableMemoryDocumentKey
    ) throws {
        var seen = Set<String>()
        for alias in aliases {
            let normalized = canonical(alias)
            guard !normalized.isEmpty else {
                throw DurableMemoryError.invalidDocument(
                    document: document,
                    reason: "aliases must not contain empty values"
                )
            }
            guard seen.insert(normalized).inserted else {
                throw DurableMemoryError.invalidDocument(
                    document: document,
                    reason: "aliases must be unique"
                )
            }
        }
    }

    private func validateStoredEntry(_ entry: DurableMemoryEntry) throws {
        guard !trimmed(entry.id).isEmpty else {
            throw DurableMemoryError.invalidEntry(entryID: entry.id, reason: "id must not be empty")
        }
        guard !trimmed(entry.text).isEmpty else {
            throw DurableMemoryError.invalidEntry(entryID: entry.id, reason: "text must not be empty")
        }
        guard entry.updatedAt >= entry.createdAt else {
            throw DurableMemoryError.invalidEntry(
                entryID: entry.id,
                reason: "updatedAt must not be earlier than createdAt"
            )
        }
        if entry.supersedesID == entry.id {
            throw DurableMemoryError.invalidEntry(
                entryID: entry.id,
                reason: "an entry cannot supersede itself"
            )
        }
        try validateEvidencePointerIDs(entry.evidencePointerIDs, entryID: entry.id)
    }

    private func validateEntryDraft(
        _ draft: DurableMemoryEntryDraft,
        authorizedBy: DurableMemoryAuthority,
        operation: String
    ) throws {
        guard !trimmed(draft.id).isEmpty else {
            throw DurableMemoryError.invalidEntry(entryID: draft.id, reason: "id must not be empty")
        }
        guard !trimmed(draft.text).isEmpty else {
            throw DurableMemoryError.invalidEntry(entryID: draft.id, reason: "text must not be empty")
        }
        guard draft.lifecycle != .superseded else {
            throw DurableMemoryError.invalidEntry(
                entryID: draft.id,
                reason: "superseded entries must be produced by supersedeEntry"
            )
        }
        if draft.authority == .userConfirmed, authorizedBy != .userConfirmed {
            throw DurableMemoryError.unauthorized(
                operation: operation,
                required: "userConfirmed authority",
                actual: authorizedBy
            )
        }
        if draft.lifecycle == .prohibited, !authorizedBy.isExplicitUserAuthority {
            throw DurableMemoryError.unauthorized(
                operation: operation,
                required: "explicit user authority for prohibited memory",
                actual: authorizedBy
            )
        }
        try validateEvidencePointerIDs(draft.evidencePointerIDs, entryID: draft.id)
    }

    private func validateEvidencePointerIDs(_ ids: [String], entryID: String) throws {
        var seen = Set<String>()
        for id in ids {
            let normalized = trimmed(id)
            guard !normalized.isEmpty else {
                throw DurableMemoryError.invalidEntry(
                    entryID: entryID,
                    reason: "evidence pointer ids must not contain empty values"
                )
            }
            guard seen.insert(normalized).inserted else {
                throw DurableMemoryError.invalidEntry(
                    entryID: entryID,
                    reason: "evidence pointer ids must be unique"
                )
            }
        }
    }

    private func validateAuthorityTransition(
        entryID: String,
        from: DurableMemoryAuthority,
        to: DurableMemoryAuthority,
        authorizedBy: DurableMemoryAuthority
    ) throws {
        if from == to { return }
        if from == .agentInferred || from == .agentProposed, to == .userConfirmed {
            throw DurableMemoryError.invalidAuthorityTransition(
                entryID: entryID,
                from: from,
                to: to
            )
        }
        guard from == .userStated, to == .userConfirmed, authorizedBy == .userConfirmed else {
            throw DurableMemoryError.invalidAuthorityTransition(
                entryID: entryID,
                from: from,
                to: to
            )
        }
    }

    private func requireMutationAuthority(
        _ authorizedBy: DurableMemoryAuthority,
        toModify entry: DurableMemoryEntry,
        operation: String
    ) throws {
        if entry.authority == .userConfirmed, authorizedBy != .userConfirmed {
            throw DurableMemoryError.unauthorized(
                operation: operation,
                required: "userConfirmed authority",
                actual: authorizedBy
            )
        }
        if entry.authority == .userStated, !authorizedBy.isExplicitUserAuthority {
            throw DurableMemoryError.unauthorized(
                operation: operation,
                required: "explicit user authority",
                actual: authorizedBy
            )
        }
        if entry.lifecycle == .prohibited, !authorizedBy.isExplicitUserAuthority {
            throw DurableMemoryError.unauthorized(
                operation: operation,
                required: "explicit user authority for prohibited memory",
                actual: authorizedBy
            )
        }
    }

    private func validateTimestamp(_ timestamp: Date, for entry: DurableMemoryEntry) throws {
        guard timestamp >= entry.updatedAt else {
            throw DurableMemoryError.invalidEntry(
                entryID: entry.id,
                reason: "mutation timestamp must not be earlier than updatedAt"
            )
        }
    }

    private func validateSupersessionChains(
        _ entriesByID: [String: DurableMemoryEntry]
    ) throws {
        for entry in entriesByID.values {
            var visited = Set([entry.id])
            var current = entry
            while let supersedesID = current.supersedesID {
                guard visited.insert(supersedesID).inserted else {
                    throw DurableMemoryError.invalidEntry(
                        entryID: entry.id,
                        reason: "supersession chain contains a cycle at \(supersedesID)"
                    )
                }
                guard let previous = entriesByID[supersedesID] else { break }
                current = previous
            }
        }
    }

    private func nextVersion(
        after version: Int,
        document: DurableMemoryDocumentKey
    ) throws -> Int {
        guard version < Int.max else {
            throw DurableMemoryError.invalidDocument(
                document: document,
                reason: "version cannot be incremented beyond Int.max"
            )
        }
        return version + 1
    }

    private func checkedDocumentIndex(
        for key: DurableMemoryDocumentKey,
        expectedVersion: Int?,
        mutationID: String,
        in library: DurableMemoryLibrary
    ) throws -> Int {
        guard let expectedVersion, expectedVersion > 0 else {
            throw DurableMemoryError.invalidMutation(
                mutationID: mutationID,
                reason: "this operation requires a positive expected document version"
            )
        }
        guard let index = documentIndex(for: key, in: library) else {
            throw DurableMemoryError.documentNotFound(key)
        }
        let actualVersion = library.documents[index].version
        guard actualVersion == expectedVersion else {
            throw DurableMemoryError.versionConflict(
                document: key,
                expected: expectedVersion,
                actual: actualVersion
            )
        }
        return index
    }

    private func checkedEntryIndex(
        _ entryID: String,
        documentIndex: Int,
        in library: DurableMemoryLibrary
    ) throws -> Int {
        let document = library.documents[documentIndex]
        guard let index = document.entries.firstIndex(where: { $0.id == entryID }) else {
            throw DurableMemoryError.entryNotFound(entryID: entryID, document: document.key)
        }
        return index
    }

    private func ensureEntryIDIsUnique(
        _ entryID: String,
        in library: DurableMemoryLibrary
    ) throws {
        for document in library.documents where document.entries.contains(where: { $0.id == entryID }) {
            throw DurableMemoryError.entryAlreadyExists(
                entryID: entryID,
                document: document.key
            )
        }
    }

    private func documentIndex(
        for key: DurableMemoryDocumentKey,
        in library: DurableMemoryLibrary
    ) -> Int? {
        let identity = canonicalIdentity(key)
        return library.documents.firstIndex { canonicalIdentity($0.key) == identity }
    }

    private func makeEntry(
        from draft: DurableMemoryEntryDraft,
        at timestamp: Date
    ) -> DurableMemoryEntry {
        DurableMemoryEntry(
            id: trimmed(draft.id),
            text: trimmed(draft.text),
            authority: draft.authority,
            lifecycle: draft.lifecycle,
            evidencePointerIDs: normalizedValues(draft.evidencePointerIDs),
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func matchesSelection(
        _ document: DurableMemoryDocument,
        selection: DurableMemorySelection
    ) -> Bool {
        let hasSelector = !selection.scopes.isEmpty
            || !selection.namespaces.isEmpty
            || !selection.aliases.isEmpty
        guard hasSelector else { return false }

        let scopeMatches = selection.scopes.isEmpty
            || selection.scopes.contains(document.scope)
        let namespaceMatches = selection.namespaces.isEmpty
            || selection.namespaces.contains(document.namespace)
        let documentAliases = Set(([document.slug] + document.aliases).map(canonical))
        let aliasMatches = selection.aliases.isEmpty
            || selection.aliases.map(canonical).contains(where: documentAliases.contains)
        return scopeMatches && namespaceMatches && aliasMatches
    }

    private func isGlobalDefault(
        _ entry: DurableMemoryEntry,
        in document: DurableMemoryDocument
    ) -> Bool {
        guard entry.lifecycle == .active || entry.lifecycle == .prohibited else {
            return false
        }
        if document.namespace == .preferences {
            return entry.authority.isExplicitUserAuthority
        }
        if document.namespace == .collaborationRules
            || document.namespace == .collaborationLoops
            || document.namespace == .collaborationProhibitions {
            return entry.authority == .userConfirmed
        }
        return false
    }

    private func isVisible(
        _ entry: DurableMemoryEntry,
        selection: DurableMemorySelection
    ) -> Bool {
        switch entry.lifecycle {
        case .active, .prohibited:
            return true
        case .candidate:
            return selection.includeCandidates
        case .superseded:
            return selection.includeSuperseded
        }
    }

    private func validateSelection(_ selection: DurableMemorySelection) throws {
        for scope in selection.scopes {
            let key = DurableMemoryDocumentKey(
                namespace: .profile,
                scope: scope,
                slug: "selection"
            )
            try validateScope(scope, document: key)
        }
        for alias in selection.aliases where canonical(alias).isEmpty {
            throw DurableMemoryError.invalidSelection("aliases must not contain empty values")
        }
    }

    private func normalizedScope(_ scope: DurableMemoryScope) -> DurableMemoryScope {
        DurableMemoryScope(kind: scope.kind, identifier: trimmed(scope.identifier))
    }

    private func normalizedValues(_ values: [String]) -> [String] {
        values.map(trimmed)
    }

    private func canonicalIdentity(_ key: DurableMemoryDocumentKey) -> String {
        [
            key.namespace.rawValue,
            key.scope.kind.rawValue,
            canonical(key.scope.identifier),
            canonical(key.slug)
        ].joined(separator: "|")
    }

    private func canonical(_ value: String) -> String {
        trimmed(value).lowercased()
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
