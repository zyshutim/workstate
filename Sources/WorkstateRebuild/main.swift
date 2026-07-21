import Foundation
import WorkstateCore
import WorkstateIngestion

@main
struct WorkstateRebuild {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("workstate-rebuild: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() throws {
        let raw = Array(CommandLine.arguments.dropFirst())
        guard let command = raw.first else { throw RebuildCLIError.missingCommand }
        let arguments = RebuildArguments(Array(raw.dropFirst()))
        switch command {
        case "generate":
            try generate(arguments)
        case "apply":
            try apply(arguments)
        case "reconcile":
            try reconcile(arguments)
        default:
            throw RebuildCLIError.unknownCommand(command)
        }
    }

    private static func generate(_ arguments: RebuildArguments) throws {
        let projectID = try arguments.required("project")
        let threadIDs = arguments.values("thread")
        guard !threadIDs.isEmpty else { throw RebuildCLIError.missingOption("--thread") }

        let service = WorkstateService()
        guard let project = try service.snapshot().project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }
        let rebuildRoot = WorkstatePaths.defaultPaths().root.appendingPathComponent("rebuild", isDirectory: true)
        try FileManager.default.createDirectory(at: rebuildRoot, withIntermediateDirectories: true)
        let evidenceURL = rebuildRoot.appendingPathComponent("\(projectID)-evidence.jsonl")
        let distillationURL = rebuildRoot.appendingPathComponent("\(projectID)-distilled.jsonl")
        let proposalURL = rebuildRoot.appendingPathComponent("\(projectID)-proposal.json")
        let sessionURLs = try threadIDs.map(findSession(threadID:))
        try extractEvidence(from: sessionURLs, to: evidenceURL)

        let evidenceCount = try countLines(evidenceURL)
        guard evidenceCount > 0 else {
            throw RebuildCLIError.invalidEvidence("No completed Codex turns were extracted")
        }
        let evidence = try readEvidence(evidenceURL)
        let actualThreadIDs = Array(Set(evidence.map(\.threadID))).sorted()
        let chunks = try makeEvidenceChunks(evidence)
        let scanner = CodexSessionScanner()
        let runtime = AgentRuntimeClient()
        let existing = try readDistillations(distillationURL)
        var distilledByIndex: [Int: RebuildDistilledChunk] = [:]
        for chunk in existing where chunk.schemaVersion == 2 && chunk.chunkCount == chunks.count && chunk.chunkIndex < chunks.count {
            guard chunk.evidenceIds == chunks[chunk.chunkIndex].map(\.id) else { continue }
            distilledByIndex[chunk.chunkIndex] = chunk
        }
        for (index, chunk) in chunks.enumerated() {
            if distilledByIndex[index] != nil {
                try printProgress("Reusing distillation chunk \(index + 1)/\(chunks.count)")
                continue
            }
            try printProgress("Distilling chunk \(index + 1)/\(chunks.count) with GPT-5.6-Terra")
            let distilled = try runtime.distill(
                project: project,
                segments: chunk,
                chunkIndex: index,
                chunkCount: chunks.count,
                scanner: scanner
            )
            try validateDistillation(distilled, input: chunk)
            distilledByIndex[index] = distilled
            try writeDistillations(Array(distilledByIndex.values), to: distillationURL)
        }
        let distillations = distilledByIndex.values.sorted { $0.chunkIndex < $1.chunkIndex }
        let coveredEvidenceIDs = distillations.flatMap(\.evidenceIds)
        guard coveredEvidenceIDs == evidence.map(\.id) else {
            throw RebuildCLIError.invalidEvidence("Distillation coverage does not match the complete evidence corpus")
        }
        try writeDistillations(distillations, to: distillationURL)
        try printProgress("Reducing \(distillations.count) complete chunks with GPT-5.6-Sol")
        let proposal = try runtime.rebuild(
            project: project,
            evidencePath: distillationURL.path,
            sourceThreadIDs: actualThreadIDs,
            scanner: scanner
        )
        let data = try WorkstateCoding.makeEncoder().encode(proposal)
        try data.write(to: proposalURL, options: .atomic)
        try printJSON(
            GenerateOutput(
                projectID: projectID,
                evidencePath: evidenceURL.path,
                distillationPath: distillationURL.path,
                proposalPath: proposalURL.path,
                evidenceCount: evidenceCount,
                chunkCount: chunks.count,
                worklineCount: proposal.worklines.count,
                deltaCount: proposal.deltas.count
            )
        )
    }

    private static func apply(_ arguments: RebuildArguments) throws {
        let projectID = try arguments.required("project")
        let rebuildRoot = WorkstatePaths.defaultPaths().root.appendingPathComponent("rebuild", isDirectory: true)
        let evidenceURL = URL(
            fileURLWithPath: arguments.value("evidence")
                ?? rebuildRoot.appendingPathComponent("\(projectID)-evidence.jsonl").path
        )
        let proposalURL = URL(
            fileURLWithPath: arguments.value("proposal")
                ?? rebuildRoot.appendingPathComponent("\(projectID)-proposal.json").path
        )
        let proposal = try JSONDecoder().decode(
            ProjectRebuildProposal.self,
            from: Data(contentsOf: proposalURL)
        )
        guard proposal.projectId == projectID else {
            throw RebuildCLIError.invalidEvidence("Proposal belongs to \(proposal.projectId), not \(projectID)")
        }
        let evidence = try readEvidence(evidenceURL)
        let snapshot = try ProjectRebuildApplier().apply(proposal, evidence: evidence)
        guard let project = snapshot.project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }
        try printJSON(
            ApplyOutput(
                projectID: project.id,
                summary: project.context.currentSummary,
                status: project.status.rawValue,
                worklineCount: project.tasks.count,
                deltaCount: project.events.filter { $0.taskID != nil && $0.kind != .taskStarted }.count,
                sourceCount: project.sourceIDs.count
            )
        )
    }

    private static func reconcile(_ arguments: RebuildArguments) throws {
        let replacements = try arguments.values("relation").map { raw -> RelationSourceReplacement in
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw RebuildCLIError.invalidEvidence("Expected --relation RELATION_ID=SOURCE_ID")
            }
            return RelationSourceReplacement(relationID: parts[0], sourceIDs: [parts[1]])
        }
        let result = try WorkspaceReconciler().reconcile(relationSources: replacements)
        let processedSegmentIDs = arguments.values("processed")
        if !processedSegmentIDs.isEmpty {
            try CodexSessionScanner().markProcessed(segmentIDs: processedSegmentIDs)
        }
        try printJSON(
            ReconcileOutput(
                relationCount: replacements.count,
                sourceCount: result.snapshot.sources.count,
                removedSourceCount: result.removedSourceCount,
                processedSegmentCount: processedSegmentIDs.count
            )
        )
    }

    private static func findSession(threadID: String) throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw RebuildCLIError.sessionNotFound(threadID)
        }
        for case let url as URL in enumerator where url.lastPathComponent.contains(threadID) {
            return url
        }
        throw RebuildCLIError.sessionNotFound(threadID)
    }

    private static func extractEvidence(from inputs: [URL], to output: URL) throws {
        let nodePath = AgentRuntimeClient.defaultNodePath()
        let scriptPath = AgentRuntimeClient.defaultEvidenceExtractor().path
        guard FileManager.default.isExecutableFile(atPath: nodePath) else {
            throw RebuildCLIError.missingExecutable(nodePath)
        }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw RebuildCLIError.missingExecutable(scriptPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [scriptPath, output.path] + inputs.map(\.path)
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw RebuildCLIError.extractionFailed(message)
        }
    }

    private static func readEvidence(_ url: URL) throws -> [SessionSegment] {
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map {
            try WorkstateCoding.makeDecoder().decode(SessionSegment.self, from: Data($0))
        }
    }

    private static func makeEvidenceChunks(
        _ evidence: [SessionSegment],
        maximumEncodedBytes: Int = 90_000
    ) throws -> [[SessionSegment]] {
        let encoder = WorkstateCoding.makeEncoder(pretty: false)
        var chunks: [[SessionSegment]] = []
        var current: [SessionSegment] = []
        var currentBytes = 0
        for segment in evidence {
            let encodedBytes = try encoder.encode(segment).count + 1
            if !current.isEmpty && currentBytes + encodedBytes > maximumEncodedBytes {
                chunks.append(current)
                current = []
                currentBytes = 0
            }
            current.append(segment)
            currentBytes += encodedBytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func readDistillations(_ url: URL) throws -> [RebuildDistilledChunk] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map {
            try WorkstateCoding.makeDecoder().decode(RebuildDistilledChunk.self, from: Data($0))
        }
    }

    private static func validateDistillation(
        _ distillation: RebuildDistilledChunk,
        input: [SessionSegment]
    ) throws {
        let allowed = Set(input.map(\.id))
        guard distillation.evidenceIds == input.map(\.id) else {
            throw RebuildCLIError.invalidEvidence("Distillation wrapper does not preserve input coverage")
        }
        for item in distillation.items {
            guard !item.evidenceIds.isEmpty else {
                throw RebuildCLIError.invalidEvidence("Distilled item has no evidence: \(item.title)")
            }
            for id in item.evidenceIds where !allowed.contains(id) {
                throw RebuildCLIError.invalidEvidence("Distilled item references evidence outside its chunk: \(id)")
            }
            let citedDates = item.evidenceIds.compactMap { id in input.first(where: { $0.id == id })?.timestamp }
            guard let itemDate = parseTimestamp(item.timestamp),
                  citedDates.contains(where: { abs($0.timeIntervalSince(itemDate)) < 1 }) else {
                throw RebuildCLIError.invalidEvidence(
                    "Distilled item timestamp is not copied from cited evidence: \(item.title)"
                )
            }
        }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(raw)
    }

    private static func writeDistillations(
        _ distillations: [RebuildDistilledChunk],
        to url: URL
    ) throws {
        let encoder = WorkstateCoding.makeEncoder(pretty: false)
        var data = Data()
        for chunk in distillations.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
            data.append(try encoder.encode(chunk))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func printProgress(_ message: String) throws {
        try FileHandle.standardError.write(contentsOf: Data("\(message)\n".utf8))
    }

    private static func countLines(_ url: URL) throws -> Int {
        try Data(contentsOf: url).reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try WorkstateCoding.makeEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RebuildCLIError.invalidOutput
        }
        print(string)
    }
}

private struct RebuildArguments {
    var options: [String: [String]] = [:]

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let token = raw[index]
            guard token.hasPrefix("--"), index + 1 < raw.count else {
                index += 1
                continue
            }
            options[String(token.dropFirst(2)), default: []].append(raw[index + 1])
            index += 2
        }
    }

    func value(_ key: String) -> String? { options[key]?.last }
    func values(_ key: String) -> [String] { options[key] ?? [] }

    func required(_ key: String) throws -> String {
        guard let value = value(key), !value.isEmpty else {
            throw RebuildCLIError.missingOption("--\(key)")
        }
        return value
    }
}

private struct GenerateOutput: Codable {
    var projectID: String
    var evidencePath: String
    var distillationPath: String
    var proposalPath: String
    var evidenceCount: Int
    var chunkCount: Int
    var worklineCount: Int
    var deltaCount: Int
}

private struct ApplyOutput: Codable {
    var projectID: String
    var summary: String
    var status: String
    var worklineCount: Int
    var deltaCount: Int
    var sourceCount: Int
}

private struct ReconcileOutput: Codable {
    var relationCount: Int
    var sourceCount: Int
    var removedSourceCount: Int
    var processedSegmentCount: Int
}

private enum RebuildCLIError: LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingOption(String)
    case sessionNotFound(String)
    case missingExecutable(String)
    case invalidEvidence(String)
    case extractionFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingCommand: "Expected generate or apply"
        case .unknownCommand(let command): "Unknown command: \(command)"
        case .missingOption(let option): "Missing option: \(option)"
        case .sessionNotFound(let id): "Codex session not found: \(id)"
        case .missingExecutable(let path): "Required executable not found: \(path)"
        case .invalidEvidence(let message): message
        case .extractionFailed(let message): "Evidence extraction failed: \(message)"
        case .invalidOutput: "Could not encode output"
        }
    }
}
