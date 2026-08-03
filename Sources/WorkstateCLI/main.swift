import Foundation
import WorkstateCore
import WorkstateIngestion

@main
struct WorkstateCLI {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("workstate: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() throws {
        let raw = Array(CommandLine.arguments.dropFirst())
        guard let command = raw.first else {
            printHelp()
            return
        }
        let arguments = CLIArguments(Array(raw.dropFirst()))
        let repository = WorkstateRepository()
        let service = WorkstateService(repository: repository)

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "home":
            print(repository.paths.root.path)
        case "bootstrap":
            try repository.ensureInitialized()
            print(repository.paths.state.path)
        case "snapshot":
            try printJSON(service.snapshot())
        case "graph":
            let snapshot = try service.snapshot()
            try printJSON(GraphOutput(projects: snapshot.projects, relations: snapshot.relations))
        case "list":
            let snapshot = try service.snapshot()
            let output = snapshot.projects.map { project in
                ProjectListOutput(
                    project: project,
                    relationCount: snapshot.relations.filter {
                        $0.fromProjectID == project.id || $0.toProjectID == project.id
                    }.count
                )
            }
            try printJSON(output)
        case "project":
            let id = try arguments.requiredPositional(at: 0, name: "project-id")
            try printJSON(
                service.compactProject(
                    projectID: id,
                    recentLimit: try arguments.integer("recent", default: 8)
                )
            )
        case "task":
            let id = try arguments.requiredPositional(at: 0, name: "task-id")
            try printJSON(service.taskContext(taskID: id))
        case "handoff":
            let scope = try arguments.requiredPositional(at: 0, name: "project|task|thread")
            let id = try arguments.requiredPositional(at: 1, name: "\(scope)-id")
            let workspace = try service.snapshot()
            let targetProjectID: String
            switch scope {
            case "project":
                targetProjectID = id
            case "task":
                guard let project = workspace.projects.first(where: {
                    $0.tasks.contains(where: { $0.id == id })
                }) else {
                    throw WorkstateStorageError.missingTask(id)
                }
                targetProjectID = project.id
            case "thread":
                guard let binding = try CodexSessionScanner().routeBinding(threadID: id) else {
                    throw CLIError.invalidOption("Thread has no Workstate project route: \(id)")
                }
                targetProjectID = binding.projectID
            default:
                throw CLIError.invalidOption("Handoff scope must be project, task, or thread")
            }
            let handoffCoordinator = ConversationBatchCoordinator()
            _ = try handoffCoordinator.recoverInterruptedBatches()
            _ = try handoffCoordinator.scanAll()
            _ = try handoffCoordinator.process(
                trigger: .handoff,
                projectID: targetProjectID
            )
            var snapshot: ContextSnapshot
            let profileGuidance = (try? CollaborationProfileRepository(
                root: repository.paths.root
            ).load().activeGuidance) ?? []
            let memoryGuidance = (try? DurableMemoryRepository(root: repository.paths.root)
                .retrieve(
                    DurableMemorySelection()
                )
                .flatMap(\.entries)
                .filter { $0.lifecycle == .active || $0.lifecycle == .prohibited }
                .map(\.text)) ?? []
            let guidance = Array(Set(profileGuidance + memoryGuidance)).sorted()
            switch scope {
            case "project":
                snapshot = try service.contextSnapshot(
                    projectID: id,
                    collaborationGuidance: guidance
                )
            case "task":
                snapshot = try service.contextSnapshot(
                    taskID: id,
                    collaborationGuidance: guidance
                )
            case "thread":
                snapshot = try service.contextSnapshot(
                    threadID: id,
                    projectID: targetProjectID,
                    collaborationGuidance: guidance
                )
            default:
                throw CLIError.invalidOption("Handoff scope must be project, task, or thread")
            }
            snapshot.openSemanticBundles = try CodexSessionScanner(
                runtimeRoot: repository.paths.root
            ).openSemanticBundles()
                .filter {
                    $0.projectID == targetProjectID
                        && (scope != "thread" || $0.threadID == id)
                }
                .map {
                    ContextSnapshotSemanticBundle(
                        id: $0.id,
                        title: $0.title,
                        summary: $0.summary,
                        threadID: $0.threadID,
                        turnIDs: $0.evidenceIDs.compactMap { evidenceID in
                            evidenceID.split(separator: ":", maxSplits: 1).last.map(String.init)
                        },
                        updatedAt: $0.updatedAt
                    )
                }
            switch arguments.value("format") ?? "markdown" {
            case "markdown":
                let handoff = try ContextHandoffExporter(
                    root: repository.paths.root
                ).export(snapshot)
                let markdown = try String(contentsOf: handoff.url, encoding: .utf8)
                print(markdown, terminator: "")
            case "json":
                try printJSON(snapshot)
            default:
                throw CLIError.invalidOption("--format must be markdown or json")
            }
        case "source":
            let excerpt = arguments.values("user").map {
                ConversationMessage(role: "user", text: $0)
            } + arguments.values("assistant").map {
                ConversationMessage(role: "assistant", text: $0)
            }
            let source = SourceReference(
                id: try arguments.required("id"),
                kind: try arguments.required("kind"),
                label: try arguments.required("label"),
                locator: try arguments.required("locator"),
                threadID: arguments.value("thread") ?? "",
                turnIDs: arguments.values("turn"),
                excerpt: excerpt,
                contentHash: arguments.value("hash") ?? ""
            )
            _ = try service.addSource(source)
            try printJSON(source)
        case "project-create":
            let status = try parseEnum(
                arguments.value("status") ?? ProjectStatus.active.rawValue,
                as: ProjectStatus.self,
                label: "project status"
            )
            let accent = try parseEnum(
                arguments.value("accent") ?? ProjectAccent.blue.rawValue,
                as: ProjectAccent.self,
                label: "accent"
            )
            let input = ProjectCreateInput(
                id: try arguments.required("id"),
                name: try arguments.required("name"),
                summary: try arguments.required("summary"),
                purpose: arguments.value("purpose") ?? "",
                status: status,
                accent: accent,
                position: GraphPosition(
                    x: try arguments.double("x", default: 240),
                    y: try arguments.double("y", default: 220)
                ),
                sourceIDs: arguments.values("source")
            )
            _ = try service.createProject(input)
            try printJSON(service.compactProject(projectID: input.id))
        case "project-update":
            let id = try arguments.requiredPositional(at: 0, name: "project-id")
            let status = try arguments.value("status").map {
                try parseEnum($0, as: ProjectStatus.self, label: "project status")
            }
            let x = try arguments.optionalDouble("x")
            let y = try arguments.optionalDouble("y")
            guard (x == nil) == (y == nil) else {
                throw CLIError.invalidOption("--x and --y must be provided together")
            }
            _ = try service.updateProject(
                id: id,
                update: ProjectUpdate(
                    name: arguments.value("name"),
                    summary: arguments.value("summary"),
                    status: status,
                    position: x.flatMap { x in y.map { GraphPosition(x: x, y: $0) } }
                )
            )
            try printJSON(service.compactProject(projectID: id))
        case "project-model":
            let id = try arguments.requiredPositional(at: 0, name: "project-id")
            let sourceIDs = arguments.values("source")
            let decisions = arguments.hasOption("decision")
                ? arguments.values("decision").map {
                    DecisionRecord(text: $0, status: .confirmed, sourceIDs: sourceIDs)
                }
                : nil
            _ = try service.updateProjectModel(
                id: id,
                update: ProjectModelUpdate(
                    currentSummary: arguments.value("current"),
                    purpose: arguments.value("purpose"),
                    objectModel: arguments.optionalValues("object"),
                    acceptedDecisions: decisions,
                    forbiddenDirections: arguments.optionalValues("forbidden")
                )
            )
            try printJSON(service.compactProject(projectID: id))
        case "relation":
            let kind = try parseEnum(
                try arguments.required("kind"),
                as: RelationKind.self,
                label: "relation kind"
            )
            let status = try parseEnum(
                arguments.value("status") ?? EvidenceStatus.confirmed.rawValue,
                as: EvidenceStatus.self,
                label: "evidence status"
            )
            let relation = ProjectRelation(
                id: try arguments.required("id"),
                fromProjectID: try arguments.required("from"),
                toProjectID: try arguments.required("to"),
                kind: kind,
                label: try arguments.required("label"),
                status: status,
                sourceIDs: arguments.values("source")
            )
            _ = try service.upsertRelation(relation)
            try printJSON(relation)
        case "task-start":
            let stage = try parseEnum(
                arguments.value("stage") ?? LoopStage.intake.rawValue,
                as: LoopStage.self,
                label: "loop stage"
            )
            let accent = try parseEnum(
                arguments.value("accent") ?? ProjectAccent.blue.rawValue,
                as: ProjectAccent.self,
                label: "accent"
            )
            let input = TaskStartInput(
                projectID: try arguments.required("project"),
                id: try arguments.required("id"),
                title: try arguments.required("title"),
                objective: try arguments.required("objective"),
                accent: accent,
                stage: stage,
                branchedFromEventID: try arguments.required("branch-from"),
                tags: arguments.values("tag"),
                sourceIDs: arguments.values("source")
            )
            _ = try service.startTask(input)
            try printJSON(service.taskContext(taskID: input.id))
        case "task-update":
            let id = try arguments.requiredPositional(at: 0, name: "task-id")
            let status = try arguments.value("status").map {
                try parseEnum($0, as: TaskStatus.self, label: "task status")
            }
            let stage = try arguments.value("stage").map {
                try parseEnum($0, as: LoopStage.self, label: "loop stage")
            }
            _ = try service.updateTask(
                id: id,
                update: TaskUpdate(
                    status: status,
                    stage: stage,
                    title: arguments.value("title"),
                    objective: arguments.value("objective")
                )
            )
            try printJSON(service.taskContext(taskID: id))
        case "task-focus":
            let projectID = try arguments.required("project")
            let taskID = try arguments.requiredPositional(at: 0, name: "task-id")
            _ = try service.focusTask(
                projectID: projectID,
                taskID: taskID == "none" ? nil : taskID
            )
            try printJSON(service.compactProject(projectID: projectID))
        case "event":
            let kind = try parseEnum(
                try arguments.required("kind"),
                as: EventKind.self,
                label: "event kind"
            )
            let stage = try parseEnum(
                try arguments.required("stage"),
                as: LoopStage.self,
                label: "loop stage"
            )
            let decisionStatus = try parseEnum(
                arguments.value("decision-status") ?? EvidenceStatus.confirmed.rawValue,
                as: EvidenceStatus.self,
                label: "decision status"
            )
            let deliveryStage = try parseEnum(
                arguments.value("delivery") ?? DeliveryStage.unchanged.rawValue,
                as: DeliveryStage.self,
                label: "delivery stage"
            )
            let decisions = arguments.values("decision").map {
                DecisionRecord(text: $0, status: decisionStatus, sourceIDs: arguments.values("source"))
            }
            let input = EventInput(
                id: arguments.value("id"),
                projectID: try arguments.required("project"),
                taskID: arguments.value("task"),
                mergeTaskID: arguments.value("merge-task"),
                title: try arguments.required("title"),
                summary: try arguments.required("summary"),
                kind: kind,
                stage: stage,
                parentEventIDs: arguments.values("parent"),
                facts: arguments.values("fact"),
                decisions: decisions,
                operations: OperationalContext(
                    cwd: arguments.value("cwd") ?? "",
                    repository: arguments.value("repository") ?? "",
                    branch: arguments.value("branch") ?? "",
                    commit: arguments.value("commit") ?? "",
                    files: arguments.values("file"),
                    runtime: arguments.values("runtime")
                ),
                delivery: DeliverySnapshot(
                    stage: deliveryStage,
                    checks: arguments.values("check"),
                    verifiedAt: deliveryStage == .unchanged || deliveryStage == .changed ? nil : Date()
                ),
                tags: arguments.values("tag"),
                sourceIDs: arguments.values("source")
            )
            _ = try service.appendEvent(input)
            try printJSON(service.compactProject(projectID: input.projectID))
        case "context-revise":
            let status = try parseEnum(
                try arguments.required("status"),
                as: EvidenceStatus.self,
                label: "evidence status"
            )
            let input = ContextRevisionInput(
                id: arguments.value("id"),
                projectID: try arguments.required("project"),
                title: try arguments.required("title"),
                summary: try arguments.required("summary"),
                status: status,
                changes: arguments.values("change"),
                sourceIDs: arguments.values("source"),
                currentSummary: arguments.value("current"),
                statementID: arguments.value("statement-id"),
                statement: arguments.value("statement")
            )
            _ = try service.reviseContext(input)
            try printJSON(service.compactProject(projectID: input.projectID))
        case "brief-compose":
            let briefCoordinator = ConversationBatchCoordinator()
            _ = try briefCoordinator.recoverInterruptedBatches()
            _ = try briefCoordinator.scanAll()
            _ = try briefCoordinator.process(trigger: .dailyBrief)
            let composer = BriefCompositionService()
            guard let brief = try composer.refreshLatest(
                workspace: service.snapshot(),
                force: arguments.hasFlag("force")
            ) else {
                throw CLIError.invalidOption("No activity brief is available to compose")
            }
            try printJSON(brief)
        case "sync":
            let coordinator = ConversationBatchCoordinator()
            _ = try coordinator.recoverInterruptedBatches()
            let pending = try coordinator.scanAll()
            let result = try coordinator.process(
                trigger: .manual,
                threadID: arguments.value("thread")
            )
            try printJSON(
                ManualSyncOutput(
                    discovered: pending.pointerCount,
                    processed: result?.summary.processed ?? 0,
                    changed: result?.summary.changed ?? 0,
                    ignored: result?.summary.ignored ?? 0,
                    failed: result?.failedPointerCount ?? 0,
                    agentRuns: result?.summary.agentRuns ?? 0
                )
            )
        case "monitoring-repair":
            let settings = try WorkstateSettingsRepository().load(
                workspaceHasProjects: !service.snapshot().projects.isEmpty
            )
            guard settings.setupCompleted,
                  settings.liveMonitoringEnabled,
                  let cutoff = settings.liveMonitoringStartedAt else {
                throw CLIError.invalidOption("Live monitoring has no active start time")
            }
            let scanner = CodexSessionScanner()
            let discarded = try scanner.discardUnprocessed(before: cutoff)
            try printJSON(MonitoringRepairOutput(cutoff: cutoff, discarded: discarded))
        case "monitoring-retry-failed":
            let scanner = CodexSessionScanner()
            let state = try scanner.loadState()
            let ids = (state.processingRecords ?? [:]).compactMap { id, record -> String? in
                record.stage == .failed ? id : nil
            }
            try scanner.requeue(segmentIDs: ids)
            try printJSON(MonitoringRetryOutput(requeued: ids.count))
        case "source-retry":
            let threadID = try arguments.required("thread")
            let turnIDs = arguments.values("turn")
            guard !turnIDs.isEmpty else {
                throw CLIError.invalidOption("source-retry requires at least one --turn")
            }
            let index = try ConversationSourceIndex(
                databaseURL: repository.paths.root
                    .appendingPathComponent("conversation-source-index.sqlite")
            )
            let requeued = try index.requeueFailedPointers(turnIDs.map {
                ConversationSourcePointerID(
                    provider: "codex",
                    threadID: threadID,
                    turnID: $0
                )
            })
            try printJSON(SourceRetryOutput(threadID: threadID, requeued: requeued))
        case "collaboration-profile-import":
            let path = try arguments.requiredPositional(at: 0, name: "profile-json")
            let profile = try WorkstateCoding.makeDecoder().decode(
                CollaborationProfile.self,
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
            try CollaborationProfileRepository(root: repository.paths.root).save(profile)
            try printJSON(profile)
        case "agent-smoke":
            let runtime = AgentRuntimeClient(runtimeRoot: repository.paths.root)
            let syntheticWorkspace = WorkspaceSnapshot(
                projects: [
                    ProjectRecord(
                        id: "synthetic-workstate",
                        name: "Synthetic Workstate",
                        summary: "Protocol-only smoke-test fixture",
                        context: ProjectContext(
                            currentSummary: "Protocol-only smoke-test fixture",
                            purpose: "Verify structured Agent Runtime calls without real project data"
                        )
                    )
                ]
            )
            let route = try runtime.routeGlobalChat(
                message: "Route this protocol smoke test to Synthetic Workstate.",
                recentMessages: [],
                workspace: syntheticWorkspace
            )
            let collaboration = try runtime.collaborationSteward(
                profile: CollaborationProfile(),
                history: [],
                message: "这是结构化调用自检。请简短回复，不要产生档案 mutation。"
            )
            try printJSON(
                AgentSmokeOutput(
                    routedProjectID: route.projectID,
                    collaborationReply: collaboration.reply,
                    collaborationMutationCount: collaboration.mutations.count
                )
            )
        case "agent-workline-smoke":
            let runtime = AgentRuntimeClient(runtimeRoot: repository.paths.root)
            let project = ProjectRecord(
                id: "synthetic-workstate",
                name: "Synthetic Workstate",
                summary: "Protocol-only workline fixture",
                context: ProjectContext(
                    currentSummary: "Protocol-only workline fixture",
                    purpose: "Verify ordered batch lifecycle decisions"
                )
            )
            let timestamp = Date()
            let segments = [
                SessionSegment(
                    threadID: "synthetic-thread",
                    turnID: "synthetic-turn-1",
                    sourcePath: "/tmp/synthetic-session.jsonl",
                    startOffset: 0,
                    endOffset: 1,
                    cwd: "/tmp",
                    userText: "开始一个独立的文案整理任务。",
                    assistantText: "已开始整理。",
                    timestamp: timestamp
                ),
                SessionSegment(
                    threadID: "synthetic-thread",
                    turnID: "synthetic-turn-2",
                    sourcePath: "/tmp/synthetic-session.jsonl",
                    startOffset: 1,
                    endOffset: 2,
                    cwd: "/tmp",
                    userText: "已经整理完成并检查通过。",
                    assistantText: "任务已完成并通过检查。",
                    timestamp: timestamp.addingTimeInterval(1)
                )
            ]
            let batch = try runtime.stewardBatch(
                segments: segments,
                project: project,
                scanner: CodexSessionScanner(runtimeRoot: repository.paths.root)
            )
            try printJSON(
                AgentWorklineSmokeOutput(
                    changeCount: batch.changes.count,
                    actions: batch.changes.map(\.result.worklineAction),
                    closureDispositions: batch.changes.map {
                        $0.result.closureDisposition ?? ""
                    }
                )
            )
        case "workline-reconcile":
            let path = try arguments.requiredPositional(at: 0, name: "reconciliation-json")
            let input = try WorkstateCoding.makeDecoder().decode(
                WorklineReconciliationInput.self,
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
            _ = try service.reconcileWorklines(input)
            try printJSON(service.compactProject(projectID: input.projectID))
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func parseEnum<T: RawRepresentable>(
        _ value: String,
        as type: T.Type,
        label: String
    ) throws -> T where T.RawValue == String {
        guard let parsed = T(rawValue: value) else {
            throw CLIError.invalidOption("Unknown \(label): \(value)")
        }
        return parsed
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try WorkstateCoding.makeEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CLIError.invalidOutput
        }
        print(string)
    }

    private static func printHelp() {
        print(
            """
            workstate - local project graph and collaboration history

            Read:
              workstate list
              workstate graph
              workstate project <project-id> [--recent N]
              workstate task <task-id>
              workstate handoff project <project-id> [--format markdown|json]
              workstate handoff task <task-id> [--format markdown|json]
              workstate handoff thread <thread-id> [--format markdown|json]
              workstate snapshot
              workstate home

            Write:
              workstate sync [--thread ID]
              workstate brief-compose [--force]
              workstate monitoring-repair
              workstate source-retry --thread ID --turn ID [--turn ID]
              workstate collaboration-profile-import <profile-json>
              workstate workline-reconcile <reconciliation-json>
              workstate source --id ID --kind KIND --label TEXT --locator PATH [--thread ID] [--turn ID] [--user TEXT] [--assistant TEXT] [--hash VALUE]
              workstate project-create --id ID --name TEXT --summary TEXT --x N --y N [--purpose TEXT] [--status active] [--accent blue]
              workstate project-update <id> [--name TEXT] [--summary TEXT] [--status STATUS] [--x N --y N]
              workstate project-model <id> [--current TEXT] [--purpose TEXT] [--object TEXT] [--decision TEXT] [--forbidden TEXT] [--issue TEXT] [--source ID]
              workstate relation --id ID --from PROJECT --to PROJECT --kind KIND --label TEXT [--status confirmed] [--source ID]
              workstate task-start --project ID --id ID --title TEXT --objective TEXT --branch-from EVENT [--stage intake] [--tag TEXT] [--source ID]
              workstate task-update <id> [--status STATUS] [--stage STAGE] [--title TEXT] [--objective TEXT]
              workstate task-focus <id|none> --project ID
              workstate event --project ID --title TEXT --summary TEXT --kind KIND --stage STAGE [--task ID] [--merge-task ID] [--parent EVENT] [--fact TEXT] [--decision TEXT] [--delivery STAGE]
              workstate context-revise --project ID --title TEXT --summary TEXT --status observed|inferred|confirmed [--change TEXT] [--current TEXT] [--statement TEXT] [--source ID]
            """
        )
    }
}

private struct MonitoringRepairOutput: Codable {
    var cutoff: Date
    var discarded: Int
}

private struct SourceRetryOutput: Codable {
    var threadID: String
    var requeued: Int
}

private struct ManualSyncOutput: Codable {
    var discovered: Int
    var processed: Int
    var changed: Int
    var ignored: Int
    var failed: Int
    var agentRuns: Int
}

private struct MonitoringRetryOutput: Codable {
    var requeued: Int
}

private struct AgentSmokeOutput: Codable {
    var routedProjectID: String
    var collaborationReply: String
    var collaborationMutationCount: Int
}

private struct AgentWorklineSmokeOutput: Codable {
    var changeCount: Int
    var actions: [String]
    var closureDispositions: [String]
}

private struct GraphOutput: Codable {
    var projects: [ProjectRecord]
    var relations: [ProjectRelation]
}

private struct ProjectListOutput: Codable {
    var id: String
    var name: String
    var summary: String
    var status: ProjectStatus
    var lastActivityAt: Date
    var activeTaskCount: Int
    var relationCount: Int

    init(project: ProjectRecord, relationCount: Int) {
        id = project.id
        name = project.name
        summary = project.summary
        status = project.status
        lastActivityAt = project.lastActivityAt
        activeTaskCount = project.activeTasks.count
        self.relationCount = relationCount
    }
}

private struct CLIArguments {
    var positionals: [String] = []
    var options: [String: [String]] = [:]
    var flags: Set<String> = []

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let token = raw[index]
            guard token.hasPrefix("--") else {
                positionals.append(token)
                index += 1
                continue
            }
            let key = String(token.dropFirst(2))
            if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                options[key, default: []].append(raw[index + 1])
                index += 2
            } else {
                flags.insert(key)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? {
        options[key]?.last
    }

    func values(_ key: String) -> [String] {
        options[key] ?? []
    }

    func hasOption(_ key: String) -> Bool {
        options[key] != nil
    }

    func hasFlag(_ key: String) -> Bool {
        flags.contains(key)
    }

    func optionalValues(_ key: String) -> [String]? {
        hasOption(key) ? values(key) : nil
    }

    func required(_ key: String) throws -> String {
        guard let value = value(key), !value.isEmpty else {
            throw CLIError.missingOption("--\(key)")
        }
        return value
    }

    func requiredPositional(at index: Int, name: String) throws -> String {
        guard positionals.indices.contains(index), !positionals[index].isEmpty else {
            throw CLIError.missingArgument(name)
        }
        return positionals[index]
    }

    func integer(_ key: String, default defaultValue: Int) throws -> Int {
        guard let value = value(key) else { return defaultValue }
        guard let parsed = Int(value), parsed > 0 else {
            throw CLIError.invalidOption("--\(key) requires a positive integer")
        }
        return parsed
    }

    func double(_ key: String, default defaultValue: Double) throws -> Double {
        try optionalDouble(key) ?? defaultValue
    }

    func optionalDouble(_ key: String) throws -> Double? {
        guard let value = value(key) else { return nil }
        guard let parsed = Double(value), parsed.isFinite else {
            throw CLIError.invalidOption("--\(key) requires a finite number")
        }
        return parsed
    }
}

private enum CLIError: LocalizedError {
    case unknownCommand(String)
    case missingArgument(String)
    case missingOption(String)
    case invalidOption(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command): "Unknown command: \(command)"
        case .missingArgument(let name): "Missing argument: \(name)"
        case .missingOption(let name): "Missing option: \(name)"
        case .invalidOption(let message): message
        case .invalidOutput: "Could not encode output"
        }
    }
}
