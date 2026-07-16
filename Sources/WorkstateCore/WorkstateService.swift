import Foundation

public struct ProjectCreateInput: Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var purpose: String
    public var status: ProjectStatus
    public var accent: ProjectAccent
    public var position: GraphPosition
    public var sourceIDs: [String]

    public init(
        id: String,
        name: String,
        summary: String,
        purpose: String,
        status: ProjectStatus = .active,
        accent: ProjectAccent = .blue,
        position: GraphPosition,
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.purpose = purpose
        self.status = status
        self.accent = accent
        self.position = position
        self.sourceIDs = sourceIDs
    }
}

public struct ProjectUpdate: Sendable {
    public var name: String?
    public var summary: String?
    public var status: ProjectStatus?
    public var position: GraphPosition?

    public init(
        name: String? = nil,
        summary: String? = nil,
        status: ProjectStatus? = nil,
        position: GraphPosition? = nil
    ) {
        self.name = name
        self.summary = summary
        self.status = status
        self.position = position
    }
}

public struct ProjectModelUpdate: Sendable {
    public var currentSummary: String?
    public var purpose: String?
    public var objectModel: [String]?
    public var acceptedDecisions: [DecisionRecord]?
    public var forbiddenDirections: [String]?
    public var openIssues: [String]?

    public init(
        currentSummary: String? = nil,
        purpose: String? = nil,
        objectModel: [String]? = nil,
        acceptedDecisions: [DecisionRecord]? = nil,
        forbiddenDirections: [String]? = nil,
        openIssues: [String]? = nil
    ) {
        self.currentSummary = currentSummary
        self.purpose = purpose
        self.objectModel = objectModel
        self.acceptedDecisions = acceptedDecisions
        self.forbiddenDirections = forbiddenDirections
        self.openIssues = openIssues
    }
}

public struct TaskStartInput: Sendable {
    public var projectID: String
    public var id: String
    public var title: String
    public var objective: String
    public var accent: ProjectAccent
    public var stage: LoopStage
    public var branchedFromEventID: String
    public var tags: [String]
    public var sourceIDs: [String]

    public init(
        projectID: String,
        id: String,
        title: String,
        objective: String,
        accent: ProjectAccent = .blue,
        stage: LoopStage = .intake,
        branchedFromEventID: String,
        tags: [String] = [],
        sourceIDs: [String] = []
    ) {
        self.projectID = projectID
        self.id = id
        self.title = title
        self.objective = objective
        self.accent = accent
        self.stage = stage
        self.branchedFromEventID = branchedFromEventID
        self.tags = tags
        self.sourceIDs = sourceIDs
    }
}

public struct TaskUpdate: Sendable {
    public var status: TaskStatus?
    public var stage: LoopStage?
    public var title: String?
    public var objective: String?

    public init(
        status: TaskStatus? = nil,
        stage: LoopStage? = nil,
        title: String? = nil,
        objective: String? = nil
    ) {
        self.status = status
        self.stage = stage
        self.title = title
        self.objective = objective
    }
}

public struct EventInput: Sendable {
    public var id: String?
    public var projectID: String
    public var taskID: String?
    public var mergeTaskID: String?
    public var title: String
    public var summary: String
    public var kind: EventKind
    public var stage: LoopStage
    public var parentEventIDs: [String]
    public var facts: [String]
    public var decisions: [DecisionRecord]
    public var operations: OperationalContext
    public var delivery: DeliverySnapshot
    public var tags: [String]
    public var sourceIDs: [String]

    public init(
        id: String? = nil,
        projectID: String,
        taskID: String? = nil,
        mergeTaskID: String? = nil,
        title: String,
        summary: String,
        kind: EventKind,
        stage: LoopStage,
        parentEventIDs: [String] = [],
        facts: [String] = [],
        decisions: [DecisionRecord] = [],
        operations: OperationalContext = .init(),
        delivery: DeliverySnapshot = .init(),
        tags: [String] = [],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.taskID = taskID
        self.mergeTaskID = mergeTaskID
        self.title = title
        self.summary = summary
        self.kind = kind
        self.stage = stage
        self.parentEventIDs = parentEventIDs
        self.facts = facts
        self.decisions = decisions
        self.operations = operations
        self.delivery = delivery
        self.tags = tags
        self.sourceIDs = sourceIDs
    }
}

public struct ContextRevisionInput: Sendable {
    public var id: String?
    public var projectID: String
    public var title: String
    public var summary: String
    public var status: EvidenceStatus
    public var changes: [String]
    public var sourceIDs: [String]
    public var currentSummary: String?
    public var statementID: String?
    public var statement: String?

    public init(
        id: String? = nil,
        projectID: String,
        title: String,
        summary: String,
        status: EvidenceStatus,
        changes: [String] = [],
        sourceIDs: [String] = [],
        currentSummary: String? = nil,
        statementID: String? = nil,
        statement: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.summary = summary
        self.status = status
        self.changes = changes
        self.sourceIDs = sourceIDs
        self.currentSummary = currentSummary
        self.statementID = statementID
        self.statement = statement
    }
}

public struct WorkstateService: Sendable {
    public let repository: WorkstateRepository

    public init(repository: WorkstateRepository = .init()) {
        self.repository = repository
    }

    public func snapshot() throws -> WorkspaceSnapshot {
        try repository.load()
    }

    public func compactProject(projectID: String, recentLimit: Int = 8) throws -> CompactProjectContext {
        let snapshot = try repository.load()
        guard let project = snapshot.project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }
        let relationIDs = snapshot.relations.filter {
            $0.fromProjectID == projectID || $0.toProjectID == projectID
        }
        return CompactProjectContext(
            project: project,
            relations: relationIDs,
            activeTasks: project.activeTasks.sorted { $0.updatedAt > $1.updatedAt },
            recentEvents: Array(project.events.sorted { $0.timestamp > $1.timestamp }.prefix(max(1, recentLimit))),
            recentRevisions: Array(project.context.revisions.sorted { $0.timestamp > $1.timestamp }.prefix(max(1, recentLimit)))
        )
    }

    public func taskContext(taskID: String) throws -> TaskContext {
        let snapshot = try repository.load()
        for project in snapshot.projects {
            guard let task = project.task(id: taskID) else { continue }
            let events = project.events(for: taskID)
            let sourceIDs = Set(task.sourceIDs + events.flatMap(\.sourceIDs))
            return TaskContext(
                projectID: project.id,
                projectName: project.name,
                task: task,
                events: events,
                sources: snapshot.sources.filter { sourceIDs.contains($0.id) }
            )
        }
        throw WorkstateStorageError.missingTask(taskID)
    }

    @discardableResult
    public func upsertReview(_ item: ReviewItem) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "review.upsert",
            summary: item.title,
            projectID: item.projectID,
            taskID: item.taskID
        )
        return try repository.update(mutation: mutation) { snapshot in
            if let index = snapshot.reviewInbox.firstIndex(where: { $0.id == item.id }) {
                snapshot.reviewInbox[index] = item
            } else {
                snapshot.reviewInbox.append(item)
            }
        }
    }

    @discardableResult
    public func resolveReview(id: String, status: ReviewStatus) throws -> WorkspaceSnapshot {
        guard status == .confirmed || status == .rejected || status == .deferred else {
            throw WorkstateStorageError.invalidState("Review resolution must be confirmed, rejected, or deferred")
        }
        let mutation = WorkspaceMutation(kind: "review.resolve", summary: id)
        return try repository.update(mutation: mutation) { snapshot in
            guard let reviewIndex = snapshot.reviewInbox.firstIndex(where: { $0.id == id }) else {
                throw WorkstateStorageError.invalidState("Review not found: \(id)")
            }
            var review = snapshot.reviewInbox[reviewIndex]
            review.status = status
            review.updatedAt = mutation.timestamp

            if status == .confirmed,
               let projectID = review.projectID,
               let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) {
                switch review.kind {
                case .understandingConflict where !review.proposedValue.isEmpty:
                    snapshot.projects[projectIndex].context.currentSummary = review.proposedValue
                    snapshot.projects[projectIndex].context.revisions.append(
                        ContextRevision(
                            timestamp: mutation.timestamp,
                            title: review.title,
                            summary: review.summary,
                            status: .confirmed,
                            changes: review.proposedChanges,
                            sourceIDs: review.sourceIDs
                        )
                    )
                case .decisionConflict where !review.proposedValue.isEmpty:
                    snapshot.projects[projectIndex].context.acceptedDecisions.append(
                        DecisionRecord(
                            text: review.proposedValue,
                            status: .confirmed,
                            rationale: review.reason,
                            sourceIDs: review.sourceIDs
                        )
                    )
                default:
                    break
                }
                snapshot.projects[projectIndex].updatedAt = mutation.timestamp
                snapshot.projects[projectIndex].lastActivityAt = mutation.timestamp
            }

            snapshot.reviewInbox[reviewIndex] = review
        }
    }

    @discardableResult
    public func updateDaemon(_ daemon: DaemonSnapshot) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(kind: "daemon.update", summary: daemon.activity.rawValue)
        return try repository.update(mutation: mutation) { snapshot in
            snapshot.daemon = daemon
        }
    }

    @discardableResult
    public func appendOpenIssues(projectID: String, issues: [String]) throws -> WorkspaceSnapshot {
        guard !issues.isEmpty else { return try repository.load() }
        let mutation = WorkspaceMutation(kind: "context.open-issues", summary: projectID, projectID: projectID)
        return try repository.update(mutation: mutation) { snapshot in
            let index = try projectIndex(projectID, in: snapshot)
            var existing = Set(snapshot.projects[index].context.openIssues)
            for issue in issues where existing.insert(issue).inserted {
                snapshot.projects[index].context.openIssues.append(issue)
            }
            touchProject(at: index, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func addSource(_ source: SourceReference) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(kind: "source.upsert", summary: source.label)
        return try repository.update(mutation: mutation) { snapshot in
            if let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
                snapshot.sources[index] = source
            } else {
                snapshot.sources.append(source)
            }
        }
    }

    @discardableResult
    public func createProject(_ input: ProjectCreateInput) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "project.create",
            summary: input.name,
            projectID: input.id
        )
        return try repository.update(mutation: mutation) { snapshot in
            guard snapshot.project(id: input.id) == nil else {
                throw WorkstateStorageError.invalidState("Project already exists: \(input.id)")
            }
            let startID = "project-start-\(UUID().uuidString.lowercased())"
            let event = ProjectEvent(
                id: startID,
                timestamp: mutation.timestamp,
                title: "项目建立",
                summary: input.summary,
                kind: .projectStarted,
                loopStage: .intake,
                sourceIDs: input.sourceIDs
            )
            snapshot.projects.append(
                ProjectRecord(
                    id: input.id,
                    name: input.name,
                    summary: input.summary,
                    status: input.status,
                    accent: input.accent,
                    createdAt: mutation.timestamp,
                    updatedAt: mutation.timestamp,
                    lastActivityAt: mutation.timestamp,
                    graphPosition: input.position,
                    context: ProjectContext(currentSummary: input.summary, purpose: input.purpose),
                    events: [event],
                    sourceIDs: input.sourceIDs
                )
            )
        }
    }

    @discardableResult
    public func updateProject(id: String, update: ProjectUpdate) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(kind: "project.update", summary: id, projectID: id)
        return try repository.update(mutation: mutation) { snapshot in
            let index = try projectIndex(id, in: snapshot)
            if let name = update.name { snapshot.projects[index].name = name }
            if let summary = update.summary { snapshot.projects[index].summary = summary }
            if let status = update.status { snapshot.projects[index].status = status }
            if let position = update.position { snapshot.projects[index].graphPosition = position }
            snapshot.projects[index].updatedAt = mutation.timestamp
        }
    }

    @discardableResult
    public func updateProjectModel(id: String, update: ProjectModelUpdate) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(kind: "project.model", summary: id, projectID: id)
        return try repository.update(mutation: mutation) { snapshot in
            let index = try projectIndex(id, in: snapshot)
            if let currentSummary = update.currentSummary {
                snapshot.projects[index].context.currentSummary = currentSummary
                snapshot.projects[index].summary = currentSummary
            }
            if let purpose = update.purpose {
                snapshot.projects[index].context.purpose = purpose
            }
            if let objectModel = update.objectModel {
                snapshot.projects[index].context.objectModel = objectModel
            }
            if let acceptedDecisions = update.acceptedDecisions {
                snapshot.projects[index].context.acceptedDecisions = acceptedDecisions
            }
            if let forbiddenDirections = update.forbiddenDirections {
                snapshot.projects[index].context.forbiddenDirections = forbiddenDirections
            }
            if let openIssues = update.openIssues {
                snapshot.projects[index].context.openIssues = openIssues
            }
            touchProject(at: index, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func upsertRelation(_ relation: ProjectRelation) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "relation.upsert",
            summary: relation.label,
            projectID: relation.fromProjectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            guard snapshot.project(id: relation.fromProjectID) != nil else {
                throw WorkstateStorageError.missingProject(relation.fromProjectID)
            }
            guard snapshot.project(id: relation.toProjectID) != nil else {
                throw WorkstateStorageError.missingProject(relation.toProjectID)
            }
            if let index = snapshot.relations.firstIndex(where: { $0.id == relation.id }) {
                snapshot.relations[index] = relation
            } else {
                snapshot.relations.append(relation)
            }
        }
    }

    @discardableResult
    public func startTask(_ input: TaskStartInput) throws -> WorkspaceSnapshot {
        let eventID = "task-start-\(UUID().uuidString.lowercased())"
        let mutation = WorkspaceMutation(
            kind: "task.start",
            summary: input.title,
            projectID: input.projectID,
            taskID: input.id,
            eventID: eventID
        )
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(input.projectID, in: snapshot)
            guard snapshot.projects[projectIndex].task(id: input.id) == nil else {
                throw WorkstateStorageError.invalidState("Task already exists: \(input.id)")
            }
            guard snapshot.projects[projectIndex].event(id: input.branchedFromEventID) != nil else {
                throw WorkstateStorageError.missingEvent(input.branchedFromEventID)
            }
            let task = TaskRecord(
                id: input.id,
                title: input.title,
                objective: input.objective,
                accent: input.accent,
                currentStage: input.stage,
                startedAt: mutation.timestamp,
                updatedAt: mutation.timestamp,
                branchedFromEventID: input.branchedFromEventID,
                tags: input.tags,
                sourceIDs: input.sourceIDs
            )
            let event = ProjectEvent(
                id: eventID,
                taskID: input.id,
                timestamp: mutation.timestamp,
                title: input.title,
                summary: input.objective,
                kind: .taskStarted,
                loopStage: input.stage,
                parentEventIDs: [input.branchedFromEventID],
                tags: input.tags,
                sourceIDs: input.sourceIDs
            )
            snapshot.projects[projectIndex].tasks.append(task)
            snapshot.projects[projectIndex].events.append(event)
            touchProject(at: projectIndex, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func updateTask(id: String, update: TaskUpdate) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(kind: "task.update", summary: id, taskID: id)
        return try repository.update(mutation: mutation) { snapshot in
            let location = try taskLocation(id, in: snapshot)
            if let status = update.status { snapshot.projects[location.project].tasks[location.task].status = status }
            if let stage = update.stage { snapshot.projects[location.project].tasks[location.task].currentStage = stage }
            if let title = update.title { snapshot.projects[location.project].tasks[location.task].title = title }
            if let objective = update.objective { snapshot.projects[location.project].tasks[location.task].objective = objective }
            snapshot.projects[location.project].tasks[location.task].updatedAt = mutation.timestamp
            if update.status == .completed || update.status == .abandoned {
                snapshot.projects[location.project].tasks[location.task].completedAt = mutation.timestamp
            }
            touchProject(at: location.project, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func appendEvent(_ input: EventInput) throws -> WorkspaceSnapshot {
        let eventID = input.id ?? UUID().uuidString.lowercased()
        let mutation = WorkspaceMutation(
            kind: "event.append",
            summary: input.title,
            projectID: input.projectID,
            taskID: input.taskID ?? input.mergeTaskID,
            eventID: eventID
        )
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(input.projectID, in: snapshot)
            guard snapshot.projects[projectIndex].event(id: eventID) == nil else {
                throw WorkstateStorageError.invalidState("Event already exists: \(eventID)")
            }
            if let taskID = input.taskID, snapshot.projects[projectIndex].task(id: taskID) == nil {
                throw WorkstateStorageError.missingTask(taskID)
            }
            if let mergeTaskID = input.mergeTaskID, snapshot.projects[projectIndex].task(id: mergeTaskID) == nil {
                throw WorkstateStorageError.missingTask(mergeTaskID)
            }

            let parents = try resolvedParents(for: input, project: snapshot.projects[projectIndex])
            let event = ProjectEvent(
                id: eventID,
                taskID: input.taskID,
                timestamp: mutation.timestamp,
                title: input.title,
                summary: input.summary,
                kind: input.kind,
                loopStage: input.stage,
                parentEventIDs: parents,
                facts: input.facts,
                decisions: input.decisions,
                operations: input.operations,
                delivery: input.delivery,
                tags: input.tags,
                sourceIDs: input.sourceIDs
            )
            snapshot.projects[projectIndex].events.append(event)

            if let taskID = input.taskID,
               let taskIndex = snapshot.projects[projectIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                snapshot.projects[projectIndex].tasks[taskIndex].currentStage = input.stage
                snapshot.projects[projectIndex].tasks[taskIndex].updatedAt = mutation.timestamp
                if input.kind == .completed {
                    snapshot.projects[projectIndex].tasks[taskIndex].status = .completed
                    snapshot.projects[projectIndex].tasks[taskIndex].completedAt = mutation.timestamp
                } else if input.kind == .interruption {
                    snapshot.projects[projectIndex].tasks[taskIndex].status = .waiting
                } else if input.kind == .resumed {
                    snapshot.projects[projectIndex].tasks[taskIndex].status = .active
                }
            }
            if let mergeTaskID = input.mergeTaskID,
               let taskIndex = snapshot.projects[projectIndex].tasks.firstIndex(where: { $0.id == mergeTaskID }) {
                snapshot.projects[projectIndex].tasks[taskIndex].status = .completed
                snapshot.projects[projectIndex].tasks[taskIndex].currentStage = .completed
                snapshot.projects[projectIndex].tasks[taskIndex].completedAt = mutation.timestamp
                snapshot.projects[projectIndex].tasks[taskIndex].mergedByEventID = eventID
            }
            touchProject(at: projectIndex, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func reviseContext(_ input: ContextRevisionInput) throws -> WorkspaceSnapshot {
        let revisionID = input.id ?? UUID().uuidString.lowercased()
        let mutation = WorkspaceMutation(
            kind: "context.revise",
            summary: input.title,
            projectID: input.projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            let index = try projectIndex(input.projectID, in: snapshot)
            guard !snapshot.projects[index].context.revisions.contains(where: { $0.id == revisionID }) else {
                throw WorkstateStorageError.invalidState("Context revision already exists: \(revisionID)")
            }
            snapshot.projects[index].context.revisions.append(
                ContextRevision(
                    id: revisionID,
                    timestamp: mutation.timestamp,
                    title: input.title,
                    summary: input.summary,
                    status: input.status,
                    changes: input.changes,
                    sourceIDs: input.sourceIDs
                )
            )
            if let currentSummary = input.currentSummary, input.status == .observed || input.status == .confirmed {
                snapshot.projects[index].context.currentSummary = currentSummary
                snapshot.projects[index].summary = currentSummary
            }
            if let statement = input.statement {
                let statementID = input.statementID ?? UUID().uuidString.lowercased()
                let value = ContextStatement(
                    id: statementID,
                    text: statement,
                    status: input.status,
                    updatedAt: mutation.timestamp,
                    sourceIDs: input.sourceIDs
                )
                if let statementIndex = snapshot.projects[index].context.understanding.firstIndex(where: { $0.id == statementID }) {
                    snapshot.projects[index].context.understanding[statementIndex] = value
                } else {
                    snapshot.projects[index].context.understanding.append(value)
                }
            }
            touchProject(at: index, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    private func projectIndex(_ id: String, in snapshot: WorkspaceSnapshot) throws -> Int {
        guard let index = snapshot.projects.firstIndex(where: { $0.id == id }) else {
            throw WorkstateStorageError.missingProject(id)
        }
        return index
    }

    private func taskLocation(_ id: String, in snapshot: WorkspaceSnapshot) throws -> (project: Int, task: Int) {
        for projectIndex in snapshot.projects.indices {
            if let taskIndex = snapshot.projects[projectIndex].tasks.firstIndex(where: { $0.id == id }) {
                return (projectIndex, taskIndex)
            }
        }
        throw WorkstateStorageError.missingTask(id)
    }

    private func resolvedParents(for input: EventInput, project: ProjectRecord) throws -> [String] {
        if !input.parentEventIDs.isEmpty {
            for id in input.parentEventIDs where project.event(id: id) == nil {
                throw WorkstateStorageError.missingEvent(id)
            }
            return input.parentEventIDs
        }
        if let taskID = input.taskID {
            return project.events
                .last { $0.taskID == taskID }
                .map { [$0.id] }
                ?? project.task(id: taskID).map { [$0.branchedFromEventID] }
                ?? []
        }
        var parents = project.events
            .last { $0.taskID == nil }
            .map { [$0.id] }
            ?? []
        if let mergeTaskID = input.mergeTaskID,
           let latestTaskEvent = project.events.last(where: { $0.taskID == mergeTaskID }) {
            parents.append(latestTaskEvent.id)
        }
        return Array(Set(parents))
    }

    private func touchProject(at index: Int, timestamp: Date, in snapshot: inout WorkspaceSnapshot) {
        snapshot.projects[index].updatedAt = timestamp
        snapshot.projects[index].lastActivityAt = timestamp
    }
}
