import Foundation
import WorkstateCore

public struct AgentRuntimeClient: Sendable {
    public let runtimeScript: URL
    public let nodePath: String
    public let runtimeRoot: URL
    private let processRegistry: AgentProcessRegistry
    private let settingsRepository: WorkstateSettingsRepository

    public init(
        runtimeScript: URL? = nil,
        nodePath: String? = nil,
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root
    ) {
        self.runtimeScript = runtimeScript ?? Self.defaultRuntimeScript()
        self.nodePath = nodePath ?? Self.defaultNodePath()
        self.runtimeRoot = runtimeRoot
        processRegistry = AgentProcessRegistry()
        settingsRepository = WorkstateSettingsRepository(root: runtimeRoot)
    }

    public static func defaultRuntimeScript() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["WORKSTATE_AGENT_RUNTIME"] {
            return URL(fileURLWithPath: explicit)
        }
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("AgentRuntime/dist/index.js"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Workstate/AgentRuntime/dist/index.js")
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? candidates[0]
    }

    public static func defaultEvidenceExtractor() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["WORKSTATE_EVIDENCE_EXTRACTOR"] {
            return URL(fileURLWithPath: explicit)
        }
        let runtimeDirectory = defaultRuntimeScript()
            .deletingLastPathComponent()
        return runtimeDirectory.appendingPathComponent("extract-evidence.js")
    }

    public static func defaultNodePath() -> String {
        if let explicit = ProcessInfo.processInfo.environment["WORKSTATE_NODE_PATH"] {
            return explicit
        }
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/node" }
        let candidates = pathCandidates + [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            ?? candidates.last!
    }

    public func cancelActiveProcess() {
        processRegistry.cancelActiveProcess()
    }

    public func route(
        segment: SessionSegment,
        workspace: WorkspaceSnapshot,
        scanner: CodexSessionScanner
    ) throws -> RouteResult {
        let request = RouteRequest(
            mode: "route",
            profile: try runtimeProfile(.route),
            segment: segment,
            projects: workspace.projects.map(PortfolioProjectPayload.init),
            priorRoute: try scanner.routeBinding(threadID: segment.threadID).map(RouteBindingPayload.init),
            recentTurns: try scanner.recentSegments(threadID: segment.threadID, before: segment.timestamp)
        )
        let envelope: RuntimeEnvelope<RouteResult> = try run(request, timeout: 300)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: segment.id)
        try appendDecision(envelope, segmentID: segment.id)
        return envelope.result
    }

    public func routeBatch(
        segments: [SessionSegment],
        workspace: WorkspaceSnapshot,
        routeHints: [String: String],
        scanner: CodexSessionScanner
    ) throws -> [BatchRouteDecision] {
        guard !segments.isEmpty else { return [] }
        let request = BatchRouteRequest(
            mode: "batch_route",
            profile: try runtimeProfile(.route),
            segments: segments.map(BatchRouteSegmentPayload.init),
            projects: workspace.projects.map(PortfolioProjectPayload.init),
            routeHints: routeHints.map {
                BatchRouteHintPayload(threadID: $0.key, projectID: $0.value)
            }
            .sorted { $0.threadID < $1.threadID }
        )
        let envelope: RuntimeEnvelope<BatchRouteResult> = try run(request, timeout: 600)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(
            envelope,
            segmentID: "batch-route:\(segments.first!.id):\(segments.count)"
        )
        let expected = Set(segments.map(\.id))
        let actual = Set(envelope.result.routes.map(\.segmentId))
        guard actual == expected, actual.count == envelope.result.routes.count else {
            throw WorkstateStorageError.invalidState(
                "Batch Router did not return exactly one decision for every segment"
            )
        }
        return envelope.result.routes
    }

    public func steward(
        segment: SessionSegment,
        project: ProjectRecord,
        scanner: CodexSessionScanner
    ) throws -> StewardResult {
        let request = StewardRequest(
            mode: "steward",
            profile: try runtimeProfile(.steward),
            segment: segment,
            project: StewardProjectPayload(project: project)
        )
        let envelope: RuntimeEnvelope<StewardResult> = try run(request, timeout: 300)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: segment.id)
        try appendDecision(envelope, segmentID: segment.id)
        return envelope.result
    }

    public func stewardBatch(
        segments: [SessionSegment],
        project: ProjectRecord,
        scanner: CodexSessionScanner
    ) throws -> [BatchStewardDecision] {
        guard !segments.isEmpty else { return [] }
        let request = BatchStewardRequest(
            mode: "batch_steward",
            profile: try runtimeProfile(.steward),
            segments: segments,
            project: StewardProjectPayload(project: project)
        )
        let envelope: RuntimeEnvelope<BatchStewardResult> = try run(request, timeout: 600)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(
            envelope,
            segmentID: "batch-steward:\(segments.first!.id):\(segments.count)"
        )
        try appendDecision(
            envelope,
            segmentID: "batch-steward:\(segments.first!.id):\(segments.count)"
        )
        let expected = segments.map(\.id)
        let actual = envelope.result.decisions.map(\.segmentId)
        guard actual == expected, Set(actual).count == actual.count else {
            throw WorkstateStorageError.invalidState(
                "Batch Steward did not return exactly one ordered decision for every segment"
            )
        }
        return envelope.result.decisions
    }

    public func rebuild(
        project: ProjectRecord,
        evidencePath: String,
        sourceThreadIDs: [String],
        scanner: CodexSessionScanner
    ) throws -> ProjectRebuildProposal {
        let request = RebuildRequest(
            mode: "rebuild",
            profile: try runtimeProfile(.rebuild),
            project: RebuildProjectPayload(project: project),
            evidencePath: evidencePath,
            sourceThreadIds: sourceThreadIDs
        )
        let envelope: RuntimeEnvelope<ProjectRebuildProposal> = try run(request, timeout: 600)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: "rebuild:\(project.id)")
        return envelope.result
    }

    public func distill(
        project: ProjectRecord,
        segments: [SessionSegment],
        chunkIndex: Int,
        chunkCount: Int,
        scanner: CodexSessionScanner
    ) throws -> RebuildDistilledChunk {
        let request = DistillRequest(
            mode: "distill",
            profile: try runtimeProfile(.distill),
            project: ProjectPayload(project: project),
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            segments: segments
        )
        let envelope: RuntimeEnvelope<DistillationResult> = try run(request, timeout: 300)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: "rebuild-distill:\(project.id):\(chunkIndex)")
        return RebuildDistilledChunk(
            schemaVersion: 2,
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            evidenceIds: segments.map(\.id),
            items: envelope.result.items
        )
    }

    public func ownerChat(
        project: ProjectRecord,
        history: [ProjectOwnerMessage],
        message: String,
        activeTopicID: String? = nil
    ) throws -> ProjectOwnerChatResponse {
        let request = OwnerChatRequest(
            mode: "owner_chat",
            profile: try runtimeProfile(.ownerChat),
            project: StewardProjectPayload(project: project),
            history: history,
            message: message,
            activeTopicId: activeTopicID ?? ""
        )
        let envelope: RuntimeEnvelope<ProjectOwnerChatResult> = try run(request, timeout: 300)
        try CodexSessionScanner().excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: "owner-chat:\(project.id):\(UUID().uuidString.lowercased())")
        try appendDecision(envelope, segmentID: "owner-chat:\(project.id)")
        return ProjectOwnerChatResponse(
            reply: envelope.result.reply,
            topicUpdates: envelope.result.topicUpdates,
            runtimeThreadID: envelope.runtimeThreadId
        )
    }

    public func routeGlobalChat(
        message: String,
        recentMessages: [GlobalChatMessage],
        workspace: WorkspaceSnapshot
    ) throws -> GlobalChatRouteResponse {
        let request = GlobalChatRouteRequest(
            mode: "global_chat_route",
            profile: try runtimeProfile(.route),
            message: message,
            recentMessages: recentMessages,
            projects: workspace.projects.map(PortfolioProjectPayload.init)
        )
        let envelope: RuntimeEnvelope<GlobalChatRouteResult> = try run(request, timeout: 300)
        try CodexSessionScanner().excludeThread(envelope.runtimeThreadId)
        guard workspace.project(id: envelope.result.projectId) != nil else {
            throw WorkstateStorageError.invalidState(
                "Global chat Router returned unknown project \(envelope.result.projectId)"
            )
        }
        let segmentID = "global-chat-route:\(UUID().uuidString.lowercased())"
        try appendRun(envelope, segmentID: segmentID)
        try appendDecision(envelope, segmentID: segmentID)
        return GlobalChatRouteResponse(
            projectID: envelope.result.projectId,
            reason: envelope.result.reason,
            runtimeThreadID: envelope.runtimeThreadId
        )
    }

    public func collaborationSteward(
        profile: CollaborationProfile,
        history: [CollaborationMessage],
        message: String
    ) throws -> CollaborationStewardResponse {
        let request = CollaborationStewardRequest(
            mode: "collaboration_steward",
            profile: try runtimeProfile(.collaborationSteward),
            collaborationProfile: profile,
            history: history,
            message: message
        )
        let envelope: RuntimeEnvelope<CollaborationStewardResult> = try run(request, timeout: 300)
        try CodexSessionScanner().excludeThread(envelope.runtimeThreadId)
        let segmentID = "collaboration-steward:\(UUID().uuidString.lowercased())"
        try appendRun(envelope, segmentID: segmentID)
        try appendDecision(envelope, segmentID: segmentID)
        return CollaborationStewardResponse(
            reply: envelope.result.reply,
            mutations: envelope.result.mutations,
            runtimeThreadID: envelope.runtimeThreadId
        )
    }

    public func composeBrief(
        _ brief: DailyBrief,
        workspace: WorkspaceSnapshot,
        scanner: CodexSessionScanner
    ) throws -> DailyBriefNarrative {
        let request = BriefRequest(
            mode: "brief",
            profile: try runtimeProfile(.brief),
            dateKey: brief.dateKey,
            sourceRevision: brief.sourceRevision,
            projects: try brief.projects.map { projectBrief in
                guard let project = workspace.project(id: projectBrief.projectID) else {
                    throw WorkstateStorageError.missingProject(projectBrief.projectID)
                }
                return BriefProjectPayload(brief: projectBrief, project: project)
            }
        )
        let envelope: RuntimeEnvelope<BriefComposerResult> = try run(request, timeout: 300)
        try scanner.excludeThread(envelope.runtimeThreadId)
        let segmentID = "brief:\(brief.dateKey):\(brief.sourceRevision.prefix(12))"
        try appendRun(envelope, segmentID: segmentID)
        try appendDecision(envelope, segmentID: segmentID)
        return DailyBriefNarrative(
            sourceRevision: brief.sourceRevision,
            overview: envelope.result.overview,
            projectSummaries: envelope.result.projectSummaries.map {
                DailyProjectNarrative(projectID: $0.projectId, summary: $0.summary)
            },
            nextStep: envelope.result.nextStep
        )
    }

    public func dailyInputTokens(now: Date = Date()) throws -> Int {
        let url = runtimeRoot.appendingPathComponent("agent-runs.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let start = Calendar.current.startOfDay(for: now)
        let data = try Data(contentsOf: url)
        return data.split(separator: 0x0A).reduce(into: 0) { total, line in
            guard let record = try? WorkstateCoding.makeDecoder().decode(AgentRunRecord.self, from: Data(line)),
                  record.timestamp >= start else { return }
            total += record.usage?.inputTokens ?? 0
        }
    }

    private func runtimeProfile(_ role: AgentRole) throws -> RuntimeProfilePayload {
        let repository = WorkstateRepository(paths: WorkstatePaths(root: runtimeRoot))
        let workspaceHasProjects = (try? repository.load().projects.isEmpty == false) ?? false
        let settings = try settingsRepository.load(workspaceHasProjects: workspaceHasProjects)
        return RuntimeProfilePayload(settings.profile(for: role))
    }

    private func run<Request: Encodable, Result: Decodable>(
        _ request: Request,
        timeout: TimeInterval
    ) throws -> RuntimeEnvelope<Result> {
        guard FileManager.default.isExecutableFile(atPath: nodePath) else {
            throw AgentRuntimeError.missingNode(nodePath)
        }
        guard FileManager.default.fileExists(atPath: runtimeScript.path) else {
            throw AgentRuntimeError.missingRuntime(runtimeScript.path)
        }
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        let requestURL = runtimeRoot.appendingPathComponent("agent-request-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: requestURL) }
        try WorkstateCoding.makeEncoder().encode(request).write(to: requestURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [runtimeScript.path, requestURL.path]
        process.currentDirectoryURL = runtimeScript.deletingLastPathComponent().deletingLastPathComponent()
        let output = Pipe()
        let error = Pipe()
        let outputCapture = PipeCapture(pipe: output, maximumBytes: 64 * 1024 * 1024)
        let errorCapture = PipeCapture(pipe: error, maximumBytes: 8 * 1024 * 1024)
        process.standardOutput = output
        process.standardError = error
        outputCapture.start()
        errorCapture.start()
        defer {
            outputCapture.cancel()
            errorCapture.cancel()
        }
        try process.run()
        processRegistry.register(process)
        defer { processRegistry.clear(process) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            processRegistry.terminate(process)
            throw AgentRuntimeError.timedOut(Int(timeout))
        }

        let outputResult = outputCapture.finish()
        let errorResult = errorCapture.finish()
        guard !outputResult.exceededLimit else {
            throw AgentRuntimeError.failed("Agent runtime output exceeded 64 MiB")
        }
        let errorText = String(
            data: errorResult.data,
            encoding: .utf8
        ) ?? ""
        guard !errorResult.exceededLimit else {
            throw AgentRuntimeError.failed("Agent runtime error output exceeded 8 MiB")
        }
        guard process.terminationStatus == 0 else {
            throw AgentRuntimeError.failed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try JSONDecoder().decode(RuntimeEnvelope<Result>.self, from: outputResult.data)
    }

    private func appendRun<Result: Encodable>(
        _ envelope: RuntimeEnvelope<Result>,
        segmentID: String
    ) throws {
        let url = runtimeRoot.appendingPathComponent("agent-runs.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let record = AgentRunRecord(
            timestamp: Date(),
            mode: envelope.mode,
            segmentID: segmentID,
            runtimeThreadID: envelope.runtimeThreadId,
            usage: envelope.usage
        )
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func appendDecision<Result: Encodable>(
        _ envelope: RuntimeEnvelope<Result>,
        segmentID: String
    ) throws {
        let url = runtimeRoot.appendingPathComponent("agent-decisions.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let record = AgentDecisionRecord(
            timestamp: Date(),
            mode: envelope.mode,
            segmentID: segmentID,
            runtimeThreadID: envelope.runtimeThreadId,
            result: envelope.result
        )
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let pipe: Pipe
    private let maximumBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var exceededLimit = false

    init(pipe: Pipe, maximumBytes: Int) {
        self.pipe = pipe
        self.maximumBytes = maximumBytes
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.captureAvailableData(from: handle)
        }
    }

    func finish() -> (data: Data, exceededLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        pipe.fileHandleForReading.readabilityHandler = nil
        while true {
            let remaining = (try? pipe.fileHandleForReading.read(upToCount: 1024 * 1024)) ?? nil
            guard let remaining, !remaining.isEmpty else { break }
            append(remaining)
        }
        return (data, exceededLimit)
    }

    func cancel() {
        lock.lock()
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.unlock()
    }

    private func captureAvailableData(from handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        append(chunk)
    }

    private func append(_ chunk: Data) {
        let remainingCapacity = maximumBytes - data.count
        guard remainingCapacity > 0 else {
            exceededLimit = true
            return
        }
        if chunk.count > remainingCapacity {
            data.append(chunk.prefix(remainingCapacity))
            exceededLimit = true
        } else {
            data.append(chunk)
        }
    }
}

private final class AgentProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?

    func register(_ process: Process) {
        lock.lock()
        activeProcess = process
        lock.unlock()
    }

    func clear(_ process: Process) {
        lock.lock()
        if activeProcess?.processIdentifier == process.processIdentifier {
            activeProcess = nil
        }
        lock.unlock()
    }

    func cancelActiveProcess() {
        lock.lock()
        let process = activeProcess
        lock.unlock()
        guard let process else { return }
        terminate(process)
    }

    func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let descendants = Process()
        descendants.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        descendants.arguments = ["-TERM", "-P", String(process.processIdentifier)]
        try? descendants.run()
        descendants.waitUntilExit()
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

public struct RouteResult: Codable, Equatable, Sendable {
    public var action: String
    public var projectId: String
    public var projectName: String
    public var projectSummary: String
    public var confidence: Double
    public var reason: String

    public init(
        action: String,
        projectId: String,
        projectName: String,
        projectSummary: String,
        confidence: Double,
        reason: String
    ) {
        self.action = action
        self.projectId = projectId
        self.projectName = projectName
        self.projectSummary = projectSummary
        self.confidence = confidence
        self.reason = reason
    }
}

public struct BatchRouteDecision: Codable, Equatable, Sendable {
    public var segmentId: String
    public var action: String
    public var projectId: String
    public var projectName: String
    public var projectSummary: String
    public var confidence: Double
    public var reason: String

    public var routeResult: RouteResult {
        RouteResult(
            action: action,
            projectId: projectId,
            projectName: projectName,
            projectSummary: projectSummary,
            confidence: confidence,
            reason: reason
        )
    }
}

public struct StewardResult: Codable, Equatable, Sendable {
    public var classification: String
    public var title: String
    public var summary: String
    public var worklineAction: String
    public var worklineId: String
    public var worklineTitle: String
    public var worklineObjective: String
    public var branchFromWorklineId: String
    public var isParallel: Bool?
    public var nextFocusedWorklineId: String?
    public var closureDisposition: String?
    public var carryoverTitle: String?
    public var carryoverSummary: String?
    public var carryoverQuestions: [String]?
    public var kind: String
    public var stage: String
    public var delivery: String
    public var facts: [String]
    public var openIssues: [String]

    public init(
        classification: String,
        title: String,
        summary: String,
        worklineAction: String,
        worklineId: String,
        worklineTitle: String,
        worklineObjective: String,
        branchFromWorklineId: String,
        isParallel: Bool? = nil,
        nextFocusedWorklineId: String? = nil,
        closureDisposition: String? = nil,
        carryoverTitle: String? = nil,
        carryoverSummary: String? = nil,
        carryoverQuestions: [String]? = nil,
        kind: String,
        stage: String,
        delivery: String,
        facts: [String],
        openIssues: [String]
    ) {
        self.classification = classification
        self.title = title
        self.summary = summary
        self.worklineAction = worklineAction
        self.worklineId = worklineId
        self.worklineTitle = worklineTitle
        self.worklineObjective = worklineObjective
        self.branchFromWorklineId = branchFromWorklineId
        self.isParallel = isParallel
        self.nextFocusedWorklineId = nextFocusedWorklineId
        self.closureDisposition = closureDisposition
        self.carryoverTitle = carryoverTitle
        self.carryoverSummary = carryoverSummary
        self.carryoverQuestions = carryoverQuestions
        self.kind = kind
        self.stage = stage
        self.delivery = delivery
        self.facts = facts
        self.openIssues = openIssues
    }
}

public struct BatchStewardDecision: Codable, Equatable, Sendable {
    public var segmentId: String
    public var result: StewardResult
}

public struct BatchStewardResult: Codable, Equatable, Sendable {
    public var decisions: [BatchStewardDecision]
}

public struct DistillationResult: Codable, Equatable, Sendable {
    public var items: [DistilledEvidenceItem]
}

public struct ProjectOwnerChatResult: Codable, Equatable, Sendable {
    public var reply: String
    public var topicUpdates: [ProjectOwnerTopicUpdate]
}

public struct ProjectOwnerChatResponse: Equatable, Sendable {
    public var reply: String
    public var topicUpdates: [ProjectOwnerTopicUpdate]
    public var runtimeThreadID: String
}

public struct GlobalChatRouteResponse: Equatable, Sendable {
    public var projectID: String
    public var reason: String
    public var runtimeThreadID: String
}

public struct CollaborationStewardResponse: Equatable, Sendable {
    public var reply: String
    public var mutations: [CollaborationProfileMutation]
    public var runtimeThreadID: String
}

private struct CollaborationStewardResult: Codable {
    var reply: String
    var mutations: [CollaborationProfileMutation]
}

private struct GlobalChatRouteResult: Codable {
    var projectId: String
    var reason: String
}

public struct ProjectOwnerTopicUpdate: Codable, Equatable, Sendable {
    public var action: String
    public var topicId: String
    public var title: String
    public var summary: String
    public var status: String
    public var kind: String
    public var disposition: String
    public var currentUnderstanding: String
    public var proposedDirection: String
    public var deferredReason: String
    public var revisitTrigger: String
    public var openQuestions: [String]
    public var noteKind: String
    public var noteTitle: String
    public var noteDetail: String
}

public struct BriefComposerResult: Codable, Equatable, Sendable {
    public var overview: String
    public var projectSummaries: [BriefProjectSummaryResult]
    public var nextStep: String
}

public struct BriefProjectSummaryResult: Codable, Equatable, Sendable {
    public var projectId: String
    public var summary: String
}

public struct DistilledEvidenceItem: Codable, Equatable, Sendable {
    public var category: String
    public var title: String
    public var summary: String
    public var timestamp: String
    public var worklineHint: String
    public var status: String
    public var kind: String
    public var stage: String
    public var delivery: String
    public var facts: [String]
    public var decisions: [String]
    public var evidenceIds: [String]
}

public struct RebuildDistilledChunk: Codable, Equatable, Sendable {
    public var schemaVersion: Int?
    public var chunkIndex: Int
    public var chunkCount: Int
    public var evidenceIds: [String]
    public var items: [DistilledEvidenceItem]

    public init(
        schemaVersion: Int? = 2,
        chunkIndex: Int,
        chunkCount: Int,
        evidenceIds: [String],
        items: [DistilledEvidenceItem]
    ) {
        self.schemaVersion = schemaVersion
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.evidenceIds = evidenceIds
        self.items = items
    }
}

private struct RouteRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segment: SessionSegment
    var projects: [PortfolioProjectPayload]
    var priorRoute: RouteBindingPayload?
    var recentTurns: [SessionSegment]
}

private struct BatchRouteRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segments: [BatchRouteSegmentPayload]
    var projects: [PortfolioProjectPayload]
    var routeHints: [BatchRouteHintPayload]
}

private struct BatchRouteSegmentPayload: Codable {
    var id: String
    var threadID: String
    var turnID: String
    var cwd: String
    var userText: String
    var timestamp: Date

    init(segment: SessionSegment) {
        id = segment.id
        threadID = segment.threadID
        turnID = segment.turnID
        cwd = segment.cwd
        userText = segment.userText
        timestamp = segment.timestamp
    }
}

private struct BatchRouteHintPayload: Codable {
    var threadID: String
    var projectID: String
}

private struct BatchRouteResult: Codable {
    var routes: [BatchRouteDecision]
}

private struct PortfolioProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
    }
}

private struct RouteBindingPayload: Codable {
    var threadID: String
    var turnID: String
    var projectID: String
    var updatedAt: Date

    init(binding: ThreadRouteBinding) {
        threadID = binding.threadID
        turnID = binding.turnID
        projectID = binding.projectID
        updatedAt = binding.updatedAt
    }
}

private struct StewardRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segment: SessionSegment
    var project: StewardProjectPayload
}

private struct BatchStewardRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segments: [SessionSegment]
    var project: StewardProjectPayload
}

private struct RebuildRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: RebuildProjectPayload
    var evidencePath: String
    var sourceThreadIds: [String]
}

private struct DistillRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: ProjectPayload
    var chunkIndex: Int
    var chunkCount: Int
    var segments: [SessionSegment]
}

private struct OwnerChatRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: StewardProjectPayload
    var history: [ProjectOwnerMessage]
    var message: String
    var activeTopicId: String
}

private struct GlobalChatRouteRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var message: String
    var recentMessages: [GlobalChatMessage]
    var projects: [PortfolioProjectPayload]
}

private struct CollaborationStewardRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var collaborationProfile: CollaborationProfile
    var history: [CollaborationMessage]
    var message: String
}

private struct BriefRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var dateKey: String
    var sourceRevision: String
    var projects: [BriefProjectPayload]
}

private struct RuntimeProfilePayload: Codable {
    var model: String
    var reasoning: String

    init(_ profile: AgentProfile) {
        model = profile.modelID
        reasoning = profile.effort.rawValue
    }
}

private struct BriefProjectPayload: Codable {
    var projectId: String
    var projectName: String
    var projectStatus: String
    var records: [BriefRecordPayload]

    init(brief: DailyProjectBrief, project: ProjectRecord) {
        projectId = brief.projectID
        projectName = brief.projectName
        projectStatus = project.status.rawValue
        records = (brief.progress + brief.confirmed + brief.unresolved + brief.resumePoints)
            .map(BriefRecordPayload.init)
    }
}

private struct BriefRecordPayload: Codable {
    var id: String
    var kind: String
    var title: String
    var detail: String

    init(item: DailyBriefItem) {
        id = item.id
        kind = item.kind.rawValue
        title = item.title
        detail = item.detail
    }
}

private struct ProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var focusedWorklineId: String
    var activeWorklines: [WorklinePayload]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
        focusedWorklineId = project.focusedTaskID ?? ""
        activeWorklines = project.tasks
            .filter { $0.status != .completed && $0.status != .abandoned }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(WorklinePayload.init)
    }
}

private struct StewardProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var focusedWorklineId: String
    var activeWorklines: [WorklinePayload]
    var currentUnderstanding: [String]
    var acceptedDecisions: [String]
    var forbiddenDirections: [String]
    var openIssues: [String]
    var recentDeltas: [DeltaPayload]
    var topics: [TopicPayload]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
        focusedWorklineId = project.focusedTaskID ?? ""
        activeWorklines = project.tasks
            .filter { $0.status != .completed && $0.status != .abandoned }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(WorklinePayload.init)
        currentUnderstanding = project.context.understanding
            .filter { $0.status == .confirmed || $0.status == .observed }
            .map(\.text)
        acceptedDecisions = project.context.acceptedDecisions.map(\.text)
        forbiddenDirections = project.context.forbiddenDirections
        openIssues = project.context.openIssues
        recentDeltas = project.events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(6)
            .map(DeltaPayload.init)
        topics = project.topics
            .filter { $0.status == .captured || $0.status == .discussing }
            .map(TopicPayload.init)
    }
}

private struct TopicPayload: Codable {
    var id: String
    var title: String
    var summary: String
    var status: String
    var kind: String
    var disposition: String
    var currentUnderstanding: String
    var proposedDirection: String
    var openQuestions: [String]

    init(topic: ProjectTopic) {
        id = topic.id
        title = topic.title
        summary = topic.summary
        status = topic.status.rawValue
        kind = topic.kind.rawValue
        disposition = (topic.disposition ?? .futureDecision).rawValue
        currentUnderstanding = topic.currentUnderstanding
        proposedDirection = topic.proposedDirection
        openQuestions = topic.openQuestions
    }
}

private struct RebuildProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var activeWorklines: [WorklinePayload]
    var currentUnderstanding: [String]
    var acceptedDecisions: [String]
    var forbiddenDirections: [String]
    var openIssues: [String]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
        activeWorklines = project.activeTasks.map(WorklinePayload.init)
        currentUnderstanding = project.context.understanding.map(\.text)
        acceptedDecisions = project.context.acceptedDecisions.map(\.text)
        forbiddenDirections = project.context.forbiddenDirections
        openIssues = project.context.openIssues
    }
}

private struct WorklinePayload: Codable {
    var id: String
    var title: String
    var objective: String
    var status: String
    var stage: String

    init(task: TaskRecord) {
        id = task.id
        title = task.title
        objective = task.objective
        status = task.status.rawValue
        stage = task.currentStage.rawValue
    }
}

private struct DeltaPayload: Codable {
    var title: String
    var summary: String
    var kind: String
    var timestamp: Date

    init(event: ProjectEvent) {
        title = event.title
        summary = event.summary
        kind = event.kind.rawValue
        timestamp = event.timestamp
    }
}

private struct RuntimeEnvelope<Result: Codable>: Codable {
    var mode: String
    var runtimeThreadId: String
    var usage: AgentUsage?
    var result: Result
}

private struct AgentUsage: Codable, Equatable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
    }
}

private struct AgentRunRecord: Codable {
    var timestamp: Date
    var mode: String
    var segmentID: String
    var runtimeThreadID: String
    var usage: AgentUsage?
}

private struct AgentDecisionRecord<Result: Encodable>: Encodable {
    var timestamp: Date
    var mode: String
    var segmentID: String
    var runtimeThreadID: String
    var result: Result
}

public enum AgentRuntimeError: LocalizedError {
    case missingNode(String)
    case missingRuntime(String)
    case failed(String)
    case timedOut(Int)

    public var errorDescription: String? {
        switch self {
        case .missingNode(let path): "Node.js executable not found at \(path)"
        case .missingRuntime(let path): "Workstate Agent Runtime not found at \(path)"
        case .failed(let message): "Workstate Agent Runtime failed: \(message)"
        case .timedOut(let seconds): "Workstate Agent Runtime timed out after \(seconds) seconds"
        }
    }
}
