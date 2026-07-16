import Foundation
import WorkstateCore

public enum AutomationMode: String, Sendable {
    case shadow
    case live
}

public struct OrchestrationSummary: Sendable {
    public var processed: Int
    public var changed: Int
    public var reviews: Int
    public var ignored: Int
    public var agentRuns: Int
    public var budgetPaused: Bool

    public init(processed: Int = 0, changed: Int = 0, reviews: Int = 0, ignored: Int = 0, agentRuns: Int = 0, budgetPaused: Bool = false) {
        self.processed = processed
        self.changed = changed
        self.reviews = reviews
        self.ignored = ignored
        self.agentRuns = agentRuns
        self.budgetPaused = budgetPaused
    }
}

public struct WorkstateOrchestrator: Sendable {
    public let service: WorkstateService
    public let scanner: CodexSessionScanner
    public let runtime: AgentRuntimeClient
    public let mode: AutomationMode
    public let maxAgentRunsPerBatch: Int
    public let maxDailyInputTokens: Int
    public let reservedInputTokensPerRun: Int

    public init(
        service: WorkstateService = .init(),
        scanner: CodexSessionScanner = .init(),
        runtime: AgentRuntimeClient = .init(),
        mode: AutomationMode = .shadow,
        maxAgentRunsPerBatch: Int = 1,
        maxDailyInputTokens: Int = 75_000,
        reservedInputTokensPerRun: Int = 30_000
    ) {
        self.service = service
        self.scanner = scanner
        self.runtime = runtime
        self.mode = mode
        self.maxAgentRunsPerBatch = maxAgentRunsPerBatch
        self.maxDailyInputTokens = maxDailyInputTokens
        self.reservedInputTokensPerRun = reservedInputTokensPerRun
    }

    public func process(_ segments: [SessionSegment]) throws -> OrchestrationSummary {
        var summary = OrchestrationSummary()
        var processedIDs: [String] = []

        processingLoop: for segment in segments {
            guard summary.agentRuns < maxAgentRunsPerBatch else { break }
            guard isMeaningful(segment) else {
                processedIDs.append(segment.id)
                summary.ignored += 1
                continue
            }
            let workspace = try service.snapshot()
            let route: RouteResult
            if let deterministic = deterministicRoute(segment: segment, workspace: workspace) {
                route = deterministic
            } else {
                guard try hasAgentBudget() else {
                    summary.budgetPaused = true
                    break processingLoop
                }
                route = try runtime.route(segment: segment, workspace: workspace, scanner: scanner)
                summary.agentRuns += 1
            }

            switch route.action {
            case "ignore":
                processedIDs.append(segment.id)
                summary.ignored += 1
            case "candidate_project", "ambiguous":
                let source = evidenceSource(segment)
                if mode == .live {
                    _ = try service.addSource(source)
                    _ = try service.upsertReview(
                        ReviewItem(
                            id: stableID(prefix: "review", segment: segment),
                            kind: route.action == "candidate_project" ? .candidateProject : .ambiguousRouting,
                            title: route.action == "candidate_project" ? "发现候选新项目" : "无法确定项目归属",
                            summary: route.worklineHint.isEmpty ? segment.userText : route.worklineHint,
                            reason: route.reason,
                            proposedValue: route.projectId,
                            sourceIDs: [source.id],
                            createdAt: segment.timestamp,
                            updatedAt: segment.timestamp
                        )
                    )
                } else {
                    try appendShadow(route, segment: segment)
                }
                processedIDs.append(segment.id)
                summary.reviews += 1
            case "existing_project":
                guard let project = workspace.project(id: route.projectId) else {
                    throw WorkstateStorageError.missingProject(route.projectId)
                }
                guard try hasAgentBudget() else {
                    summary.budgetPaused = true
                    break
                }
                let result = try runtime.steward(segment: segment, project: project, scanner: scanner)
                summary.agentRuns += 1
                if mode == .shadow {
                    try appendShadow(result, segment: segment, projectID: project.id)
                } else {
                    try apply(result, segment: segment, project: project)
                }
                processedIDs.append(segment.id)
                switch result.classification {
                case "ordinary_delta": summary.changed += 1
                case "review_required": summary.reviews += 1
                default: summary.ignored += 1
                }
            default:
                throw WorkstateStorageError.invalidState("Unknown route action: \(route.action)")
            }
        }

        try scanner.markProcessed(segmentIDs: processedIDs)
        summary.processed = processedIDs.count
        return summary
    }

    private func isMeaningful(_ segment: SessionSegment) -> Bool {
        let user = segment.userText.lowercased()
        let assistant = segment.assistantText.lowercased()
        let explicitDecisionSignals = [
            "确认", "我同意", "就这样", "可以改", "按这个", "定下来", "拍板",
            "confirmed", "i agree", "go ahead", "ship it"
        ]
        let durableOutcomeSignals = [
            "已实现", "已修改", "已更新", "已完成", "构建通过", "测试通过", "验证通过",
            "已发布", "已部署", "已提交", "已合并", "根因", "当前结论", "工作区状态",
            "implemented", "updated", "completed", "build passed", "tests passed", "verified",
            "deployed", "published", "committed", "merged", "root cause"
        ]
        return explicitDecisionSignals.contains(where: user.contains)
            || durableOutcomeSignals.contains(where: assistant.contains)
    }

    private func hasAgentBudget() throws -> Bool {
        try runtime.dailyInputTokens() + reservedInputTokensPerRun <= maxDailyInputTokens
    }

    private func deterministicRoute(
        segment: SessionSegment,
        workspace: WorkspaceSnapshot
    ) -> RouteResult? {
        let text = "\(segment.userText)\n\(segment.assistantText)".lowercased()
        let cwd = segment.cwd.lowercased()
        var matches: [(String, String)] = []

        if cwd.contains("/documents/workstate") || text.contains("workstate") {
            matches.append(("workstate", "明确涉及 Workstate 产品或代码"))
        }
        if cwd.contains("reframe_website") || text.contains("reframe 官网") || text.contains("官网项目") {
            matches.append(("reframe-website", "明确涉及 Reframe 官网"))
        }
        if cwd.contains("reframe-app-material-graph")
            || text.contains("reframe beta")
            || text.contains("素材图谱")
            || text.contains("storyboard")
            || text.contains("候选池") {
            matches.append(("reframe-beta", "明确涉及 Reframe Beta 素材图谱工作"))
        }
        if text.contains("v1.0 rc")
            || text.contains("reframe rc")
            || text.contains("多机位版本")
            || text.contains("报告视图") {
            matches.append(("reframe-rc", "明确涉及 Reframe V1.0 RC"))
        }

        let valid = matches.filter { workspace.project(id: $0.0) != nil }
        let projectIDs = Set(valid.map(\.0))
        guard projectIDs.count == 1, let match = valid.first else { return nil }
        return RouteResult(
            action: "existing_project",
            projectId: match.0,
            worklineHint: "",
            confidence: 0.99,
            reason: match.1
        )
    }

    private func apply(_ result: StewardResult, segment: SessionSegment, project: ProjectRecord) throws {
        guard result.classification != "no_change" else { return }
        let source = evidenceSource(segment)
        _ = try service.addSource(source)

        if result.classification == "review_required" {
            let kind = ReviewKind(rawValue: result.review.kind) ?? .understandingConflict
            _ = try service.upsertReview(
                ReviewItem(
                    id: stableID(prefix: "review", segment: segment),
                    kind: kind,
                    projectID: project.id,
                    taskID: project.task(id: result.worklineId) == nil ? nil : result.worklineId,
                    title: result.title,
                    summary: result.summary,
                    reason: result.review.reason,
                    previousValue: result.review.previousValue,
                    proposedValue: result.review.proposedValue,
                    proposedChanges: result.review.proposedChanges,
                    sourceIDs: [source.id],
                    createdAt: segment.timestamp,
                    updatedAt: segment.timestamp
                )
            )
            return
        }

        let eventID = stableID(prefix: "delta", segment: segment)
        if project.event(id: eventID) != nil { return }
        guard let kind = EventKind(rawValue: result.kind),
              let stage = LoopStage(rawValue: result.stage),
              let delivery = DeliveryStage(rawValue: result.delivery) else {
            throw WorkstateStorageError.invalidState("Steward returned an unsupported state")
        }
        let taskID = project.task(id: result.worklineId) == nil ? nil : result.worklineId
        _ = try service.appendEvent(
            EventInput(
                id: eventID,
                projectID: project.id,
                taskID: taskID,
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

    private func appendShadow<Result: Encodable>(
        _ result: Result,
        segment: SessionSegment,
        projectID: String? = nil
    ) throws {
        let url = WorkstatePaths.defaultPaths().root.appendingPathComponent("shadow-proposals.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let record = ShadowRecord(
            timestamp: Date(),
            segmentID: segment.id,
            projectID: projectID,
            payload: try JSONValue(result)
        )
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

private struct ShadowRecord: Codable {
    var timestamp: Date
    var segmentID: String
    var projectID: String?
    var payload: JSONValue
}

private struct JSONValue: Codable {
    var object: [String: String]

    init<Value: Encodable>(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = raw as? [String: Any] else {
            object = ["value": String(data: data, encoding: .utf8) ?? ""]
            return
        }
        object = dictionary.mapValues { item in
            if let string = item as? String { return string }
            if let data = try? JSONSerialization.data(withJSONObject: item),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return String(describing: item)
        }
    }
}
