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

    private func apply(_ result: StewardResult, segment: SessionSegment, project: ProjectRecord) throws {
        guard result.classification != "no_change" else { return }
        let source = evidenceSource(segment)
        _ = try service.addSource(source)

        let taskID = try resolveWorkline(result, segment: segment, projectID: project.id, sourceID: source.id)

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
        _ = try service.appendOpenIssues(projectID: project.id, issues: result.openIssues)
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
            turnIDs: [segment.turnID],
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

}
