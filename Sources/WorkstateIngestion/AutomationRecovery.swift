import Foundation
import WorkstateCore

public struct AutomationRecoveryResult: Sendable {
    public var removedEvidenceCount: Int
    public var removedReviewCount: Int
}

public struct AutomationRecovery: Sendable {
    public let service: WorkstateService
    public let scanner: CodexSessionScanner
    public let runtimeRoot: URL

    public init(
        service: WorkstateService = .init(),
        scanner: CodexSessionScanner = .init(),
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root
    ) {
        self.service = service
        self.scanner = scanner
        self.runtimeRoot = runtimeRoot
    }

    public func run() throws -> AutomationRecoveryResult {
        try migrateWorklineLifecycleRecords()
        let marker = runtimeRoot.appendingPathComponent("internal-session-cleanup-v7.done")
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            return AutomationRecoveryResult(removedEvidenceCount: 0, removedReviewCount: 0)
        }

        let snapshot = try service.snapshot()
        let pendingReviewIDs = Set(snapshot.reviewInbox.filter { $0.status == .pending }.map(\.id))
        _ = try service.removeReviews(ids: pendingReviewIDs)

        let evidenceURL = runtimeRoot.appendingPathComponent("evidence.jsonl")
        let evidence = try readEvidence(at: evidenceURL)
        let internalEvidence = evidence.filter(isInternalAgentSegment)
        let internalThreadIDs = Set(internalEvidence.map(\.threadID))
            .union(try scanner.loadState().excludedThreadIDs)
        let internalSourceIDs = Set(snapshot.sources.compactMap { source -> String? in
            if source.locator.contains("/Workstate/AgentRuntime") ||
                internalThreadIDs.contains(source.threadID) {
                return source.id
            }
            return nil
        })

        if !internalEvidence.isEmpty {
            let backup = runtimeRoot.appendingPathComponent(
                "evidence-internal-backup-\(Int(Date().timeIntervalSince1970)).jsonl"
            )
            try Data(contentsOf: evidenceURL).write(to: backup, options: .atomic)
            try writeEvidence(
                evidence.filter { !isInternalAgentSegment($0) },
                to: evidenceURL
            )
        }
        _ = try service.removeSourceArtifacts(sourceIDs: internalSourceIDs)

        let generatedEventTimestamps = Dictionary(
            evidence
                .filter { !isInternalAgentSegment($0) }
                .map { segment in
                    ("delta-\(segment.threadID)-\(segment.turnID)", segment.timestamp)
                },
            uniquingKeysWith: { _, latest in latest }
        )
        _ = try service.repairEventTimestamps(generatedEventTimestamps)

        let retainedEvidenceIDs = Set(evidence.filter { !isInternalAgentSegment($0) }.map(\.id))
        let retainedPendingIDs = try scanner.loadState().pendingSegmentIDs.filter(retainedEvidenceIDs.contains)
        try scanner.replacePending(segmentIDs: retainedPendingIDs)
        for threadID in internalThreadIDs {
            try scanner.excludeThread(threadID)
        }

        try Data(Date().formatted(.iso8601).utf8).write(to: marker, options: .atomic)
        return AutomationRecoveryResult(
            removedEvidenceCount: internalEvidence.count,
            removedReviewCount: pendingReviewIDs.count
        )
    }

    private func migrateWorklineLifecycleRecords() throws {
        let marker = runtimeRoot.appendingPathComponent("workline-lifecycle-v8.done")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let stateURL = runtimeRoot.appendingPathComponent("ingestion-state.json")
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            try Data(Date().formatted(.iso8601).utf8).write(to: marker, options: .atomic)
            return
        }

        let data = try Data(contentsOf: stateURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var records = root["processingRecords"] as? [String: Any] else {
            throw WorkstateStorageError.invalidState("Cannot migrate Workstate processing records")
        }
        var changed = false
        for (id, value) in records {
            guard var record = value as? [String: Any],
                  var steward = record["steward"] as? [String: Any],
                  steward["worklineAction"] == nil else { continue }
            let worklineID = steward["worklineId"] as? String ?? ""
            steward["worklineAction"] = worklineID.isEmpty ? "none" : "continue_existing"
            steward["worklineTitle"] = ""
            steward["worklineObjective"] = ""
            steward["branchFromWorklineId"] = ""
            record["steward"] = steward
            records[id] = record
            changed = true
        }
        if changed {
            let backup = runtimeRoot.appendingPathComponent(
                "ingestion-state-pre-workline-v8-\(Int(Date().timeIntervalSince1970)).json"
            )
            try data.write(to: backup, options: .atomic)
            root["processingRecords"] = records
            let migrated = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try migrated.write(to: stateURL, options: .atomic)
        }
        try Data(Date().formatted(.iso8601).utf8).write(to: marker, options: .atomic)
    }

    private func readEvidence(at url: URL) throws -> [SessionSegment] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 0x0A).map { line in
            try WorkstateCoding.makeDecoder().decode(SessionSegment.self, from: Data(line))
        }
    }

    private func writeEvidence(_ segments: [SessionSegment], to url: URL) throws {
        var data = Data()
        for segment in segments {
            data.append(try WorkstateCoding.makeEncoder(pretty: false).encode(segment))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private func isWorkstateAgentCWD(_ cwd: String) -> Bool {
        cwd.contains("/Workstate/AgentRuntime")
    }

    private func isInternalAgentSegment(_ segment: SessionSegment) -> Bool {
        if isWorkstateAgentCWD(segment.cwd) { return true }
        let url = URL(fileURLWithPath: segment.sourcePath)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024 * 1024),
              let newline = data.firstIndex(of: 0x0A),
              let object = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else {
            return false
        }
        let originator = payload["originator"] as? String ?? ""
        let source = payload["source"] as? [String: Any]
        return originator == "codex_sdk_ts" || source?["subagent"] != nil
    }
}
