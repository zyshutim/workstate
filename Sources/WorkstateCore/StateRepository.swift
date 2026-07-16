import Darwin
import Foundation

public enum WorkstateStorageError: LocalizedError {
    case cannotCreateLock(String)
    case cannotLock(String)
    case missingProject(String)
    case missingTask(String)
    case missingEvent(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateLock(let path):
            return "Cannot create Workstate lock at \(path)"
        case .cannotLock(let path):
            return "Cannot lock Workstate state at \(path)"
        case .missingProject(let id):
            return "Project not found: \(id)"
        case .missingTask(let id):
            return "Task not found: \(id)"
        case .missingEvent(let id):
            return "Event not found: \(id)"
        case .invalidState(let message):
            return "Invalid Workstate state: \(message)"
        }
    }
}

public struct WorkstatePaths: Sendable {
    public let root: URL
    public let state: URL
    public let events: URL
    public let lock: URL

    public init(root: URL) {
        self.root = root
        self.state = root.appendingPathComponent("state.json")
        self.events = root.appendingPathComponent("events.jsonl")
        self.lock = root.appendingPathComponent("state.lock")
    }

    public static func defaultPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> WorkstatePaths {
        if let override = environment["WORKSTATE_HOME"], !override.isEmpty {
            return WorkstatePaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        return WorkstatePaths(
            root: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/workstate", isDirectory: true)
        )
    }
}

public struct WorkstateRepository: Sendable {
    public let paths: WorkstatePaths

    public init(paths: WorkstatePaths = .defaultPaths()) {
        self.paths = paths
    }

    public func ensureInitialized(initial: WorkspaceSnapshot? = nil) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: paths.state.path) else {
            _ = try withLock(exclusive: true) {
                guard !FileManager.default.fileExists(atPath: paths.state.path) else { return }
                let snapshot = initial ?? WorkstateBootstrap.makeInitialState()
                try validate(snapshot)
                try writeUnlocked(snapshot)
                try appendMutationUnlocked(
                    WorkspaceMutation(kind: "workspace.bootstrap", summary: "Initialized Workstate schema v2")
                )
            }
            return
        }

        let version = try schemaVersion(at: paths.state)
        guard version != 3 else { return }
        guard version == 1 || version == 2 else {
            throw WorkstateStorageError.invalidState("Unsupported schema version \(version)")
        }

        _ = try withLock(exclusive: true) {
            let currentVersion = try schemaVersion(at: paths.state)
            guard currentVersion != 3 else { return }
            let stamp = Int(Date().timeIntervalSince1970)
            let stateBackup = paths.root.appendingPathComponent("state-v\(currentVersion)-backup-\(stamp).json")
            try FileManager.default.copyItem(at: paths.state, to: stateBackup)
            if FileManager.default.fileExists(atPath: paths.events.path) {
                let eventsBackup = paths.root.appendingPathComponent("events-v\(currentVersion)-backup-\(stamp).jsonl")
                try FileManager.default.copyItem(at: paths.events, to: eventsBackup)
            }
            if currentVersion == 2 {
                try migrateV2StateUnlocked()
            } else {
                let snapshot = initial ?? WorkstateBootstrap.makeInitialState()
                try validate(snapshot)
                try writeUnlocked(snapshot)
            }
            try appendMutationUnlocked(
                WorkspaceMutation(
                    kind: "workspace.migrate",
                    summary: "Archived schema v\(currentVersion) and initialized Workstate schema v3"
                )
            )
        }
    }

    public func load() throws -> WorkspaceSnapshot {
        try ensureInitialized()
        return try withLock(exclusive: false) {
            try loadUnlocked()
        }
    }

    @discardableResult
    public func update(
        mutation: WorkspaceMutation,
        mutate: (inout WorkspaceSnapshot) throws -> Void
    ) throws -> WorkspaceSnapshot {
        try ensureInitialized()
        return try withLock(exclusive: true) {
            var snapshot = try loadUnlocked()
            try mutate(&snapshot)
            snapshot.updatedAt = mutation.timestamp
            try validate(snapshot)
            try writeUnlocked(snapshot)
            try appendMutationUnlocked(mutation)
            return snapshot
        }
    }

    public func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: paths.state.path)
        return attributes?[.modificationDate] as? Date
    }

    private func schemaVersion(at url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["schemaVersion"] as? Int else {
            throw WorkstateStorageError.invalidState("state.json has no schemaVersion")
        }
        return value
    }

    private func loadUnlocked() throws -> WorkspaceSnapshot {
        let data = try Data(contentsOf: paths.state)
        let snapshot = try WorkstateCoding.makeDecoder().decode(WorkspaceSnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    private func writeUnlocked(_ snapshot: WorkspaceSnapshot) throws {
        let data = try WorkstateCoding.makeEncoder().encode(snapshot)
        try data.write(to: paths.state, options: .atomic)
    }

    private func appendMutationUnlocked(_ mutation: WorkspaceMutation) throws {
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(mutation)
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: paths.events.path) {
            FileManager.default.createFile(atPath: paths.events.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: paths.events)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func validate(_ snapshot: WorkspaceSnapshot) throws {
        guard snapshot.schemaVersion == 3 else {
            throw WorkstateStorageError.invalidState("Expected schema version 3")
        }

        let sourceIDs = Set(snapshot.sources.map(\.id))
        guard sourceIDs.count == snapshot.sources.count else {
            throw WorkstateStorageError.invalidState("Duplicate source id")
        }

        let projectIDs = Set(snapshot.projects.map(\.id))
        guard projectIDs.count == snapshot.projects.count else {
            throw WorkstateStorageError.invalidState("Duplicate project id")
        }

        for relation in snapshot.relations {
            guard projectIDs.contains(relation.fromProjectID), projectIDs.contains(relation.toProjectID) else {
                throw WorkstateStorageError.invalidState("Relation \(relation.id) references an unknown project")
            }
            try validateSourceIDs(relation.sourceIDs, known: sourceIDs, owner: "relation \(relation.id)")
        }

        let relationIDs = Set(snapshot.relations.map(\.id))
        guard relationIDs.count == snapshot.relations.count else {
            throw WorkstateStorageError.invalidState("Duplicate relation id")
        }

        let reviewIDs = Set(snapshot.reviewInbox.map(\.id))
        guard reviewIDs.count == snapshot.reviewInbox.count else {
            throw WorkstateStorageError.invalidState("Duplicate review id")
        }
        for review in snapshot.reviewInbox {
            if let projectID = review.projectID, !projectIDs.contains(projectID) {
                throw WorkstateStorageError.invalidState("Review \(review.id) references an unknown project")
            }
            try validateSourceIDs(review.sourceIDs, known: sourceIDs, owner: "review \(review.id)")
        }

        for project in snapshot.projects {
            guard project.graphPosition.x.isFinite, project.graphPosition.y.isFinite else {
                throw WorkstateStorageError.invalidState("Invalid graph position for \(project.id)")
            }
            try validateSourceIDs(project.sourceIDs, known: sourceIDs, owner: "project \(project.id)")

            let taskIDs = Set(project.tasks.map(\.id))
            guard taskIDs.count == project.tasks.count else {
                throw WorkstateStorageError.invalidState("Duplicate task id in \(project.id)")
            }
            let eventIDs = Set(project.events.map(\.id))
            guard eventIDs.count == project.events.count else {
                throw WorkstateStorageError.invalidState("Duplicate event id in \(project.id)")
            }
            let revisionIDs = Set(project.context.revisions.map(\.id))
            guard revisionIDs.count == project.context.revisions.count else {
                throw WorkstateStorageError.invalidState("Duplicate context revision id in \(project.id)")
            }

            for statement in project.context.understanding {
                try validateSourceIDs(statement.sourceIDs, known: sourceIDs, owner: "statement \(statement.id)")
            }
            for revision in project.context.revisions {
                try validateSourceIDs(revision.sourceIDs, known: sourceIDs, owner: "revision \(revision.id)")
            }
            for task in project.tasks {
                guard eventIDs.contains(task.branchedFromEventID) else {
                    throw WorkstateStorageError.invalidState("Task \(task.id) has an unknown branch point")
                }
                if let mergedByEventID = task.mergedByEventID, !eventIDs.contains(mergedByEventID) {
                    throw WorkstateStorageError.invalidState("Task \(task.id) has an unknown merge event")
                }
                try validateSourceIDs(task.sourceIDs, known: sourceIDs, owner: "task \(task.id)")
            }
            for event in project.events {
                if let taskID = event.taskID, !taskIDs.contains(taskID) {
                    throw WorkstateStorageError.invalidState("Event \(event.id) references an unknown task")
                }
                for parentID in event.parentEventIDs where !eventIDs.contains(parentID) {
                    throw WorkstateStorageError.invalidState("Event \(event.id) has unknown parent \(parentID)")
                }
                try validateSourceIDs(event.sourceIDs, known: sourceIDs, owner: "event \(event.id)")
                for decision in event.decisions {
                    try validateSourceIDs(decision.sourceIDs, known: sourceIDs, owner: "decision \(decision.id)")
                }
            }
        }
    }

    private func validateSourceIDs(_ ids: [String], known: Set<String>, owner: String) throws {
        for id in ids where !known.contains(id) {
            throw WorkstateStorageError.invalidState("\(owner) references unknown source \(id)")
        }
    }

    private func migrateV2StateUnlocked() throws {
        let data = try Data(contentsOf: paths.state)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkstateStorageError.invalidState("Schema v2 state is not a JSON object")
        }

        root["schemaVersion"] = 3
        root["reviewInbox"] = []
        root["daemon"] = [
            "activity": DaemonActivity.stopped.rawValue,
            "pendingEvidenceCount": 0,
            "detail": ""
        ]

        if var projects = root["projects"] as? [[String: Any]] {
            for index in projects.indices {
                guard var context = projects[index]["context"] as? [String: Any] else { continue }
                context["objectModel"] = context["objectModel"] ?? []
                context["acceptedDecisions"] = context["acceptedDecisions"] ?? []
                context["forbiddenDirections"] = context["forbiddenDirections"] ?? []
                context["openIssues"] = context["openIssues"] ?? []
                projects[index]["context"] = context
            }
            root["projects"] = projects
        }

        if var sources = root["sources"] as? [[String: Any]] {
            for index in sources.indices {
                sources[index]["threadID"] = sources[index]["threadID"] ?? ""
                sources[index]["turnIDs"] = sources[index]["turnIDs"] ?? []
                sources[index]["excerpt"] = sources[index]["excerpt"] ?? []
                sources[index]["contentHash"] = sources[index]["contentHash"] ?? ""
            }
            root["sources"] = sources
        }

        let migratedData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let snapshot = try WorkstateCoding.makeDecoder().decode(WorkspaceSnapshot.self, from: migratedData)
        try validate(snapshot)
        try writeUnlocked(snapshot)
    }

    private func withLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let descriptor = open(paths.lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw WorkstateStorageError.cannotCreateLock(paths.lock.path)
        }
        defer { close(descriptor) }
        let operation = exclusive ? LOCK_EX : LOCK_SH
        guard flock(descriptor, operation) == 0 else {
            throw WorkstateStorageError.cannotLock(paths.lock.path)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
