import Foundation
import WorkstateCore
import WorkstateIngestion
import WorkstateUI

@main
struct WorkstateChecks {
    @MainActor
    static func main() throws {
        try bootstrapGraphIntegrity()
        try legacyStateMigration()
        try projectPositionUpdate()
        try projectModelReplacement()
        try taskBranchAndMerge()
        try contextRevisionAuthority()
        try timelineLaneReuse()
        try projectTimelineHierarchy()
        try timelineSelectionHierarchy()
        try reviewResolutionAuthority()
        try sessionScannerIncremental()
        try agentDailyBudgetStopsBeforeInvocation()
        print("Workstate checks passed")
    }

    private static func bootstrapGraphIntegrity() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let snapshot = try repository.load()
            try require(snapshot.schemaVersion == 3, "schema version")
            try require(snapshot.projects.count == 3, "bootstrap project count")
            try require(snapshot.relations.count == 2, "bootstrap relation count")

            guard let multicam = snapshot.project(id: "reframe-multicam") else {
                throw CheckFailure.failed("multicam project")
            }
            try require(multicam.tasks.count == 4, "multicam tasks")
            try require(multicam.context.revisions.count == 4, "context revision history")
            try require(multicam.event(id: "mc-report-handoff") != nil, "handoff event")
            try require(
                multicam.event(id: "mc-source-merged")?.parentEventIDs.contains("mc-source-accepted") == true,
                "task merge parent"
            )
            try require(
                snapshot.relations.contains(where: {
                    $0.fromProjectID == "reframe-multicam" && $0.toProjectID == "reframe-report"
                }),
                "cross-project handoff"
            )
        }
    }

    private static func projectPositionUpdate() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let position = GraphPosition(x: 418, y: 276)
            _ = try service.updateProject(
                id: "reframe-multicam",
                update: ProjectUpdate(position: position)
            )
            let updated = try service.snapshot().project(id: "reframe-multicam")
            try require(updated?.graphPosition == position, "project graph position update")
        }
    }

    private static func projectModelReplacement() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            _ = try service.updateProjectModel(
                id: "reframe-multicam",
                update: ProjectModelUpdate(
                    currentSummary: "Canonical HEAD",
                    objectModel: ["Project", "Workline", "Delta"],
                    acceptedDecisions: [DecisionRecord(text: "Confirmed decision", status: .confirmed)],
                    forbiddenDirections: ["Do not infer acceptance"],
                    openIssues: ["Verify runtime"]
                )
            )
            let project = try service.snapshot().project(id: "reframe-multicam")
            try require(project?.summary == "Canonical HEAD", "project model updates graph summary")
            try require(project?.context.objectModel == ["Project", "Workline", "Delta"], "project object model replacement")
            try require(project?.context.acceptedDecisions.first?.text == "Confirmed decision", "project accepted decisions replacement")
            try require(project?.context.forbiddenDirections == ["Do not infer acceptance"], "project forbidden directions replacement")
            try require(project?.context.openIssues == ["Verify runtime"], "project open issues replacement")
        }
    }

    private static func legacyStateMigration() throws {
        try withFixture { repository in
            try FileManager.default.createDirectory(at: repository.paths.root, withIntermediateDirectories: true)
            try Data("{\"schemaVersion\":1}".utf8).write(to: repository.paths.state)
            try Data("legacy event\n".utf8).write(to: repository.paths.events)

            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let snapshot = try repository.load()
            let files = try FileManager.default.contentsOfDirectory(atPath: repository.paths.root.path)
            try require(snapshot.schemaVersion == 3, "migrated schema")
            try require(files.contains(where: { $0.hasPrefix("state-v1-backup-") }), "state backup")
            try require(files.contains(where: { $0.hasPrefix("events-v1-backup-") }), "events backup")
        }
    }

    private static func reviewResolutionAuthority() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let source = SourceReference(
                id: "review-source",
                kind: "conversation",
                label: "Review source",
                locator: "/tmp/source.jsonl",
                threadID: "thread",
                turnIDs: ["turn"],
                excerpt: [ConversationMessage(role: "user", text: "确认修改")]
            )
            _ = try service.addSource(source)
            _ = try service.upsertReview(
                ReviewItem(
                    id: "review",
                    kind: .understandingConflict,
                    projectID: "reframe-multicam",
                    title: "Understanding change",
                    summary: "Confirmed through review",
                    reason: "Conflicts with current HEAD",
                    previousValue: "Old",
                    proposedValue: "New",
                    sourceIDs: [source.id]
                )
            )
            _ = try service.resolveReview(id: "review", status: .confirmed)
            let snapshot = try service.snapshot()
            try require(
                snapshot.reviewInbox.first(where: { $0.id == "review" })?.status == .confirmed,
                "review confirmation state"
            )
            try require(
                snapshot.project(id: "reframe-multicam")?.context.currentSummary == "New",
                "review applies confirmed understanding"
            )
        }
    }

    private static func sessionScannerIncremental() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-ingestion-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("rollout.jsonl")
        let metadata = """
        {"type":"session_meta","timestamp":"2026-07-16T00:00:00.000Z","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: session)

        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        let baseline = try scanner.scan()
        try require(baseline.isEmpty, "first scan establishes baseline")

        let turn = """
        {"type":"event_msg","timestamp":"2026-07-16T00:01:00.000Z","payload":{"type":"task_started","turn_id":"turn"}}
        {"type":"event_msg","timestamp":"2026-07-16T00:01:01.000Z","payload":{"type":"user_message","message":"Update the project"}}
        {"type":"event_msg","timestamp":"2026-07-16T00:01:02.000Z","payload":{"type":"task_complete","turn_id":"turn","last_agent_message":"Project updated"}}

        """
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(turn.utf8))
        try handle.close()

        let segments = try scanner.scan()
        try require(segments.count == 1, "one completed turn becomes one segment")
        try require(segments.first?.threadID == "thread", "segment thread id")
        try require(segments.first?.userText == "Update the project", "segment user text")
        try require(segments.first?.assistantText == "Project updated", "segment assistant text")
        let repeated = try scanner.scan()
        try require(repeated.map(\.id) == segments.map(\.id), "pending segment remains available before processing")
        try scanner.markProcessed(segmentIDs: segments.map(\.id))
        let processed = try scanner.scan()
        try require(processed.isEmpty, "processed segment is not returned again")
    }

    private static func agentDailyBudgetStopsBeforeInvocation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-budget-check-\(UUID().uuidString)", isDirectory: true)
        let stateRoot = root.appendingPathComponent("state", isDirectory: true)
        let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let repository = WorkstateRepository(paths: WorkstatePaths(root: stateRoot))
        try repository.ensureInitialized(initial: WorkspaceSnapshot())
        let service = WorkstateService(repository: repository)
        _ = try service.createProject(
            ProjectCreateInput(
                id: "workstate",
                name: "Workstate",
                summary: "Shared working memory",
                purpose: "Budget test",
                position: GraphPosition(x: 0, y: 0)
            )
        )

        let timestamp = Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let usage = """
        {"timestamp":"\(timestamp)","mode":"steward","segmentID":"prior","runtimeThreadID":"runtime","usage":{"input_tokens":60000,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}

        """
        try Data(usage.utf8).write(to: runtimeRoot.appendingPathComponent("agent-runs.jsonl"))

        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
            runtimeRoot: runtimeRoot
        )
        let runtime = AgentRuntimeClient(
            runtimeScript: root.appendingPathComponent("missing.js"),
            nodePath: "/missing/node",
            runtimeRoot: runtimeRoot
        )
        let orchestrator = WorkstateOrchestrator(
            service: service,
            scanner: scanner,
            runtime: runtime,
            mode: .shadow,
            maxDailyInputTokens: 75_000,
            reservedInputTokensPerRun: 30_000
        )
        let summary = try orchestrator.process([
            SessionSegment(
                threadID: "thread",
                turnID: "turn",
                sourcePath: "/tmp/turn.jsonl",
                startOffset: 0,
                endOffset: 100,
                cwd: "/Users/timshu/Documents/Workstate",
                userText: "所有内容已经确认",
                assistantText: "准备更新",
                timestamp: Date()
            )
        ])
        try require(summary.budgetPaused, "daily token budget pauses orchestration")
        try require(summary.agentRuns == 0, "budget check happens before agent invocation")
        try require(summary.processed == 0, "budget-paused segment stays pending")
    }

    private static func taskBranchAndMerge() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            let service = WorkstateService(repository: repository)
            _ = try service.createProject(
                ProjectCreateInput(
                    id: "project",
                    name: "Project",
                    summary: "Graph test",
                    purpose: "Verify branching",
                    position: GraphPosition(x: 100, y: 100)
                )
            )
            guard let start = try service.snapshot().project(id: "project")?.latestEvent else {
                throw CheckFailure.failed("project start event")
            }
            _ = try service.startTask(
                TaskStartInput(
                    projectID: "project",
                    id: "task",
                    title: "Task",
                    objective: "Branch and merge",
                    branchedFromEventID: start.id
                )
            )
            _ = try service.appendEvent(
                EventInput(
                    id: "implementation",
                    projectID: "project",
                    taskID: "task",
                    title: "Implemented",
                    summary: "Changed state",
                    kind: .implementation,
                    stage: .implementation,
                    delivery: DeliverySnapshot(stage: .changed)
                )
            )
            _ = try service.appendEvent(
                EventInput(
                    id: "merge",
                    projectID: "project",
                    mergeTaskID: "task",
                    title: "Merged",
                    summary: "Task returned to mainline",
                    kind: .integrated,
                    stage: .integration,
                    delivery: DeliverySnapshot(stage: .integrated)
                )
            )

            guard let project = try service.snapshot().project(id: "project"),
                  let task = project.task(id: "task"),
                  let taskStart = project.events.first(where: { $0.taskID == "task" && $0.kind == .taskStarted }),
                  let implementation = project.event(id: "implementation"),
                  let merge = project.event(id: "merge") else {
                throw CheckFailure.failed("stored branch graph")
            }
            try require(task.status == .completed, "merged task status")
            try require(task.mergedByEventID == "merge", "task merge event")
            try require(implementation.parentEventIDs == [taskStart.id], "inferred task parent")
            try require(merge.parentEventIDs.contains(start.id), "mainline merge parent")
            try require(merge.parentEventIDs.contains("implementation"), "branch merge parent")
        }
    }

    private static func contextRevisionAuthority() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let projectID = "reframe-multicam"
            let original = try service.snapshot().project(id: projectID)?.context.currentSummary

            _ = try service.reviseContext(
                ContextRevisionInput(
                    id: "inferred",
                    projectID: projectID,
                    title: "Inference",
                    summary: "Not authoritative",
                    status: .inferred,
                    currentSummary: "Must not become current",
                    statementID: "candidate",
                    statement: "Candidate understanding"
                )
            )
            let afterInference = try service.snapshot().project(id: projectID)
            try require(afterInference?.context.currentSummary == original, "inference does not replace current summary")
            try require(
                afterInference?.context.understanding.first(where: { $0.id == "candidate" })?.status == .inferred,
                "inference remains labeled"
            )

            _ = try service.reviseContext(
                ContextRevisionInput(
                    id: "confirmed",
                    projectID: projectID,
                    title: "Confirmed",
                    summary: "Authoritative update",
                    status: .confirmed,
                    currentSummary: "New current understanding",
                    statementID: "candidate",
                    statement: "Confirmed understanding"
                )
            )
            let confirmed = try service.snapshot().project(id: projectID)
            try require(confirmed?.context.currentSummary == "New current understanding", "confirmed summary update")
            try require(
                confirmed?.context.understanding.first(where: { $0.id == "candidate" })?.status == .confirmed,
                "statement authority update"
            )
        }
    }

    private static func timelineLaneReuse() throws {
        let tasks = [
            timelineTask(id: "first", start: 0, update: 8, completion: 10),
            timelineTask(id: "overlap", start: 5, update: 12, completion: 15),
            timelineTask(id: "later", start: 16, update: 18, completion: 20)
        ]
        let allocation = ProjectTaskLaneAllocation(tasks: tasks)

        try require(allocation.laneCount == 2, "timeline uses maximum concurrent lanes")
        try require(allocation.laneByTaskID["first"] == 1, "first task lane")
        try require(allocation.laneByTaskID["overlap"] == 2, "overlapping task lane")
        try require(allocation.laneByTaskID["later"] == 1, "completed lane is reused")
    }

    private static func projectTimelineHierarchy() throws {
        let start = ProjectEvent(
            id: "project-start",
            timestamp: timelineDate(0),
            title: "Project started",
            summary: "Start",
            kind: .projectStarted,
            loopStage: .intake
        )
        let task = timelineTask(id: "task", start: 1, update: 3, completion: 4)
        let internalEvent = ProjectEvent(
            id: "task-progress",
            taskID: task.id,
            timestamp: timelineDate(3),
            title: "Implemented",
            summary: "Internal progress",
            kind: .implementation,
            loopStage: .implementation
        )
        let merge = ProjectEvent(
            id: "merge",
            timestamp: timelineDate(4),
            title: "Merged",
            summary: "Returned to mainline",
            kind: .integrated,
            loopStage: .integration
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            graphPosition: .init(x: 0, y: 0),
            tasks: [task],
            events: [start, internalEvent, merge]
        )
        let layout = ProjectTimelineLayout(project: project)
        let taskNodeCount = layout.nodes.filter {
            if case .task = $0.content { return true }
            return false
        }.count
        let projectEventNodeCount = layout.nodes.filter {
            if case .projectEvent = $0.content { return true }
            return false
        }.count

        try require(taskNodeCount == 1, "project timeline has one node per task")
        try require(projectEventNodeCount == 2, "project timeline keeps mainline events")
        try require(
            !layout.nodes.contains(where: {
                $0.id == ProjectTimelineLayout.eventNodeID(internalEvent.id)
            }),
            "task progress stays inside task detail"
        )
        try require(
            layout.points[ProjectTimelineLayout.taskNodeID(task.id)]?.y
                != layout.points[ProjectTimelineLayout.eventNodeID(merge.id)]?.y,
            "task progress and mainline merge use separate rows"
        )
    }

    @MainActor
    private static func timelineSelectionHierarchy() throws {
        try withFixture { repository in
            let start = ProjectEvent(
                id: "project-start",
                timestamp: timelineDate(0),
                title: "Project started",
                summary: "Start",
                kind: .projectStarted,
                loopStage: .intake
            )
            let task = timelineTask(id: "task", start: 1, update: 3, completion: nil)
            let first = ProjectEvent(
                id: "first",
                taskID: task.id,
                timestamp: timelineDate(2),
                title: "First",
                summary: "First progress",
                kind: .investigation,
                loopStage: .audit
            )
            let latest = ProjectEvent(
                id: "latest",
                taskID: task.id,
                timestamp: timelineDate(3),
                title: "Latest",
                summary: "Latest progress",
                kind: .implementation,
                loopStage: .implementation
            )
            let project = ProjectRecord(
                id: "project",
                name: "Project",
                summary: "Summary",
                graphPosition: .init(x: 0, y: 0),
                tasks: [task],
                events: [start, first, latest]
            )
            try repository.ensureInitialized(initial: WorkspaceSnapshot(projects: [project]))
            let model = WorkstateViewModel(repository: repository)

            model.selectProject(project.id)
            model.selectTask(task.id)
            try require(model.selectedTaskID == task.id, "task node selects the task")
            try require(model.selectedEventID == latest.id, "task node opens latest internal progress")

            model.selectTaskEvent(first.id)
            try require(model.selectedTaskID == task.id, "internal progress keeps task selected")
            try require(model.selectedEventID == first.id, "internal progress changes reference detail")

            model.selectProjectEvent(start.id)
            try require(model.selectedTaskID == nil, "project checkpoint clears task selection")
            try require(model.selectedEventID == start.id, "project checkpoint opens its own detail")
        }
    }

    private static func timelineTask(
        id: String,
        start: TimeInterval,
        update: TimeInterval,
        completion: TimeInterval?
    ) -> TaskRecord {
        TaskRecord(
            id: id,
            title: id,
            objective: id,
            status: completion == nil ? .active : .completed,
            accent: .blue,
            currentStage: completion == nil ? .implementation : .completed,
            startedAt: timelineDate(start),
            updatedAt: timelineDate(update),
            completedAt: completion.map { timelineDate($0) },
            branchedFromEventID: "project-start",
            mergedByEventID: completion == nil ? nil : "merge"
        )
    }

    private static func timelineDate(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private static func withFixture(_ body: (WorkstateRepository) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(WorkstateRepository(paths: WorkstatePaths(root: root)))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw CheckFailure.failed(label) }
    }
}

private enum CheckFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let label): "Check failed: \(label)"
        }
    }
}
