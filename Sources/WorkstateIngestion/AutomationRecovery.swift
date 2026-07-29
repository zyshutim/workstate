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
        let marker = runtimeRoot.appendingPathComponent("pointer-source-backend-v9.done")
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            return AutomationRecoveryResult(removedEvidenceCount: 0, removedReviewCount: 0)
        }
        try Data(Date().formatted(.iso8601).utf8).write(to: marker, options: .atomic)
        return AutomationRecoveryResult(removedEvidenceCount: 0, removedReviewCount: 0)
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

}
