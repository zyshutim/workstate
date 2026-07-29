import Foundation

public enum IngestionWorklineAction: String, Codable, Sendable {
    case none
    case continueExisting
    case startNew
    case completeExisting
}

public enum IngestionClosureDisposition: String, Codable, Sendable {
    case none
    case completed
    case futureDecision
    case awaitingVerification
}

public struct IngestionUnderstandingMutation: Codable, Sendable {
    public var id: String
    public var text: String
    public var status: EvidenceStatus

    public init(id: String, text: String, status: EvidenceStatus) {
        self.id = id
        self.text = text
        self.status = status
    }
}

public struct IngestionDecisionMutation: Codable, Sendable {
    public var id: String
    public var text: String
    public var rationale: String

    public init(id: String, text: String, rationale: String) {
        self.id = id
        self.text = text
        self.rationale = rationale
    }
}

public struct IngestionTopicMutation: Codable, Sendable {
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
        disposition: ProjectTopicDisposition,
        currentUnderstanding: String,
        proposedDirection: String,
        deferredReason: String,
        revisitTrigger: String,
        openQuestions: [String],
        note: ProjectTopicNote?,
        sourceIDs: [String]
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

public struct IngestionContextPatch: Codable, Sendable {
    public var currentSummary: String
    public var revisionID: String
    public var revisionTitle: String
    public var revisionSummary: String
    public var revisionStatus: EvidenceStatus
    public var changes: [String]
    public var understandingUpserts: [IngestionUnderstandingMutation]
    public var supersededUnderstandingIDs: [String]
    public var decisionUpserts: [IngestionDecisionMutation]
    public var supersededDecisionIDs: [String]
    public var forbiddenDirectionAdditions: [String]
    public var forbiddenDirectionRemovals: [String]

    public init(
        currentSummary: String = "",
        revisionID: String,
        revisionTitle: String,
        revisionSummary: String,
        revisionStatus: EvidenceStatus,
        changes: [String] = [],
        understandingUpserts: [IngestionUnderstandingMutation] = [],
        supersededUnderstandingIDs: [String] = [],
        decisionUpserts: [IngestionDecisionMutation] = [],
        supersededDecisionIDs: [String] = [],
        forbiddenDirectionAdditions: [String] = [],
        forbiddenDirectionRemovals: [String] = []
    ) {
        self.currentSummary = currentSummary
        self.revisionID = revisionID
        self.revisionTitle = revisionTitle
        self.revisionSummary = revisionSummary
        self.revisionStatus = revisionStatus
        self.changes = changes
        self.understandingUpserts = understandingUpserts
        self.supersededUnderstandingIDs = supersededUnderstandingIDs
        self.decisionUpserts = decisionUpserts
        self.supersededDecisionIDs = supersededDecisionIDs
        self.forbiddenDirectionAdditions = forbiddenDirectionAdditions
        self.forbiddenDirectionRemovals = forbiddenDirectionRemovals
    }

    public var isEmpty: Bool {
        currentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && understandingUpserts.isEmpty
            && supersededUnderstandingIDs.isEmpty
            && decisionUpserts.isEmpty
            && supersededDecisionIDs.isEmpty
            && forbiddenDirectionAdditions.isEmpty
            && forbiddenDirectionRemovals.isEmpty
    }
}

public struct IngestionProjectChange: Codable, Sendable {
    public var id: String
    public var projectID: String
    public var timestamp: Date
    public var sources: [SourceReference]
    public var title: String
    public var summary: String
    public var kind: EventKind
    public var stage: LoopStage
    public var delivery: DeliveryStage
    public var facts: [String]
    public var operations: OperationalContext
    public var worklineAction: IngestionWorklineAction
    public var worklineID: String
    public var worklineTitle: String
    public var worklineObjective: String
    public var branchFromWorklineID: String
    public var isParallel: Bool
    public var nextFocusedWorklineID: String
    public var closureDisposition: IngestionClosureDisposition
    public var carryoverTitle: String
    public var carryoverSummary: String
    public var carryoverQuestions: [String]
    public var taskStartEventID: String
    public var contextPatch: IngestionContextPatch?
    public var topicUpserts: [IngestionTopicMutation]

    public init(
        id: String,
        projectID: String,
        timestamp: Date,
        sources: [SourceReference],
        title: String,
        summary: String,
        kind: EventKind,
        stage: LoopStage,
        delivery: DeliveryStage,
        facts: [String],
        operations: OperationalContext,
        worklineAction: IngestionWorklineAction,
        worklineID: String,
        worklineTitle: String,
        worklineObjective: String,
        branchFromWorklineID: String,
        isParallel: Bool,
        nextFocusedWorklineID: String,
        closureDisposition: IngestionClosureDisposition,
        carryoverTitle: String,
        carryoverSummary: String,
        carryoverQuestions: [String],
        taskStartEventID: String,
        contextPatch: IngestionContextPatch?,
        topicUpserts: [IngestionTopicMutation] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.timestamp = timestamp
        self.sources = sources
        self.title = title
        self.summary = summary
        self.kind = kind
        self.stage = stage
        self.delivery = delivery
        self.facts = facts
        self.operations = operations
        self.worklineAction = worklineAction
        self.worklineID = worklineID
        self.worklineTitle = worklineTitle
        self.worklineObjective = worklineObjective
        self.branchFromWorklineID = branchFromWorklineID
        self.isParallel = isParallel
        self.nextFocusedWorklineID = nextFocusedWorklineID
        self.closureDisposition = closureDisposition
        self.carryoverTitle = carryoverTitle
        self.carryoverSummary = carryoverSummary
        self.carryoverQuestions = carryoverQuestions
        self.taskStartEventID = taskStartEventID
        self.contextPatch = contextPatch
        self.topicUpserts = topicUpserts
    }
}

public extension WorkstateService {
    @discardableResult
    func applyIngestionChanges(
        projectID: String,
        changes: [IngestionProjectChange]
    ) throws -> WorkspaceSnapshot {
        guard !changes.isEmpty else { return try repository.load() }
        guard changes.allSatisfy({ $0.projectID == projectID }) else {
            throw WorkstateStorageError.invalidState("One ingestion transaction cannot span projects")
        }
        return try applyIngestionBatch(changes)
    }

    @discardableResult
    func applyIngestionBatch(
        _ changes: [IngestionProjectChange],
        newProjects: [ProjectCreateInput] = []
    ) throws -> WorkspaceSnapshot {
        guard !changes.isEmpty || !newProjects.isEmpty else { return try repository.load() }
        let newProjectIDs = Set(newProjects.map(\.id))
        guard newProjectIDs.count == newProjects.count else {
            throw WorkstateStorageError.invalidState(
                "One ingestion batch cannot create the same project twice"
            )
        }
        let ordered = changes.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp == rhs.element.timestamp {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.timestamp < rhs.element.timestamp
            }
            .map(\.element)
        let timestamp = ordered.map(\.timestamp).max() ?? Date()
        let projectStartTimestamps = Dictionary(grouping: ordered, by: \.projectID)
            .mapValues { projectChanges in
                projectChanges.map(\.timestamp).min()!
            }
        let affectedProjectIDs = Set(ordered.map(\.projectID)).union(newProjectIDs)
        let mutation = WorkspaceMutation(
            timestamp: timestamp,
            kind: "ingestion.apply",
            summary: "Applied \(ordered.count) project changes",
            projectID: affectedProjectIDs.count == 1 ? affectedProjectIDs.first : nil
        )

        return try repository.update(mutation: mutation) { snapshot in
            for input in newProjects {
                guard !input.id.isEmpty,
                      !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !input.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw WorkstateStorageError.invalidState(
                        "A new ingestion project requires id, name, and summary"
                    )
                }
                if let existing = snapshot.project(id: input.id) {
                    guard existing.name == input.name else {
                        throw WorkstateStorageError.invalidState(
                            "A recovered ingestion project conflicts with existing project \(input.id)"
                        )
                    }
                    continue
                }
                let startID = "project-start-\(input.id)"
                let projectTimestamp = projectStartTimestamps[input.id] ?? timestamp
                snapshot.projects.append(
                    ProjectRecord(
                        id: input.id,
                        name: input.name,
                        summary: input.summary,
                        status: input.status,
                        accent: input.accent,
                        createdAt: projectTimestamp,
                        updatedAt: projectTimestamp,
                        lastActivityAt: projectTimestamp,
                        graphPosition: input.position,
                        context: ProjectContext(
                            currentSummary: input.summary,
                            purpose: input.purpose
                        ),
                        events: [
                            ProjectEvent(
                                id: startID,
                                timestamp: projectTimestamp,
                                title: "项目建立",
                                summary: input.summary,
                                kind: .projectStarted,
                                loopStage: .intake,
                                sourceIDs: input.sourceIDs
                            )
                        ],
                        sourceIDs: input.sourceIDs
                    )
                )
            }
            for change in ordered {
                guard let projectIndex = snapshot.projects.firstIndex(where: {
                    $0.id == change.projectID
                }) else {
                    throw WorkstateStorageError.missingProject(change.projectID)
                }
                try apply(change, to: projectIndex, in: &snapshot)
            }
        }
    }

    private func apply(
        _ change: IngestionProjectChange,
        to projectIndex: Int,
        in snapshot: inout WorkspaceSnapshot
    ) throws {
        guard !change.id.isEmpty,
              !change.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !change.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState("An ingestion change requires id, title, and summary")
        }
        if snapshot.projects[projectIndex].event(id: change.id) != nil {
            return
        }

        for source in change.sources {
            if let sourceIndex = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
                snapshot.sources[sourceIndex] = source
            } else {
                snapshot.sources.append(source)
            }
        }
        let sourceIDs = Array(Set(change.sources.map(\.id))).sorted()
        var project = snapshot.projects[projectIndex]
        let taskID = try resolveWorkline(
            for: change,
            sourceIDs: sourceIDs,
            project: &project
        )

        if let taskID,
           change.worklineAction == .continueExisting || change.worklineAction == .startNew {
            guard let task = project.task(id: taskID), task.status == .active else {
                throw WorkstateStorageError.invalidState("Cannot focus an inactive workline: \(taskID)")
            }
            project.focusedTaskID = taskID
        }

        let decisions = try applyContextPatch(
            change.contextPatch,
            timestamp: change.timestamp,
            sourceIDs: sourceIDs,
            project: &project
        )
        let parents = try eventParents(taskID: taskID, in: project)
        let event = ProjectEvent(
            id: change.id,
            taskID: taskID,
            timestamp: change.timestamp,
            title: change.title,
            summary: change.summary,
            kind: change.kind,
            loopStage: change.stage,
            parentEventIDs: parents,
            facts: change.facts,
            decisions: decisions,
            operations: change.operations,
            delivery: DeliverySnapshot(
                stage: change.delivery,
                verifiedAt: verifiedAt(for: change.delivery, timestamp: change.timestamp)
            ),
            sourceIDs: sourceIDs
        )
        project.events.append(event)

        if let taskID,
           let taskIndex = project.tasks.firstIndex(where: { $0.id == taskID }) {
            project.tasks[taskIndex].currentStage = change.stage
            project.tasks[taskIndex].updatedAt = change.timestamp
            project.tasks[taskIndex].sourceIDs = Array(
                Set(project.tasks[taskIndex].sourceIDs + sourceIDs)
            ).sorted()
            if change.worklineAction == .completeExisting || change.kind == .completed {
                project.tasks[taskIndex].status = .completed
                project.tasks[taskIndex].currentStage = .completed
                project.tasks[taskIndex].completedAt = change.timestamp
                project.tasks[taskIndex].mergedByEventID = change.id
                try createCarryoverTopicIfNeeded(
                    task: project.tasks[taskIndex],
                    change: change,
                    sourceIDs: sourceIDs,
                    project: &project
                )
                if project.focusedTaskID == taskID {
                    project.focusedTaskID = nil
                }
            }
        }

        if change.worklineAction == .completeExisting {
            if !change.nextFocusedWorklineID.isEmpty {
                guard change.nextFocusedWorklineID != taskID,
                      let nextIndex = project.tasks.firstIndex(where: {
                          $0.id == change.nextFocusedWorklineID
                      }),
                      project.tasks[nextIndex].status == .active else {
                    throw WorkstateStorageError.invalidState(
                        "Ingestion returned an invalid next focused workline"
                    )
                }
                project.focusedTaskID = change.nextFocusedWorklineID
            } else if project.focusedTaskID == taskID {
                project.focusedTaskID = nil
            }
        }

        for topicMutation in change.topicUpserts {
            try applyTopicMutation(
                topicMutation,
                timestamp: change.timestamp,
                project: &project
            )
        }

        project.sourceIDs = Array(Set(project.sourceIDs + sourceIDs)).sorted()
        project.updatedAt = max(project.updatedAt, change.timestamp)
        project.lastActivityAt = max(project.lastActivityAt, change.timestamp)
        snapshot.projects[projectIndex] = project
    }

    private func applyTopicMutation(
        _ input: IngestionTopicMutation,
        timestamp: Date,
        project: inout ProjectRecord
    ) throws {
        guard !input.id.isEmpty,
              !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.currentUnderstanding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState(
                "Topic id, title, and current understanding are required"
            )
        }
        guard input.status == .captured || input.status == .discussing else {
            throw WorkstateStorageError.invalidState(
                "Automatic topic updates cannot confirm or close a topic"
            )
        }
        if let topicIndex = project.topics.firstIndex(where: { $0.id == input.id }) {
            guard project.topics[topicIndex].status != .converted,
                  project.topics[topicIndex].status != .closed else {
                throw WorkstateStorageError.invalidState(
                    "Confirmed or closed topics cannot be overwritten by Owner"
                )
            }
            var topic = project.topics[topicIndex]
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
            topic.updatedAt = timestamp
            project.topics[topicIndex] = topic
        } else {
            project.topics.append(
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
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }
    }

    private func resolveWorkline(
        for change: IngestionProjectChange,
        sourceIDs: [String],
        project: inout ProjectRecord
    ) throws -> String? {
        switch change.worklineAction {
        case .none:
            guard change.worklineID.isEmpty else {
                throw WorkstateStorageError.invalidState("A project-wide delta cannot name a workline")
            }
            return nil
        case .continueExisting, .completeExisting:
            guard let task = project.task(id: change.worklineID) else {
                throw WorkstateStorageError.missingTask(change.worklineID)
            }
            guard task.status == .active else {
                throw WorkstateStorageError.invalidState(
                    "Cannot advance an inactive workline: \(change.worklineID)"
                )
            }
            if change.worklineAction == .completeExisting,
               change.closureDisposition == .none {
                throw WorkstateStorageError.invalidState(
                    "A completed workline requires a closure disposition"
                )
            }
            return change.worklineID
        case .startNew:
            guard !change.worklineID.isEmpty,
                  !change.worklineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !change.worklineObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !change.taskStartEventID.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "A new workline requires id, title, objective, and start event"
                )
            }
            guard project.task(id: change.worklineID) == nil,
                  project.event(id: change.taskStartEventID) == nil else {
                throw WorkstateStorageError.invalidState(
                    "New workline already exists: \(change.worklineID)"
                )
            }
            let branchEventID = try branchEventID(
                parentWorklineID: change.branchFromWorklineID,
                before: change.timestamp,
                project: project
            )
            let task = TaskRecord(
                id: change.worklineID,
                title: change.worklineTitle,
                objective: change.worklineObjective,
                accent: ingestionAccent(for: change.worklineID),
                currentStage: change.stage,
                startedAt: change.timestamp,
                updatedAt: change.timestamp,
                branchedFromEventID: branchEventID,
                sourceIDs: sourceIDs
            )
            project.tasks.append(task)
            project.events.append(
                ProjectEvent(
                    id: change.taskStartEventID,
                    taskID: change.worklineID,
                    timestamp: change.timestamp,
                    title: change.worklineTitle,
                    summary: change.worklineObjective,
                    kind: .taskStarted,
                    loopStage: change.stage,
                    parentEventIDs: [branchEventID],
                    sourceIDs: sourceIDs
                )
            )
            return change.worklineID
        }
    }

    private func applyContextPatch(
        _ patch: IngestionContextPatch?,
        timestamp: Date,
        sourceIDs: [String],
        project: inout ProjectRecord
    ) throws -> [DecisionRecord] {
        guard let patch, !patch.isEmpty else { return [] }
        guard !patch.revisionID.isEmpty,
              !patch.revisionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !patch.revisionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              patch.revisionStatus == .observed || patch.revisionStatus == .confirmed,
              !project.context.revisions.contains(where: { $0.id == patch.revisionID }) else {
            throw WorkstateStorageError.invalidState(
                "A context patch requires a unique revision with observed or confirmed authority"
            )
        }

        for statementID in patch.supersededUnderstandingIDs {
            guard let index = project.context.understanding.firstIndex(where: {
                $0.id == statementID
            }) else {
                throw WorkstateStorageError.invalidState(
                    "Cannot supersede unknown understanding: \(statementID)"
                )
            }
            project.context.understanding[index].status = .superseded
            project.context.understanding[index].updatedAt = timestamp
            project.context.understanding[index].sourceIDs = Array(
                Set(project.context.understanding[index].sourceIDs + sourceIDs)
            ).sorted()
        }

        for item in patch.understandingUpserts {
            guard !item.id.isEmpty,
                  !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.status == .observed || item.status == .confirmed || item.status == .inferred else {
                throw WorkstateStorageError.invalidState("Invalid understanding upsert")
            }
            var statement = ContextStatement(
                id: item.id,
                text: item.text,
                status: item.status,
                updatedAt: timestamp,
                sourceIDs: sourceIDs
            )
            if let index = project.context.understanding.firstIndex(where: { $0.id == item.id }) {
                statement.sourceIDs = Array(
                    Set(project.context.understanding[index].sourceIDs + sourceIDs)
                ).sorted()
                project.context.understanding[index] = statement
            } else {
                project.context.understanding.append(statement)
            }
        }

        for decisionID in patch.supersededDecisionIDs {
            guard let index = project.context.acceptedDecisions.firstIndex(where: {
                $0.id == decisionID
            }) else {
                throw WorkstateStorageError.invalidState(
                    "Cannot supersede unknown decision: \(decisionID)"
                )
            }
            project.context.acceptedDecisions[index].status = .superseded
            project.context.acceptedDecisions[index].sourceIDs = Array(
                Set(project.context.acceptedDecisions[index].sourceIDs + sourceIDs)
            ).sorted()
        }

        var accepted: [DecisionRecord] = []
        for item in patch.decisionUpserts {
            guard !item.id.isEmpty,
                  !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkstateStorageError.invalidState("Invalid decision upsert")
            }
            var decision = DecisionRecord(
                id: item.id,
                text: item.text,
                status: .confirmed,
                rationale: item.rationale,
                sourceIDs: sourceIDs
            )
            if let index = project.context.acceptedDecisions.firstIndex(where: {
                $0.id == item.id
            }) {
                decision.sourceIDs = Array(
                    Set(project.context.acceptedDecisions[index].sourceIDs + sourceIDs)
                ).sorted()
                project.context.acceptedDecisions[index] = decision
            } else {
                project.context.acceptedDecisions.append(decision)
            }
            accepted.append(decision)
        }

        for value in patch.forbiddenDirectionRemovals {
            guard let index = project.context.forbiddenDirections.firstIndex(of: value) else {
                throw WorkstateStorageError.invalidState(
                    "Cannot remove unknown forbidden direction: \(value)"
                )
            }
            project.context.forbiddenDirections.remove(at: index)
        }
        for value in patch.forbiddenDirectionAdditions
        where !project.context.forbiddenDirections.contains(value) {
            project.context.forbiddenDirections.append(value)
        }

        let currentSummary = patch.currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentSummary.isEmpty {
            project.context.currentSummary = currentSummary
            project.summary = currentSummary
        }
        project.context.revisions.append(
            ContextRevision(
                id: patch.revisionID,
                timestamp: timestamp,
                title: patch.revisionTitle,
                summary: patch.revisionSummary,
                status: patch.revisionStatus,
                changes: patch.changes,
                sourceIDs: sourceIDs
            )
        )
        return accepted
    }

    private func createCarryoverTopicIfNeeded(
        task: TaskRecord,
        change: IngestionProjectChange,
        sourceIDs: [String],
        project: inout ProjectRecord
    ) throws {
        let disposition: ProjectTopicDisposition
        switch change.closureDisposition {
        case .none, .completed:
            return
        case .futureDecision:
            disposition = .futureDecision
        case .awaitingVerification:
            disposition = .awaitingVerification
        }
        let title = nonempty(change.carryoverTitle) ?? task.title
        let summary = nonempty(change.carryoverSummary) ?? task.objective
        let topicID = "carryover-\(task.id)-\(change.id)"
        guard project.topics.first(where: { $0.id == topicID }) == nil else { return }
        project.topics.append(
            ProjectTopic(
                id: topicID,
                title: title,
                summary: summary,
                status: .captured,
                kind: .product,
                disposition: disposition,
                currentUnderstanding: summary,
                proposedDirection: disposition == .awaitingVerification
                    ? "等待结果后确认是否真正完成。"
                    : "等待确认是否进入后续执行。",
                deferredReason: disposition == .awaitingVerification
                    ? "本轮执行已经结束，但结果或验收尚未确定。"
                    : "当前执行已经结束，未来是否继续尚未决定。",
                revisitTrigger: disposition == .awaitingVerification
                    ? "获得运行结果、外部反馈或用户验收时。"
                    : "用户确认推进时。",
                openQuestions: change.carryoverQuestions,
                notes: [
                    ProjectTopicNote(
                        id: "note-\(topicID)",
                        timestamp: change.timestamp,
                        kind: .statusChange,
                        title: "由工作线转入议题",
                        detail: summary,
                        sourceIDs: sourceIDs
                    )
                ],
                sourceIDs: sourceIDs,
                createdAt: change.timestamp,
                updatedAt: change.timestamp
            )
        )
    }

    private func eventParents(taskID: String?, in project: ProjectRecord) throws -> [String] {
        if let taskID {
            guard let task = project.task(id: taskID) else {
                throw WorkstateStorageError.missingTask(taskID)
            }
            return project.events.last(where: { $0.taskID == taskID })
                .map { [$0.id] }
                ?? [task.branchedFromEventID]
        }
        return project.events.last(where: { $0.taskID == nil }).map { [$0.id] } ?? []
    }

    private func branchEventID(
        parentWorklineID: String,
        before timestamp: Date,
        project: ProjectRecord
    ) throws -> String {
        let eligible = project.events
            .filter { $0.timestamp <= timestamp && $0.kind != .taskStarted }
            .sorted { $0.timestamp < $1.timestamp }
        if parentWorklineID.isEmpty {
            guard let event = eligible.last(where: { $0.taskID == nil }) ?? eligible.last else {
                throw WorkstateStorageError.invalidState(
                    "Cannot start a workline without a branch event"
                )
            }
            return event.id
        }
        guard let parent = project.task(id: parentWorklineID) else {
            throw WorkstateStorageError.missingTask(parentWorklineID)
        }
        return eligible.last(where: { $0.taskID == parentWorklineID })?.id
            ?? parent.branchedFromEventID
    }

    private func ingestionAccent(for id: String) -> ProjectAccent {
        let accents: [ProjectAccent] = [.blue, .green, .amber, .violet, .cyan, .red]
        let value = id.utf8.reduce(0) { ($0 + Int($1)) % accents.count }
        return accents[value]
    }

    private func verifiedAt(for delivery: DeliveryStage, timestamp: Date) -> Date? {
        switch delivery {
        case .unchanged, .changed:
            nil
        case .checked, .rendered, .userAccepted, .integrated, .published:
            timestamp
        }
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
