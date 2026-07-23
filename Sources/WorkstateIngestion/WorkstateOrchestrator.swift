import Foundation
import WorkstateCore

public struct OrchestrationSummary: Sendable {
    public var processed: Int
    public var changed: Int
    public var ignored: Int
    public var agentRuns: Int
    public var failed: Int

    public init(processed: Int = 0, changed: Int = 0, ignored: Int = 0, agentRuns: Int = 0, failed: Int = 0) {
        self.processed = processed
        self.changed = changed
        self.ignored = ignored
        self.agentRuns = agentRuns
        self.failed = failed
    }
}

public struct WorkstateOrchestrator: Sendable {
    public let service: WorkstateService
    public let scanner: CodexSessionScanner
    public let runtime: AgentRuntimeClient

    public init(
        service: WorkstateService = .init(),
        scanner: CodexSessionScanner = .init(),
        runtime: AgentRuntimeClient = .init()
    ) {
        self.service = service
        self.scanner = scanner
        self.runtime = runtime
    }

    public func process(_ segments: [SessionSegment]) throws -> OrchestrationSummary {
        var summary = OrchestrationSummary()

        for segment in segments {
            var record = try scanner.processingRecord(segmentID: segment.id)
            if record.stage == .completed {
                try scanner.markProcessed(segmentIDs: [segment.id])
                summary.processed += 1
                continue
            }
            if record.stage == .failed {
                summary.failed += 1
                continue
            }
            if record.stage == .routing || record.stage == .stewarding || record.stage == .applying {
                try scanner.failProcessing(
                    segmentID: segment.id,
                    failedStage: record.stage,
                    error: "Processing was interrupted; explicit requeue is required"
                )
                summary.failed += 1
                continue
            }

            do {
                let workspace = try service.snapshot()
                let route: RouteResult
                if let persisted = record.route {
                    route = persisted
                } else {
                    try scanner.beginProcessing(segmentID: segment.id, stage: .routing)
                    route = try runtime.route(segment: segment, workspace: workspace, scanner: scanner)
                    summary.agentRuns += 1
                    try scanner.recordRouteResult(segmentID: segment.id, route: route)
                    record = try scanner.processingRecord(segmentID: segment.id)
                }

                if route.action == "ignore" {
                    summary.ignored += 1
                    try scanner.completeProcessing(segmentID: segment.id)
                    try scanner.markProcessed(segmentIDs: [segment.id])
                    summary.processed += 1
                    continue
                }

                let project: ProjectRecord
                switch route.action {
                case "continue_previous", "switch_project":
                    if route.action == "continue_previous" {
                        guard try scanner.routeBinding(threadID: segment.threadID)?.projectID == route.projectId else {
                            throw WorkstateStorageError.invalidState("Router continued a project without a matching prior route")
                        }
                    }
                    guard let existing = workspace.project(id: route.projectId) else {
                        throw WorkstateStorageError.missingProject(route.projectId)
                    }
                    project = existing
                case "new_project":
                    project = try createProject(route: route, segment: segment, workspace: workspace)
                default:
                    throw WorkstateStorageError.invalidState("Unknown route action: \(route.action)")
                }

                let result: StewardResult
                if let persisted = record.steward {
                    result = persisted
                } else {
                    try scanner.beginProcessing(segmentID: segment.id, stage: .stewarding)
                    result = try runtime.steward(segment: segment, project: project, scanner: scanner)
                    summary.agentRuns += 1
                    try scanner.recordStewardResult(segmentID: segment.id, steward: result)
                }

                try scanner.beginProcessing(segmentID: segment.id, stage: .applying)
                try apply(result, segment: segment, project: project)
                if result.classification == "ordinary_delta" {
                    summary.changed += 1
                } else {
                    summary.ignored += 1
                }
                try scanner.recordRoute(
                    threadID: segment.threadID,
                    turnID: segment.turnID,
                    projectID: project.id
                )
                try scanner.completeProcessing(segmentID: segment.id)
                try scanner.markProcessed(segmentIDs: [segment.id])
                summary.processed += 1
            } catch {
                let currentStage = (try? scanner.processingRecord(segmentID: segment.id).stage) ?? .queued
                try? scanner.failProcessing(
                    segmentID: segment.id,
                    failedStage: currentStage,
                    error: error.localizedDescription
                )
                summary.failed += 1
            }
        }

        return summary
    }

    public func processBacklog(_ segments: [SessionSegment]) throws -> OrchestrationSummary {
        guard segments.count > 1 else { return try process(segments) }
        var summary = OrchestrationSummary()
        let eligible = try segments.filter {
            try scanner.processingRecord(segmentID: $0.id).stage == .queued
        }
        let resumable = segments.filter { segment in
            !eligible.contains(where: { $0.id == segment.id })
        }
        if !resumable.isEmpty {
            let resumed = try process(resumable)
            summary = summary.adding(resumed)
        }
        guard !eligible.isEmpty else { return summary }

        let workspace = try service.snapshot()
        var decisions: [BatchRouteDecision] = []
        var unresolved: [SessionSegment] = []
        for segment in eligible {
            if let projectID = try scanner.routeBinding(threadID: segment.threadID)?.projectID,
               let project = workspace.project(id: projectID) {
                let decision = BatchRouteDecision(
                    segmentId: segment.id,
                    action: "continue_previous",
                    projectId: projectID,
                    projectName: project.name,
                    projectSummary: project.context.currentSummary,
                    confidence: 1,
                    reason: "Reused the existing thread route"
                )
                decisions.append(decision)
                try scanner.recordRouteResult(
                    segmentID: segment.id,
                    route: decision.routeResult
                )
            } else {
                unresolved.append(segment)
            }
        }
        for chunk in unresolved.chunked(maximumCount: 6) {
            do {
                let chunkDecisions = try runtime.routeBatch(
                    segments: chunk,
                    workspace: workspace,
                    routeHints: [:],
                    scanner: scanner
                )
                summary.agentRuns += 1
                decisions.append(contentsOf: chunkDecisions)
                for decision in chunkDecisions {
                    try scanner.recordRouteResult(
                        segmentID: decision.segmentId,
                        route: decision.routeResult
                    )
                }
            } catch {
                for segment in chunk {
                    try? scanner.failProcessing(
                        segmentID: segment.id,
                        failedStage: .routing,
                        error: error.localizedDescription
                    )
                }
                summary.failed += chunk.count
            }
        }
        guard !decisions.isEmpty else { return summary }

        let segmentByID = Dictionary(
            eligible.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for decision in decisions where decision.action == "ignore" {
            try scanner.completeProcessing(segmentID: decision.segmentId)
            try scanner.markProcessed(segmentIDs: [decision.segmentId])
            summary.processed += 1
            summary.ignored += 1
        }

        let routed = decisions.compactMap { decision -> RoutedBacklogSegment? in
            guard decision.action != "ignore", let segment = segmentByID[decision.segmentId] else {
                return nil
            }
            return RoutedBacklogSegment(segment: segment, route: decision.routeResult)
        }
        for group in backlogGroups(routed) {
            do {
                let orderedSegments = group.map(\.segment).sorted { $0.timestamp < $1.timestamp }
                let route = group.last!.route
                let currentWorkspace = try service.snapshot()
                let project: ProjectRecord
                switch route.action {
                case "continue_previous", "switch_project":
                    if route.action == "continue_previous" {
                        guard try scanner.routeBinding(
                            threadID: orderedSegments.last!.threadID
                        )?.projectID == route.projectId else {
                            throw WorkstateStorageError.invalidState(
                                "Batch Router continued a project without a matching prior route"
                            )
                        }
                    }
                    guard let existing = currentWorkspace.project(id: route.projectId) else {
                        throw WorkstateStorageError.missingProject(route.projectId)
                    }
                    project = existing
                case "new_project":
                    project = try createProject(
                        route: route,
                        segment: orderedSegments.first!,
                        workspace: currentWorkspace
                    )
                default:
                    throw WorkstateStorageError.invalidState(
                        "Unknown backlog route action: \(route.action)"
                    )
                }
                for segment in orderedSegments {
                    try scanner.beginProcessing(segmentID: segment.id, stage: .stewarding)
                }
                let stewardDecisions: [BatchStewardDecision]
                if orderedSegments.count == 1 {
                    stewardDecisions = [
                        BatchStewardDecision(
                            segmentId: orderedSegments[0].id,
                            result: try runtime.steward(
                                segment: orderedSegments[0],
                                project: project,
                                scanner: scanner
                            )
                        )
                    ]
                } else {
                    stewardDecisions = try runtime.stewardBatch(
                        segments: orderedSegments,
                        project: project,
                        scanner: scanner
                    )
                }
                summary.agentRuns += 1
                for decision in stewardDecisions {
                    guard let segment = orderedSegments.first(where: { $0.id == decision.segmentId }) else {
                        throw WorkstateStorageError.invalidState(
                            "Batch Steward returned an unknown segment"
                        )
                    }
                    try scanner.recordStewardResult(
                        segmentID: segment.id,
                        steward: decision.result
                    )
                    try scanner.beginProcessing(segmentID: segment.id, stage: .applying)
                    let currentProject = try service.snapshot().project(id: project.id) ?? project
                    try apply(decision.result, segment: segment, project: currentProject)
                    if decision.result.classification == "ordinary_delta" {
                        summary.changed += 1
                    } else {
                        summary.ignored += 1
                    }
                }
                let ids = orderedSegments.map(\.id)
                for item in group {
                    try scanner.recordRoute(
                        threadID: item.segment.threadID,
                        turnID: item.segment.turnID,
                        projectID: project.id
                    )
                    try scanner.completeProcessing(segmentID: item.segment.id)
                }
                try scanner.markProcessed(segmentIDs: ids)
                summary.processed += ids.count
            } catch {
                for item in group {
                    let stage = (try? scanner.processingRecord(segmentID: item.segment.id).stage)
                        ?? .queued
                    try? scanner.failProcessing(
                        segmentID: item.segment.id,
                        failedStage: stage,
                        error: error.localizedDescription
                    )
                }
                summary.failed += group.count
            }
        }
        return summary
    }

    private func apply(_ result: StewardResult, segment: SessionSegment, project: ProjectRecord) throws {
        guard result.classification != "no_change" else { return }
        let source = evidenceSource(segment)
        _ = try service.addSource(source)

        let taskID = try resolveWorkline(result, segment: segment, projectID: project.id, sourceID: source.id)
        let focusBeforeChange = try service.snapshot().project(id: project.id)?.focusedTaskID
        try applyFocusBeforeEvent(
            result,
            taskID: taskID,
            previousFocusedTaskID: focusBeforeChange,
            projectID: project.id,
            segment: segment,
            sourceID: source.id
        )

        let eventID = stableID(prefix: "delta", segment: segment)
        let currentProject = try service.snapshot().project(id: project.id)
        if currentProject?.event(id: eventID) != nil { return }
        guard let kind = EventKind(rawValue: result.kind),
              let stage = LoopStage(rawValue: result.stage),
              let delivery = DeliveryStage(rawValue: result.delivery) else {
            throw WorkstateStorageError.invalidState("Steward returned an unsupported state")
        }
        let completesWorkline = result.worklineAction == "complete_existing"
        _ = try service.appendEvent(
            EventInput(
                id: eventID,
                timestamp: segment.timestamp,
                projectID: project.id,
                taskID: taskID,
                mergeTaskID: completesWorkline ? taskID : nil,
                title: result.title,
                summary: result.summary,
                kind: kind,
                stage: stage,
                facts: result.facts,
                operations: OperationalContext(cwd: segment.cwd),
                delivery: DeliverySnapshot(stage: delivery),
                sourceIDs: [source.id]
            )
        )
        if result.worklineAction == "complete_existing" {
            try createCarryoverTopicIfNeeded(
                result,
                closedTaskID: taskID,
                projectID: project.id,
                segment: segment,
                sourceID: source.id
            )
        } else {
            _ = try service.appendOpenIssues(projectID: project.id, issues: result.openIssues)
        }
        try applyFocusAfterEvent(
            result,
            completedTaskID: taskID,
            previousFocusedTaskID: focusBeforeChange,
            projectID: project.id,
            timestamp: segment.timestamp
        )
    }

    private func applyFocusBeforeEvent(
        _ result: StewardResult,
        taskID: String?,
        previousFocusedTaskID: String?,
        projectID: String,
        segment: SessionSegment,
        sourceID: String
    ) throws {
        guard ["continue_existing", "start_new"].contains(result.worklineAction),
              let taskID else { return }
        if let previousFocusedTaskID,
           previousFocusedTaskID != taskID,
           result.isParallel != true,
           let previous = try service.snapshot().project(id: projectID)?.task(id: previousFocusedTaskID),
           previous.status == .active {
            guard result.closureDisposition != nil,
                  result.closureDisposition != "none" else {
                throw WorkstateStorageError.invalidState(
                    "A non-parallel focus switch must close or carry over the previous workline"
                )
            }
            try createCarryoverTopicIfNeeded(
                result,
                closedTaskID: previousFocusedTaskID,
                projectID: projectID,
                segment: segment,
                sourceID: sourceID
            )
            _ = try service.appendEvent(
                EventInput(
                    id: "closure-\(previousFocusedTaskID)-\(segment.turnID)",
                    timestamp: segment.timestamp,
                    projectID: projectID,
                    taskID: previousFocusedTaskID,
                    mergeTaskID: previousFocusedTaskID,
                    title: "\(previous.title)本轮结束",
                    summary: nonempty(result.carryoverSummary)
                        ?? "工作重心已切换，本轮工作线结束。",
                    kind: .completed,
                    stage: .completed,
                    sourceIDs: [sourceID]
                )
            )
        }
        _ = try service.focusTask(projectID: projectID, taskID: taskID)
    }

    private func applyFocusAfterEvent(
        _ result: StewardResult,
        completedTaskID: String?,
        previousFocusedTaskID: String?,
        projectID: String,
        timestamp: Date
    ) throws {
        guard result.worklineAction == "complete_existing" else { return }
        if let nextID = result.nextFocusedWorklineId, !nextID.isEmpty {
            guard nextID != completedTaskID,
                  let next = try service.snapshot().project(id: projectID)?.task(id: nextID) else {
                throw WorkstateStorageError.invalidState("Steward returned an invalid next focused workline")
            }
            if next.status == .waiting || next.status == .parked {
                _ = try service.updateTask(
                    id: nextID,
                    update: TaskUpdate(status: .active),
                    timestamp: timestamp
                )
            }
            _ = try service.focusTask(projectID: projectID, taskID: nextID)
        } else if previousFocusedTaskID == completedTaskID {
            _ = try service.focusTask(projectID: projectID, taskID: nil)
        }
    }

    private func createCarryoverTopicIfNeeded(
        _ result: StewardResult,
        closedTaskID: String?,
        projectID: String,
        segment: SessionSegment,
        sourceID: String
    ) throws {
        guard let closedTaskID else { return }
        let rawDisposition = result.closureDisposition ?? "completed"
        guard rawDisposition != "completed" else { return }
        guard let disposition = ProjectTopicDisposition(stewardValue: rawDisposition) else {
            throw WorkstateStorageError.invalidState(
                "Steward returned an unsupported workline closure disposition"
            )
        }
        guard let task = try service.snapshot().project(id: projectID)?.task(id: closedTaskID) else {
            throw WorkstateStorageError.missingTask(closedTaskID)
        }
        let questions = result.carryoverQuestions ?? result.openIssues
        let summary = nonempty(result.carryoverSummary) ?? task.objective
        let title = nonempty(result.carryoverTitle) ?? task.title
        _ = try service.upsertTopic(
            projectID: projectID,
            input: ProjectTopicUpdateInput(
                id: "carryover-\(closedTaskID)-\(segment.turnID)",
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
                openQuestions: questions,
                note: ProjectTopicNote(
                    timestamp: segment.timestamp,
                    kind: .statusChange,
                    title: "由工作线转入议题",
                    detail: summary,
                    sourceIDs: [sourceID]
                ),
                sourceIDs: [sourceID]
            )
        )
    }

    private func resolveWorkline(
        _ result: StewardResult,
        segment: SessionSegment,
        projectID: String,
        sourceID: String
    ) throws -> String? {
        let snapshot = try service.snapshot()
        guard let project = snapshot.project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }

        switch result.worklineAction {
        case "none":
            guard result.worklineId.isEmpty else {
                throw WorkstateStorageError.invalidState("A no-workline delta returned a workline id")
            }
            return nil
        case "continue_existing", "complete_existing", "resume_existing":
            guard project.task(id: result.worklineId) != nil else {
                throw WorkstateStorageError.missingTask(result.worklineId)
            }
            if result.worklineAction == "resume_existing" {
                _ = try service.updateTask(
                    id: result.worklineId,
                    update: TaskUpdate(status: .active, stage: LoopStage(rawValue: result.stage))
                )
            }
            return result.worklineId
        case "start_new":
            guard !result.worklineId.isEmpty,
                  !result.worklineTitle.isEmpty,
                  !result.worklineObjective.isEmpty else {
                throw WorkstateStorageError.invalidState("A new workline requires id, title, and objective")
            }
            guard project.task(id: result.worklineId) == nil else {
                throw WorkstateStorageError.invalidState("New workline already exists: \(result.worklineId)")
            }
            let branchEventID = try branchEventID(
                parentWorklineID: result.branchFromWorklineId,
                project: project,
                before: segment.timestamp
            )
            _ = try service.startTask(
                TaskStartInput(
                    projectID: projectID,
                    id: result.worklineId,
                    title: result.worklineTitle,
                    objective: result.worklineObjective,
                    accent: accent(for: result.worklineId),
                    stage: LoopStage(rawValue: result.stage) ?? .intake,
                    branchedFromEventID: branchEventID,
                    sourceIDs: [sourceID],
                    timestamp: segment.timestamp,
                    eventID: stableID(prefix: "task-start", segment: segment)
                )
            )
            return result.worklineId
        default:
            throw WorkstateStorageError.invalidState("Unknown workline action: \(result.worklineAction)")
        }
    }

    private func branchEventID(
        parentWorklineID: String,
        project: ProjectRecord,
        before timestamp: Date
    ) throws -> String {
        let eligible = project.events
            .filter { $0.timestamp <= timestamp && $0.kind != .taskStarted }
            .sorted { $0.timestamp < $1.timestamp }
        if parentWorklineID.isEmpty {
            guard let event = eligible.last(where: { $0.taskID == nil }) ?? eligible.last else {
                throw WorkstateStorageError.invalidState("Cannot start a workline without a branch event")
            }
            return event.id
        }
        guard let parent = project.task(id: parentWorklineID) else {
            throw WorkstateStorageError.missingTask(parentWorklineID)
        }
        return eligible.last(where: { $0.taskID == parentWorklineID })?.id ?? parent.branchedFromEventID
    }

    private func accent(for id: String) -> ProjectAccent {
        let accents: [ProjectAccent] = [.blue, .green, .amber, .violet, .cyan, .red]
        let value = id.utf8.reduce(0) { ($0 + Int($1)) % accents.count }
        return accents[value]
    }

    private func createProject(
        route: RouteResult,
        segment: SessionSegment,
        workspace: WorkspaceSnapshot
    ) throws -> ProjectRecord {
        guard !route.projectId.isEmpty, !route.projectName.isEmpty, !route.projectSummary.isEmpty else {
            throw WorkstateStorageError.invalidState("Router returned an incomplete new project")
        }
        if let existing = workspace.project(id: route.projectId) {
            return existing
        }
        let source = evidenceSource(segment)
        _ = try service.addSource(source)
        let index = workspace.projects.count
        let accent = ProjectAccent.allCases[index % ProjectAccent.allCases.count]
        _ = try service.createProject(
            ProjectCreateInput(
                id: route.projectId,
                name: route.projectName,
                summary: route.projectSummary,
                purpose: route.projectSummary,
                accent: accent,
                position: GraphPosition(
                    x: 180 + Double(index % 2) * 260,
                    y: 180 + Double(index / 2) * 180
                ),
                sourceIDs: [source.id]
            )
        )
        guard let created = try service.snapshot().project(id: route.projectId) else {
            throw WorkstateStorageError.missingProject(route.projectId)
        }
        return created
    }

    private func evidenceSource(_ segment: SessionSegment) -> SourceReference {
        SourceReference(
            id: stableID(prefix: "source", segment: segment),
            kind: "conversation",
            label: "Codex · \(segment.turnID)",
            locator: segment.sourcePath,
            threadID: segment.threadID,
            turnIDs: segment.relatedTurnIDs ?? [segment.turnID],
            excerpt: [
                ConversationMessage(role: "user", text: segment.userText, timestamp: segment.timestamp),
                ConversationMessage(role: "assistant", text: segment.assistantText, timestamp: segment.timestamp)
            ],
            contentHash: segment.id
        )
    }

    private func stableID(prefix: String, segment: SessionSegment) -> String {
        "\(prefix)-\(segment.threadID)-\(segment.turnID)"
    }

    private func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func backlogGroups(
        _ routed: [RoutedBacklogSegment]
    ) -> [[RoutedBacklogSegment]] {
        let ordered = routed.sorted { $0.segment.timestamp < $1.segment.timestamp }
        var groups: [[RoutedBacklogSegment]] = []
        for item in ordered {
            if let last = groups.indices.last,
               let previous = groups[last].last,
               previous.route.projectId == item.route.projectId,
               previous.segment.threadID == item.segment.threadID {
                groups[last].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups
    }

}

private extension ProjectTopicDisposition {
    init?(stewardValue: String) {
        switch stewardValue {
        case "future_decision":
            self = .futureDecision
        case "awaiting_verification":
            self = .awaitingVerification
        default:
            return nil
        }
    }
}

private struct RoutedBacklogSegment {
    var segment: SessionSegment
    var route: RouteResult
}

private extension OrchestrationSummary {
    func adding(_ other: OrchestrationSummary) -> OrchestrationSummary {
        OrchestrationSummary(
            processed: processed + other.processed,
            changed: changed + other.changed,
            ignored: ignored + other.ignored,
            agentRuns: agentRuns + other.agentRuns,
            failed: failed + other.failed
        )
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        precondition(maximumCount > 0)
        return stride(from: 0, to: count, by: maximumCount).map { start in
            Array(self[start..<Swift.min(start + maximumCount, count)])
        }
    }
}
