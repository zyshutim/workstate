import Foundation
import WorkstateCore

public struct AgentRuntimeClient: Sendable {
    public let runtimeScript: URL
    public let nodePath: String
    public let runtimeRoot: URL

    public init(
        runtimeScript: URL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["WORKSTATE_AGENT_RUNTIME"]
                ?? "/Users/timshu/Documents/Workstate/AgentRuntime/dist/index.js"
        ),
        nodePath: String = ProcessInfo.processInfo.environment["WORKSTATE_NODE_PATH"] ?? "/opt/homebrew/bin/node",
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root
    ) {
        self.runtimeScript = runtimeScript
        self.nodePath = nodePath
        self.runtimeRoot = runtimeRoot
    }

    public func route(
        segment: SessionSegment,
        workspace: WorkspaceSnapshot,
        scanner: CodexSessionScanner
    ) throws -> RouteResult {
        let request = RouteRequest(
            mode: "route",
            segment: segment,
            projects: workspace.projects.map(ProjectPayload.init)
        )
        let envelope: RuntimeEnvelope<RouteResult> = try run(request)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: segment.id)
        return envelope.result
    }

    public func steward(
        segment: SessionSegment,
        project: ProjectRecord,
        scanner: CodexSessionScanner
    ) throws -> StewardResult {
        let request = StewardRequest(
            mode: "steward",
            segment: segment,
            project: StewardProjectPayload(project: project)
        )
        let envelope: RuntimeEnvelope<StewardResult> = try run(request)
        try scanner.excludeThread(envelope.runtimeThreadId)
        try appendRun(envelope, segmentID: segment.id)
        return envelope.result
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

    private func run<Request: Encodable, Result: Decodable>(_ request: Request) throws -> RuntimeEnvelope<Result> {
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
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw AgentRuntimeError.failed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try JSONDecoder().decode(RuntimeEnvelope<Result>.self, from: outputData)
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
}

public struct RouteResult: Codable, Equatable, Sendable {
    public var action: String
    public var projectId: String
    public var worklineHint: String
    public var confidence: Double
    public var reason: String
}

public struct StewardResult: Codable, Equatable, Sendable {
    public var classification: String
    public var title: String
    public var summary: String
    public var worklineId: String
    public var kind: String
    public var stage: String
    public var delivery: String
    public var facts: [String]
    public var openIssues: [String]
    public var review: StewardReviewProposal
}

public struct StewardReviewProposal: Codable, Equatable, Sendable {
    public var kind: String
    public var reason: String
    public var previousValue: String
    public var proposedValue: String
    public var proposedChanges: [String]
}

private struct RouteRequest: Codable {
    var mode: String
    var segment: SessionSegment
    var projects: [ProjectPayload]
}

private struct StewardRequest: Codable {
    var mode: String
    var segment: SessionSegment
    var project: StewardProjectPayload
}

private struct ProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var activeWorklines: [WorklinePayload]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
        activeWorklines = project.activeTasks.map(WorklinePayload.init)
    }
}

private struct StewardProjectPayload: Codable {
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
    var recentDeltas: [DeltaPayload]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
        activeWorklines = project.activeTasks.map(WorklinePayload.init)
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

public enum AgentRuntimeError: LocalizedError {
    case missingNode(String)
    case missingRuntime(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .missingNode(let path): "Node.js executable not found at \(path)"
        case .missingRuntime(let path): "Workstate Agent Runtime not found at \(path)"
        case .failed(let message): "Workstate Agent Runtime failed: \(message)"
        }
    }
}
