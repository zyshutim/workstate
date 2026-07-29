import Foundation

public struct ProjectCreateInput: Codable, Sendable {
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

    public init(
        currentSummary: String? = nil,
        purpose: String? = nil,
        objectModel: [String]? = nil,
        acceptedDecisions: [DecisionRecord]? = nil,
        forbiddenDirections: [String]? = nil
    ) {
        self.currentSummary = currentSummary
        self.purpose = purpose
        self.objectModel = objectModel
        self.acceptedDecisions = acceptedDecisions
        self.forbiddenDirections = forbiddenDirections
    }
}

public struct ProjectTopicUpdateInput: Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var status: ProjectTopicStatus
    public var kind: ProjectTopicKind
    public var disposition: ProjectTopicDisposition
    public var currentUnderstanding: String
    public var proposedDirection: String
    public var deferredReason: String
    public var revisitTrigger: String
    public var openQuestions: [String]
    public var note: ProjectTopicNote?
    public var sourceIDs: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        status: ProjectTopicStatus,
        kind: ProjectTopicKind,
        disposition: ProjectTopicDisposition = .futureDecision,
        currentUnderstanding: String,
        proposedDirection: String = "",
        deferredReason: String = "",
        revisitTrigger: String = "",
        openQuestions: [String] = [],
        note: ProjectTopicNote? = nil,
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.kind = kind
        self.disposition = disposition
        self.currentUnderstanding = currentUnderstanding
        self.proposedDirection = proposedDirection
        self.deferredReason = deferredReason
        self.revisitTrigger = revisitTrigger
        self.openQuestions = openQuestions
        self.note = note
        self.sourceIDs = sourceIDs
    }
}

public struct ProjectTopicPromotionInput: Sendable {
    public var projectID: String
    public var topicID: String
    public var kind: ProjectTopicPromotionKind
    public var title: String
    public var detail: String

    public init(
        projectID: String,
        topicID: String,
        kind: ProjectTopicPromotionKind,
        title: String,
        detail: String
    ) {
        self.projectID = projectID
        self.topicID = topicID
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct ProjectTopicResolutionInput: Sendable {
    public var projectID: String
    public var topicID: String
    public var resolution: ProjectTopicResolution

    public init(
        projectID: String,
        topicID: String,
        resolution: ProjectTopicResolution
    ) {
        self.projectID = projectID
        self.topicID = topicID
        self.resolution = resolution
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
    public var timestamp: Date?
    public var eventID: String?

    public init(
        projectID: String,
        id: String,
        title: String,
        objective: String,
        accent: ProjectAccent = .blue,
        stage: LoopStage = .intake,
        branchedFromEventID: String,
        tags: [String] = [],
        sourceIDs: [String] = [],
        timestamp: Date? = nil,
        eventID: String? = nil
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
        self.timestamp = timestamp
        self.eventID = eventID
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

public struct WorklineReconciliationInput: Codable, Sendable {
    public var projectID: String
    public var worklines: [WorklineReconciliation]

    public init(projectID: String, worklines: [WorklineReconciliation]) {
        self.projectID = projectID
        self.worklines = worklines
    }
}

public struct WorklineReconciliation: Codable, Sendable {
    public var id: String
    public var title: String
    public var objective: String
    public var status: TaskStatus
    public var accent: ProjectAccent
    public var branchedFromEventID: String
    public var mergedByEventID: String?
    public var eventIDs: [String]
    public var tags: [String]

    public init(
        id: String,
        title: String,
        objective: String,
        status: TaskStatus,
        accent: ProjectAccent,
        branchedFromEventID: String,
        mergedByEventID: String? = nil,
        eventIDs: [String],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.objective = objective
        self.status = status
        self.accent = accent
        self.branchedFromEventID = branchedFromEventID
        self.mergedByEventID = mergedByEventID
        self.eventIDs = eventIDs
        self.tags = tags
    }
}

public struct EventInput: Sendable {
    public var id: String?
    public var timestamp: Date?
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
        timestamp: Date? = nil,
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
        self.timestamp = timestamp
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

    public func contextSnapshot(
        projectID: String,
        generatedAt: Date = Date(),
        collaborationGuidance: [String] = []
    ) throws -> ContextSnapshot {
        try ContextSnapshotBuilder().project(
            projectID,
            from: repository.load(),
            generatedAt: generatedAt,
            collaborationGuidance: collaborationGuidance
        )
    }

    public func contextSnapshot(
        taskID: String,
        generatedAt: Date = Date(),
        collaborationGuidance: [String] = []
    ) throws -> ContextSnapshot {
        try ContextSnapshotBuilder().task(
            taskID,
            from: repository.load(),
            generatedAt: generatedAt,
            collaborationGuidance: collaborationGuidance
        )
    }

    public func contextSnapshot(
        threadID: String,
        projectID: String,
        generatedAt: Date = Date(),
        collaborationGuidance: [String] = []
    ) throws -> ContextSnapshot {
        try ContextSnapshotBuilder().thread(
            threadID,
            projectID: projectID,
            from: repository.load(),
            generatedAt: generatedAt,
            collaborationGuidance: collaborationGuidance
        )
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
    public func removeReviews(ids: Set<String>) throws -> WorkspaceSnapshot {
        guard !ids.isEmpty else { return try snapshot() }
        let mutation = WorkspaceMutation(kind: "review.remove", summary: "Removed \(ids.count) reviews")
        return try repository.update(mutation: mutation) { snapshot in
            snapshot.reviewInbox.removeAll { ids.contains($0.id) }
        }
    }

    @discardableResult
    public func removeSourceArtifacts(sourceIDs: Set<String>) throws -> WorkspaceSnapshot {
        guard !sourceIDs.isEmpty else { return try snapshot() }
        let mutation = WorkspaceMutation(
            kind: "source.cleanup",
            summary: "Removed artifacts from \(sourceIDs.count) internal sources"
        )
        return try repository.update(mutation: mutation) { snapshot in
            snapshot.reviewInbox.removeAll { !$0.sourceIDs.allSatisfy { !sourceIDs.contains($0) } }
            snapshot.relations.removeAll { relation in
                !relation.sourceIDs.isEmpty && relation.sourceIDs.allSatisfy(sourceIDs.contains)
            }
            for relationIndex in snapshot.relations.indices {
                snapshot.relations[relationIndex].sourceIDs.removeAll(where: sourceIDs.contains)
            }

            for projectIndex in snapshot.projects.indices {
                snapshot.projects[projectIndex].sourceIDs.removeAll(where: sourceIDs.contains)
                snapshot.projects[projectIndex].context.understanding.removeAll { statement in
                    !statement.sourceIDs.isEmpty && statement.sourceIDs.allSatisfy(sourceIDs.contains)
                }
                snapshot.projects[projectIndex].context.revisions.removeAll { revision in
                    !revision.sourceIDs.isEmpty && revision.sourceIDs.allSatisfy(sourceIDs.contains)
                }
                snapshot.projects[projectIndex].context.acceptedDecisions.removeAll { decision in
                    !decision.sourceIDs.isEmpty && decision.sourceIDs.allSatisfy(sourceIDs.contains)
                }
                for statementIndex in snapshot.projects[projectIndex].context.understanding.indices {
                    snapshot.projects[projectIndex].context.understanding[statementIndex].sourceIDs
                        .removeAll(where: sourceIDs.contains)
                }
                for revisionIndex in snapshot.projects[projectIndex].context.revisions.indices {
                    snapshot.projects[projectIndex].context.revisions[revisionIndex].sourceIDs
                        .removeAll(where: sourceIDs.contains)
                }
                for decisionIndex in snapshot.projects[projectIndex].context.acceptedDecisions.indices {
                    snapshot.projects[projectIndex].context.acceptedDecisions[decisionIndex].sourceIDs
                        .removeAll(where: sourceIDs.contains)
                }
                for taskIndex in snapshot.projects[projectIndex].tasks.indices {
                    snapshot.projects[projectIndex].tasks[taskIndex].sourceIDs
                        .removeAll(where: sourceIDs.contains)
                }
                for topicIndex in snapshot.projects[projectIndex].topics.indices {
                    snapshot.projects[projectIndex].topics[topicIndex].sourceIDs
                        .removeAll(where: sourceIDs.contains)
                    for noteIndex in snapshot.projects[projectIndex].topics[topicIndex].notes.indices {
                        snapshot.projects[projectIndex].topics[topicIndex].notes[noteIndex].sourceIDs
                            .removeAll(where: sourceIDs.contains)
                    }
                }

                let removedEventIDs = Set(snapshot.projects[projectIndex].events.compactMap { event -> String? in
                    guard !event.sourceIDs.isEmpty,
                          event.sourceIDs.allSatisfy(sourceIDs.contains) else { return nil }
                    return event.id
                })
                snapshot.projects[projectIndex].events.removeAll { removedEventIDs.contains($0.id) }
                for eventIndex in snapshot.projects[projectIndex].events.indices {
                    snapshot.projects[projectIndex].events[eventIndex].sourceIDs
                        .removeAll(where: sourceIDs.contains)
                    snapshot.projects[projectIndex].events[eventIndex].parentEventIDs
                        .removeAll(where: removedEventIDs.contains)
                    for decisionIndex in snapshot.projects[projectIndex].events[eventIndex].decisions.indices {
                        snapshot.projects[projectIndex].events[eventIndex].decisions[decisionIndex].sourceIDs
                            .removeAll(where: sourceIDs.contains)
                    }
                }
            }
            snapshot.sources.removeAll { sourceIDs.contains($0.id) }
        }
    }

    @discardableResult
    public func repairEventTimestamps(_ timestamps: [String: Date]) throws -> WorkspaceSnapshot {
        guard !timestamps.isEmpty else { return try snapshot() }
        let mutation = WorkspaceMutation(
            kind: "event.timestamp.repair",
            summary: "Repaired timestamps for generated events"
        )
        return try repository.update(mutation: mutation) { snapshot in
            for projectIndex in snapshot.projects.indices {
                for eventIndex in snapshot.projects[projectIndex].events.indices {
                    let eventID = snapshot.projects[projectIndex].events[eventIndex].id
                    if let timestamp = timestamps[eventID] {
                        snapshot.projects[projectIndex].events[eventIndex].timestamp = timestamp
                    }
                }
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
                if let proposal = review.proposedEvent {
                    guard snapshot.projects[projectIndex].event(id: proposal.eventID) == nil else {
                        throw WorkstateStorageError.invalidState("Proposed event already exists: \(proposal.eventID)")
                    }
                    if let taskID = proposal.taskID,
                       snapshot.projects[projectIndex].task(id: taskID) == nil {
                        throw WorkstateStorageError.missingTask(taskID)
                    }
                    let parentID: String? = if let taskID = proposal.taskID {
                        snapshot.projects[projectIndex].events(for: taskID).first?.id
                            ?? snapshot.projects[projectIndex].task(id: taskID)?.branchedFromEventID
                    } else {
                        snapshot.projects[projectIndex].events
                            .filter { $0.taskID == nil }
                            .max { $0.timestamp < $1.timestamp }?.id
                    }
                    snapshot.projects[projectIndex].events.append(
                        ProjectEvent(
                            id: proposal.eventID,
                            taskID: proposal.taskID,
                            timestamp: proposal.timestamp,
                            title: review.title,
                            summary: review.summary,
                            kind: proposal.kind,
                            loopStage: proposal.stage,
                            parentEventIDs: parentID.map { [$0] } ?? [],
                            facts: proposal.facts,
                            operations: proposal.operations,
                            delivery: DeliverySnapshot(
                                stage: proposal.delivery,
                                verifiedAt: proposal.delivery == .unchanged || proposal.delivery == .changed
                                    ? nil
                                    : proposal.timestamp
                            ),
                            sourceIDs: review.sourceIDs
                        )
                    )
                    if let taskID = proposal.taskID,
                       let taskIndex = snapshot.projects[projectIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                        snapshot.projects[projectIndex].tasks[taskIndex].currentStage = proposal.stage
                        snapshot.projects[projectIndex].tasks[taskIndex].updatedAt = proposal.timestamp
                        if proposal.kind == .completed {
                            snapshot.projects[projectIndex].tasks[taskIndex].status = .completed
                            snapshot.projects[projectIndex].tasks[taskIndex].completedAt = proposal.timestamp
                        } else if proposal.kind == .interruption {
                            snapshot.projects[projectIndex].tasks[taskIndex].status = .waiting
                        } else if proposal.kind == .resumed {
                            snapshot.projects[projectIndex].tasks[taskIndex].status = .active
                        }
                    }
                }
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
    public func upsertTopic(projectID: String, input: ProjectTopicUpdateInput) throws -> WorkspaceSnapshot {
        guard !input.id.isEmpty,
              !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.currentUnderstanding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState("Topic id, title, and current understanding are required")
        }
        guard input.status == .captured || input.status == .discussing else {
            throw WorkstateStorageError.invalidState("Automatic topic updates cannot confirm or close a topic")
        }
        let mutation = WorkspaceMutation(kind: "topic.upsert", summary: input.title, projectID: projectID)
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(projectID, in: snapshot)
            if let topicIndex = snapshot.projects[projectIndex].topics.firstIndex(where: { $0.id == input.id }) {
                guard snapshot.projects[projectIndex].topics[topicIndex].status != .converted,
                      snapshot.projects[projectIndex].topics[topicIndex].status != .closed else {
                    throw WorkstateStorageError.invalidState("Confirmed or closed topics cannot be overwritten by Owner")
                }
                var topic = snapshot.projects[projectIndex].topics[topicIndex]
                topic.title = input.title
                topic.summary = input.summary
                topic.status = input.status
                topic.kind = input.kind
                topic.disposition = input.disposition
                topic.resolution = nil
                topic.currentUnderstanding = input.currentUnderstanding
                topic.proposedDirection = input.proposedDirection
                topic.deferredReason = input.deferredReason
                topic.revisitTrigger = input.revisitTrigger
                topic.openQuestions = input.openQuestions
                topic.sourceIDs = Array(Set(topic.sourceIDs + input.sourceIDs)).sorted()
                if let note = input.note, !topic.notes.contains(where: { $0.id == note.id }) {
                    topic.notes.append(note)
                }
                topic.updatedAt = mutation.timestamp
                snapshot.projects[projectIndex].topics[topicIndex] = topic
            } else {
                snapshot.projects[projectIndex].topics.append(
                    ProjectTopic(
                        id: input.id,
                        title: input.title,
                        summary: input.summary,
                        status: input.status,
                        kind: input.kind,
                        disposition: input.disposition,
                        currentUnderstanding: input.currentUnderstanding,
                        proposedDirection: input.proposedDirection,
                        deferredReason: input.deferredReason,
                        revisitTrigger: input.revisitTrigger,
                        openQuestions: input.openQuestions,
                        notes: input.note.map { [$0] } ?? [],
                        sourceIDs: input.sourceIDs,
                        createdAt: mutation.timestamp,
                        updatedAt: mutation.timestamp
                    )
                )
            }
            touchProject(at: projectIndex, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func promoteTopic(_ input: ProjectTopicPromotionInput) throws -> WorkspaceSnapshot {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = input.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !detail.isEmpty else {
            throw WorkstateStorageError.invalidState("Promotion title and detail are required")
        }
        let mutation = WorkspaceMutation(kind: "topic.promote", summary: title, projectID: input.projectID)
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(input.projectID, in: snapshot)
            guard let topicIndex = snapshot.projects[projectIndex].topics.firstIndex(where: { $0.id == input.topicID }) else {
                throw WorkstateStorageError.invalidState("Topic not found: \(input.topicID)")
            }
            guard snapshot.projects[projectIndex].topics[topicIndex].status == .captured
                    || snapshot.projects[projectIndex].topics[topicIndex].status == .discussing else {
                throw WorkstateStorageError.invalidState("Only open topics can enter the formal project flow")
            }
            let parentEventID = snapshot.projects[projectIndex].events
                .filter { $0.taskID == nil }
                .max { $0.timestamp < $1.timestamp }?.id
                ?? snapshot.projects[projectIndex].latestEvent?.id
            guard let parentEventID else {
                throw WorkstateStorageError.invalidState("Project has no event to branch from")
            }

            var topic = snapshot.projects[projectIndex].topics[topicIndex]
            topic.status = .converted
            topic.confirmedAt = mutation.timestamp
            topic.updatedAt = mutation.timestamp
            topic.notes.append(
                ProjectTopicNote(
                    timestamp: mutation.timestamp,
                    kind: .confirmation,
                    title: input.kind == .decision ? "确认为项目方向" : "转为后续任务",
                    detail: detail,
                    sourceIDs: topic.sourceIDs
                )
            )

            switch input.kind {
            case .decision:
                let decision = DecisionRecord(
                    text: detail,
                    status: .confirmed,
                    rationale: "由议题 \(topic.title) 经用户在 Workstate 中正式确认",
                    sourceIDs: topic.sourceIDs
                )
                let event = ProjectEvent(
                    timestamp: mutation.timestamp,
                    title: title,
                    summary: detail,
                    kind: .decision,
                    loopStage: .confirmation,
                    parentEventIDs: [parentEventID],
                    decisions: [decision],
                    sourceIDs: topic.sourceIDs
                )
                snapshot.projects[projectIndex].context.acceptedDecisions.append(decision)
                snapshot.projects[projectIndex].events.append(event)
                topic.promotedDecisionID = decision.id
            case .task:
                let taskID = "topic-task-\(input.topicID)"
                guard snapshot.projects[projectIndex].task(id: taskID) == nil else {
                    throw WorkstateStorageError.invalidState("Topic task already exists: \(taskID)")
                }
                let task = TaskRecord(
                    id: taskID,
                    title: title,
                    objective: detail,
                    accent: snapshot.projects[projectIndex].accent,
                    currentStage: .intake,
                    startedAt: mutation.timestamp,
                    updatedAt: mutation.timestamp,
                    branchedFromEventID: parentEventID,
                    tags: ["议题转化"],
                    sourceIDs: topic.sourceIDs
                )
                let event = ProjectEvent(
                    taskID: taskID,
                    timestamp: mutation.timestamp,
                    title: title,
                    summary: detail,
                    kind: .taskStarted,
                    loopStage: .intake,
                    parentEventIDs: [parentEventID],
                    tags: ["议题转化"],
                    sourceIDs: topic.sourceIDs
                )
                snapshot.projects[projectIndex].tasks.append(task)
                snapshot.projects[projectIndex].events.append(event)
                topic.derivedTaskIDs.append(taskID)
            }
            snapshot.projects[projectIndex].topics[topicIndex] = topic
            touchProject(at: projectIndex, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func resolveTopic(_ input: ProjectTopicResolutionInput) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "topic.resolve",
            summary: input.topicID,
            projectID: input.projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(input.projectID, in: snapshot)
            guard let topicIndex = snapshot.projects[projectIndex].topics.firstIndex(where: {
                $0.id == input.topicID
            }) else {
                throw WorkstateStorageError.invalidState("Topic not found: \(input.topicID)")
            }
            guard snapshot.projects[projectIndex].topics[topicIndex].status == .captured
                    || snapshot.projects[projectIndex].topics[topicIndex].status == .discussing else {
                throw WorkstateStorageError.invalidState("Only open topics can be resolved")
            }

            var topic = snapshot.projects[projectIndex].topics[topicIndex]
            topic.status = .closed
            topic.resolution = input.resolution
            topic.confirmedAt = mutation.timestamp
            topic.updatedAt = mutation.timestamp
            topic.notes.append(
                ProjectTopicNote(
                    timestamp: mutation.timestamp,
                    kind: .confirmation,
                    title: input.resolution == .completed ? "确认完成" : "取消议题",
                    detail: input.resolution == .completed
                        ? "用户确认相关结果已经完成。"
                        : "用户确认不再继续处理该议题。",
                    sourceIDs: topic.sourceIDs
                )
            )
            snapshot.projects[projectIndex].topics[topicIndex] = topic
            touchProject(at: projectIndex, timestamp: mutation.timestamp, in: &snapshot)
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
        let eventID = input.eventID ?? "task-start-\(UUID().uuidString.lowercased())"
        let mutation = WorkspaceMutation(
            timestamp: input.timestamp ?? Date(),
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
    public func updateTask(
        id: String,
        update: TaskUpdate,
        timestamp: Date? = nil
    ) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            timestamp: timestamp ?? Date(),
            kind: "task.update",
            summary: id,
            taskID: id
        )
        return try repository.update(mutation: mutation) { snapshot in
            let location = try taskLocation(id, in: snapshot)
            if let status = update.status { snapshot.projects[location.project].tasks[location.task].status = status }
            if let stage = update.stage { snapshot.projects[location.project].tasks[location.task].currentStage = stage }
            if let title = update.title { snapshot.projects[location.project].tasks[location.task].title = title }
            if let objective = update.objective { snapshot.projects[location.project].tasks[location.task].objective = objective }
            snapshot.projects[location.project].tasks[location.task].updatedAt = mutation.timestamp
            if update.status == .completed || update.status == .abandoned {
                snapshot.projects[location.project].tasks[location.task].completedAt = mutation.timestamp
                if snapshot.projects[location.project].focusedTaskID == id {
                    snapshot.projects[location.project].focusedTaskID = nil
                }
            }
            touchProject(at: location.project, timestamp: mutation.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func reconcileWorklines(_ input: WorklineReconciliationInput) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "workline.reconcile",
            summary: "Reconciled \(input.worklines.count) worklines",
            projectID: input.projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(input.projectID, in: snapshot)
            var project = snapshot.projects[projectIndex]
            let knownEventIDs = Set(project.events.map(\.id))
            let assignedEventIDs = input.worklines.flatMap(\.eventIDs)
            guard Set(assignedEventIDs).count == assignedEventIDs.count else {
                throw WorkstateStorageError.invalidState("A reconciled event belongs to multiple worklines")
            }

            for workline in input.worklines {
                guard !workline.eventIDs.isEmpty else {
                    throw WorkstateStorageError.invalidState("Reconciled workline has no events: \(workline.id)")
                }
                guard knownEventIDs.contains(workline.branchedFromEventID) else {
                    throw WorkstateStorageError.missingEvent(workline.branchedFromEventID)
                }
                for eventID in workline.eventIDs where !knownEventIDs.contains(eventID) {
                    throw WorkstateStorageError.missingEvent(eventID)
                }
                if let mergeID = workline.mergedByEventID,
                   !workline.eventIDs.contains(mergeID) {
                    throw WorkstateStorageError.invalidState("Merge event is outside workline: \(workline.id)")
                }

                let eventIDSet = Set(workline.eventIDs)
                let orderedEvents = project.events
                    .filter { eventIDSet.contains($0.id) }
                    .sorted { $0.timestamp < $1.timestamp }
                let sourceIDs = Array(Set(orderedEvents.flatMap(\.sourceIDs))).sorted()
                let completedAt = workline.status == .completed
                    ? workline.mergedByEventID
                        .flatMap { mergeID in orderedEvents.first(where: { $0.id == mergeID })?.timestamp }
                        ?? orderedEvents.last?.timestamp
                    : nil
                let task = TaskRecord(
                    id: workline.id,
                    title: workline.title,
                    objective: workline.objective,
                    status: workline.status,
                    accent: workline.accent,
                    currentStage: workline.status == .completed
                        ? .completed
                        : orderedEvents.last?.loopStage ?? .intake,
                    startedAt: orderedEvents.first!.timestamp,
                    updatedAt: orderedEvents.last!.timestamp,
                    completedAt: completedAt,
                    branchedFromEventID: workline.branchedFromEventID,
                    mergedByEventID: workline.mergedByEventID,
                    tags: workline.tags,
                    sourceIDs: sourceIDs
                )
                if let taskIndex = project.tasks.firstIndex(where: { $0.id == workline.id }) {
                    project.tasks[taskIndex] = task
                } else {
                    project.tasks.append(task)
                }

                for (index, event) in orderedEvents.enumerated() {
                    guard let eventIndex = project.events.firstIndex(where: { $0.id == event.id }) else {
                        throw WorkstateStorageError.missingEvent(event.id)
                    }
                    project.events[eventIndex].taskID = workline.id
                    project.events[eventIndex].parentEventIDs = [
                        index == 0 ? workline.branchedFromEventID : orderedEvents[index - 1].id
                    ]
                }
            }

            for taskIndex in project.tasks.indices {
                let taskEvents = project.events
                    .filter { $0.taskID == project.tasks[taskIndex].id && $0.kind != .taskStarted }
                    .sorted { $0.timestamp < $1.timestamp }
                guard let latest = taskEvents.last else { continue }
                project.tasks[taskIndex].updatedAt = latest.timestamp
                if project.tasks[taskIndex].status != .completed {
                    project.tasks[taskIndex].currentStage = latest.loopStage
                }
            }
            let latestTimestamp = project.events.map(\.timestamp).max() ?? mutation.timestamp
            project.updatedAt = latestTimestamp
            project.lastActivityAt = latestTimestamp
            snapshot.projects[projectIndex] = project
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
                timestamp: input.timestamp ?? mutation.timestamp,
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
                snapshot.projects[projectIndex].tasks[taskIndex].updatedAt = event.timestamp
                if input.kind == .completed {
                    snapshot.projects[projectIndex].tasks[taskIndex].status = .completed
                    snapshot.projects[projectIndex].tasks[taskIndex].completedAt = event.timestamp
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
                snapshot.projects[projectIndex].tasks[taskIndex].completedAt = event.timestamp
                snapshot.projects[projectIndex].tasks[taskIndex].mergedByEventID = eventID
                if snapshot.projects[projectIndex].focusedTaskID == mergeTaskID {
                    snapshot.projects[projectIndex].focusedTaskID = nil
                }
            }
            touchProject(at: projectIndex, timestamp: event.timestamp, in: &snapshot)
        }
    }

    @discardableResult
    public func focusTask(
        projectID: String,
        taskID: String?
    ) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "task.focus",
            summary: taskID.map { "Focused \($0)" } ?? "Cleared project focus",
            projectID: projectID,
            taskID: taskID
        )
        return try repository.update(mutation: mutation) { snapshot in
            let projectIndex = try projectIndex(projectID, in: snapshot)
            if let taskID {
                guard let task = snapshot.projects[projectIndex].task(id: taskID) else {
                    throw WorkstateStorageError.missingTask(taskID)
                }
                guard task.status == .active else {
                    throw WorkstateStorageError.invalidState("Cannot focus an inactive workline: \(taskID)")
                }
            }
            snapshot.projects[projectIndex].focusedTaskID = taskID
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
