import Darwin
import Foundation
import WorkstateCore

public struct SessionSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var threadID: String
    public var turnID: String
    public var sourcePath: String
    public var startOffset: UInt64
    public var endOffset: UInt64
    public var cwd: String
    public var userText: String
    public var assistantText: String
    public var timestamp: Date
    public var relatedTurnIDs: [String]?

    public init(
        threadID: String,
        turnID: String,
        sourcePath: String,
        startOffset: UInt64,
        endOffset: UInt64,
        cwd: String,
        userText: String,
        assistantText: String,
        timestamp: Date,
        relatedTurnIDs: [String]? = nil
    ) {
        id = "\(threadID):\(turnID)"
        self.threadID = threadID
        self.turnID = turnID
        self.sourcePath = sourcePath
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.cwd = cwd
        self.userText = userText
        self.assistantText = assistantText
        self.timestamp = timestamp
        self.relatedTurnIDs = relatedTurnIDs
    }
}

public struct ActiveSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(threadID):\(turnID)" }
    public var threadID: String
    public var turnID: String
    public var cwd: String
    public var userText: String
    public var updatedAt: Date

    public init(
        threadID: String,
        turnID: String,
        cwd: String,
        userText: String,
        updatedAt: Date
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.cwd = cwd
        self.userText = userText
        self.updatedAt = updatedAt
    }
}

public struct CodexSessionRecord: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var cwd: String
    public var sourcePath: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        cwd: String,
        sourcePath: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var workspaceName: String {
        let value = URL(fileURLWithPath: cwd).lastPathComponent
        return value.isEmpty ? "其他任务" : value
    }
}

public struct HistoryImportPreview: Equatable, Sendable {
    public var completedTurnCount: Int
    public var evidenceBytes: UInt64

    public init(completedTurnCount: Int, evidenceBytes: UInt64) {
        self.completedTurnCount = completedTurnCount
        self.evidenceBytes = evidenceBytes
    }
}

public struct IngestionSnapshot: Codable, Equatable, Sendable {
    public var initialized: Bool
    public var cursors: [String: SessionCursor]
    public var pendingSegmentIDs: [String]
    public var excludedThreadIDs: [String]
    public var routeBindings: [String: ThreadRouteBinding]?
    public var processingRecords: [String: SegmentProcessingRecord]?
    public var lastScanAt: Date?

    public init(
        initialized: Bool = false,
        cursors: [String: SessionCursor] = [:],
        pendingSegmentIDs: [String] = [],
        excludedThreadIDs: [String] = [],
        routeBindings: [String: ThreadRouteBinding]? = nil,
        processingRecords: [String: SegmentProcessingRecord]? = nil,
        lastScanAt: Date? = nil
    ) {
        self.initialized = initialized
        self.cursors = cursors
        self.pendingSegmentIDs = pendingSegmentIDs
        self.excludedThreadIDs = excludedThreadIDs
        self.routeBindings = routeBindings
        self.processingRecords = processingRecords
        self.lastScanAt = lastScanAt
    }
}

public enum SegmentProcessingStage: String, Codable, Equatable, Sendable {
    case queued
    case routing
    case routed
    case stewarding
    case stewarded
    case applying
    case completed
    case failed
}

public struct SegmentProcessingRecord: Codable, Equatable, Sendable {
    public var segmentID: String
    public var stage: SegmentProcessingStage
    public var route: RouteResult?
    public var steward: StewardResult?
    public var failedStage: SegmentProcessingStage?
    public var error: String
    public var updatedAt: Date

    public init(
        segmentID: String,
        stage: SegmentProcessingStage = .queued,
        route: RouteResult? = nil,
        steward: StewardResult? = nil,
        failedStage: SegmentProcessingStage? = nil,
        error: String = "",
        updatedAt: Date = Date()
    ) {
        self.segmentID = segmentID
        self.stage = stage
        self.route = route
        self.steward = steward
        self.failedStage = failedStage
        self.error = error
        self.updatedAt = updatedAt
    }
}

public struct ThreadRouteBinding: Codable, Equatable, Sendable {
    public var threadID: String
    public var turnID: String
    public var projectID: String
    public var updatedAt: Date

    public init(threadID: String, turnID: String, projectID: String, updatedAt: Date = Date()) {
        self.threadID = threadID
        self.turnID = turnID
        self.projectID = projectID
        self.updatedAt = updatedAt
    }
}

public struct SessionCursor: Codable, Equatable, Sendable {
    public var offset: UInt64
    public var threadID: String
    public var cwd: String
    public var activeTurnID: String
    public var activeTurnOffset: UInt64
    public var userText: String
    public var lastActivityAt: Date?
    public var isInternalAgentSession: Bool?

    public init(
        offset: UInt64 = 0,
        threadID: String = "",
        cwd: String = "",
        activeTurnID: String = "",
        activeTurnOffset: UInt64 = 0,
        userText: String = "",
        lastActivityAt: Date? = nil,
        isInternalAgentSession: Bool? = nil
    ) {
        self.offset = offset
        self.threadID = threadID
        self.cwd = cwd
        self.activeTurnID = activeTurnID
        self.activeTurnOffset = activeTurnOffset
        self.userText = userText
        self.lastActivityAt = lastActivityAt
        self.isInternalAgentSession = isInternalAgentSession
    }
}

public struct ScannerDiagnostics: Equatable, Sendable {
    public var fullScans = 0
    public var changedFileScans = 0
    public var metadataReads = 0
    public var metadataBytesRead: UInt64 = 0
    public var evidenceIndexLoads = 0
}

private final class SessionScannerStorage: @unchecked Sendable {
    let lock = NSRecursiveLock()
    var state: IngestionSnapshot?
    var evidenceLocations: [String: EvidenceLocation]?
    var diagnostics = ScannerDiagnostics()
}

private struct EvidenceLocation {
    var offset: UInt64
    var length: Int
    var threadID: String
    var timestamp: Date
}

private struct SessionMetadata {
    var threadID: String
    var cwd: String
    var isInternalAgentSession: Bool
    var createdAt: Date?
}

public struct CodexSessionScanner: Sendable {
    public let sessionsRoot: URL
    public let runtimeRoot: URL
    private let storage: SessionScannerStorage

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root
    ) {
        self.sessionsRoot = canonicalFileURL(sessionsRoot)
        self.runtimeRoot = canonicalFileURL(runtimeRoot)
        storage = SessionScannerStorage()
    }

    public var stateURL: URL {
        runtimeRoot.appendingPathComponent("ingestion-state.json")
    }

    public var evidenceURL: URL {
        runtimeRoot.appendingPathComponent("evidence.jsonl")
    }

    public func scan(minimumTimestamp: Date? = nil) throws -> [SessionSegment] {
        try synchronized {
            storage.diagnostics.fullScans += 1
            return try scanUnlocked(files: sessionFiles(), minimumTimestamp: minimumTimestamp)
        }
    }

    public func scanChangedFiles(
        _ paths: [String],
        minimumTimestamp: Date? = nil
    ) throws -> [SessionSegment] {
        try synchronized {
            storage.diagnostics.changedFileScans += 1
            let rootPath = sessionsRoot.path
            let files = Set(paths.compactMap { path -> URL? in
                let url = canonicalFileURL(URL(fileURLWithPath: path))
                guard url.pathExtension == "jsonl",
                      url.path.hasPrefix(rootPath + "/"),
                      FileManager.default.fileExists(atPath: url.path) else {
                    return nil
                }
                return url
            })
            return try scanUnlocked(
                files: files.sorted { $0.path < $1.path },
                minimumTimestamp: minimumTimestamp
            )
        }
    }

    public func diagnostics() -> ScannerDiagnostics {
        synchronized { storage.diagnostics }
    }

    private func scanUnlocked(files: [URL], minimumTimestamp: Date?) throws -> [SessionSegment] {
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        var state = try loadStateUnlocked()
        let previousState = state
        var segments: [SessionSegment] = []

        if !state.initialized {
            for file in files {
                let cursor = try primeCursor(for: file)
                state.cursors[file.path] = cursor
                if !cursor.threadID.isEmpty, cursor.isInternalAgentSession == true {
                    state.excludedThreadIDs.append(cursor.threadID)
                }
            }
            state.excludedThreadIDs = Array(Set(state.excludedThreadIDs)).sorted()
            state.initialized = true
            state.lastScanAt = Date()
            try saveState(state)
            return []
        }

        var excludedThreadIDs = Set(state.excludedThreadIDs)
        for file in files {
            var cursor = state.cursors[file.path] ?? SessionCursor()
            let fileSize = try size(of: file)

            if cursor.isInternalAgentSession == nil, !cursor.threadID.isEmpty {
                cursor.isInternalAgentSession = excludedThreadIDs.contains(cursor.threadID)
            }
            if cursor.threadID.isEmpty || cursor.isInternalAgentSession == nil {
                guard let metadata = try sessionMetadata(for: file) else {
                    state.cursors[file.path] = cursor
                    continue
                }
                cursor.threadID = metadata.threadID
                cursor.cwd = metadata.cwd
                cursor.isInternalAgentSession = metadata.isInternalAgentSession
            }
            if cursor.isInternalAgentSession == true {
                if !cursor.threadID.isEmpty {
                    excludedThreadIDs.insert(cursor.threadID)
                }
                cursor.offset = fileSize
                cursor.activeTurnID = ""
                cursor.userText = ""
                cursor.lastActivityAt = nil
                state.cursors[file.path] = cursor
                continue
            }
            if excludedThreadIDs.contains(cursor.threadID) {
                cursor.offset = fileSize
                state.cursors[file.path] = cursor
                continue
            }
            if fileSize < cursor.offset {
                state.cursors[file.path] = try primeCursor(for: file)
                continue
            }
            guard fileSize > cursor.offset else {
                state.cursors[file.path] = cursor
                continue
            }

            let result = try readAppended(file: file, cursor: cursor)
            cursor = result.cursor
            state.cursors[file.path] = cursor
            segments.append(contentsOf: result.segments.filter { segment in
                guard let minimumTimestamp else { return true }
                return segment.timestamp >= minimumTimestamp
            })
        }

        state.excludedThreadIDs = excludedThreadIDs.sorted()

        if !segments.isEmpty {
            let knownEvidenceIDs = Set(try evidenceLocationIndex().keys)
            segments = Array(Dictionary(
                segments.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            ).values)
            .filter { !knownEvidenceIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
            try appendEvidence(segments)
            let existing = Set(state.pendingSegmentIDs)
            state.pendingSegmentIDs.append(contentsOf: segments.map(\.id).filter { !existing.contains($0) })
            var processing = state.processingRecords ?? [:]
            for segment in segments where processing[segment.id] == nil {
                processing[segment.id] = SegmentProcessingRecord(segmentID: segment.id)
            }
            state.processingRecords = processing
        }
        var comparableState = state
        comparableState.lastScanAt = previousState.lastScanAt
        if comparableState != previousState {
            state.lastScanAt = Date()
            try saveState(state)
        }
        return try loadPendingSegments(ids: state.pendingSegmentIDs)
    }

    public func sessionCatalog(
        indexURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
    ) throws -> [CodexSessionRecord] {
        try synchronized {
            let titles = try loadSessionIndex(indexURL)
            return try sessionFiles().compactMap { file in
                guard let metadata = try sessionMetadata(for: file),
                      !metadata.isInternalAgentSession,
                      !metadata.threadID.isEmpty else {
                    return nil
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                let modifiedAt = attributes[.modificationDate] as? Date ?? Date.distantPast
                let indexed = titles[metadata.threadID]
                let title = indexed?.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return CodexSessionRecord(
                    id: metadata.threadID,
                    title: title?.isEmpty == false ? title! : "未命名任务",
                    cwd: metadata.cwd,
                    sourcePath: file.path,
                    createdAt: metadata.createdAt
                        ?? Self.timestamp(fromTimeOrderedID: metadata.threadID)
                        ?? modifiedAt,
                    updatedAt: max(indexed?.updatedAt ?? Date.distantPast, modifiedAt)
                )
            }
            .sorted { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt ? lhs.title < rhs.title : lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    public func importHistory(
        threadIDs: Set<String>,
        interval: DateInterval
    ) throws -> [SessionSegment] {
        try synchronized {
            guard !threadIDs.isEmpty else {
                throw WorkstateStorageError.invalidState("Select at least one Codex task")
            }
            guard interval.start < interval.end else {
                throw WorkstateStorageError.invalidState("History range must have a start before its end")
            }

            try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
            var state = try loadStateUnlocked()
            var imported: [SessionSegment] = []
            var discovered = Set<String>()
            var excluded = Set(state.excludedThreadIDs)

            for file in try sessionFiles() {
                guard let metadata = try sessionMetadata(for: file), !metadata.threadID.isEmpty else {
                    continue
                }
                if metadata.isInternalAgentSession {
                    excluded.insert(metadata.threadID)
                    state.cursors[file.path] = try primeCursor(for: file)
                    continue
                }

                if threadIDs.contains(metadata.threadID) {
                    discovered.insert(metadata.threadID)
                    let result = try readHistoricalFile(file)
                    var cursor = result.cursor
                    cursor.isInternalAgentSession = false
                    state.cursors[file.path] = cursor
                    imported.append(contentsOf: result.segments.filter {
                        $0.timestamp >= interval.start && $0.timestamp < interval.end
                    })
                } else {
                    state.cursors[file.path] = try primeCursor(for: file)
                }
            }

            let missing = threadIDs.subtracting(discovered)
            guard missing.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "Selected Codex tasks were not found: \(missing.sorted().joined(separator: ", "))"
                )
            }

            imported = Array(
                Dictionary(imported.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values
            )
            .sorted { $0.timestamp < $1.timestamp }

            let known = Set(try evidenceLocationIndex().keys)
            let newSegments = imported.filter { !known.contains($0.id) }
            if !newSegments.isEmpty {
                try appendEvidence(newSegments)
            }

            let importedIDs = imported.map(\.id)
            let pending = Set(state.pendingSegmentIDs)
            state.pendingSegmentIDs.append(contentsOf: importedIDs.filter { !pending.contains($0) })
            var records = state.processingRecords ?? [:]
            for segmentID in importedIDs where records[segmentID] == nil {
                records[segmentID] = SegmentProcessingRecord(segmentID: segmentID)
            }
            state.processingRecords = records
            state.excludedThreadIDs = excluded.sorted()
            state.initialized = true
            state.lastScanAt = Date()
            try saveState(state)
            return try loadPendingSegments(ids: importedIDs)
        }
    }

    public func previewHistory(
        threadIDs: Set<String>,
        interval: DateInterval
    ) throws -> HistoryImportPreview {
        try synchronized {
            guard !threadIDs.isEmpty, interval.start < interval.end else {
                throw WorkstateStorageError.invalidState("History preview requires tasks and a valid range")
            }
            var discovered = Set<String>()
            var turnCount = 0
            var evidenceBytes: UInt64 = 0
            for file in try sessionFiles() {
                guard let metadata = try sessionMetadata(for: file),
                      threadIDs.contains(metadata.threadID),
                      !metadata.isInternalAgentSession else {
                    continue
                }
                discovered.insert(metadata.threadID)
                let metrics = try historicalMetrics(file, interval: interval)
                turnCount += metrics.turnCount
                evidenceBytes += metrics.evidenceBytes
            }
            let missing = threadIDs.subtracting(discovered)
            guard missing.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "Selected Codex tasks were not found: \(missing.sorted().joined(separator: ", "))"
                )
            }
            return HistoryImportPreview(
                completedTurnCount: turnCount,
                evidenceBytes: evidenceBytes
            )
        }
    }

    public func loadState() throws -> IngestionSnapshot {
        try synchronized {
            try loadStateUnlocked()
        }
    }

    public func markProcessed(segmentIDs: [String]) throws {
        try synchronized {
            guard !segmentIDs.isEmpty else { return }
            var state = try loadState()
            let processed = Set(segmentIDs)
            state.pendingSegmentIDs.removeAll { processed.contains($0) }
            try saveState(state)
        }
    }

    public func requeue(segmentIDs: [String]) throws {
        try synchronized {
            guard !segmentIDs.isEmpty else { return }
            var state = try loadState()
            let existing = Set(state.pendingSegmentIDs)
            state.pendingSegmentIDs.append(contentsOf: segmentIDs.filter { !existing.contains($0) })
            var records = state.processingRecords ?? [:]
            for segmentID in segmentIDs {
                var record = records[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
                if record.stage == .failed {
                    if record.steward != nil {
                        record.stage = .stewarded
                    } else if record.route != nil {
                        record.stage = .routed
                    } else {
                        record.stage = .queued
                    }
                    record.failedStage = nil
                    record.error = ""
                    record.updatedAt = Date()
                    records[segmentID] = record
                }
            }
            state.processingRecords = records
            try saveState(state)
        }
    }

    @discardableResult
    public func recoverInterruptedProcessing() throws -> Int {
        try synchronized {
            var state = try loadStateUnlocked()
            var records = state.processingRecords ?? [:]
            var recovered = 0
            for segmentID in state.pendingSegmentIDs {
                guard var record = records[segmentID] else { continue }
                switch record.stage {
                case .routing:
                    record.stage = record.route == nil ? .queued : .routed
                case .stewarding:
                    record.stage = record.steward == nil ? .routed : .stewarded
                case .applying:
                    record.stage = record.steward == nil ? .routed : .stewarded
                default:
                    continue
                }
                record.failedStage = nil
                record.error = ""
                record.updatedAt = Date()
                records[segmentID] = record
                recovered += 1
            }
            if recovered > 0 {
                state.processingRecords = records
                try saveState(state)
            }
            return recovered
        }
    }

    public func replacePending(segmentIDs: [String]) throws {
        try synchronized {
            var state = try loadState()
            state.pendingSegmentIDs = Array(Set(segmentIDs)).sorted()
            var records = state.processingRecords ?? [:]
            for segmentID in state.pendingSegmentIDs where records[segmentID] == nil {
                records[segmentID] = SegmentProcessingRecord(segmentID: segmentID)
            }
            state.processingRecords = records
            try saveState(state)
        }
    }

    public func excludeThread(_ threadID: String) throws {
        try synchronized {
            guard !threadID.isEmpty else { return }
            var state = try loadState()
            if !state.excludedThreadIDs.contains(threadID) {
                state.excludedThreadIDs.append(threadID)
                try saveState(state)
            }
        }
    }

    public func routeBinding(threadID: String) throws -> ThreadRouteBinding? {
        try synchronized {
            try loadState().routeBindings?[threadID]
        }
    }

    public func recordRoute(threadID: String, turnID: String, projectID: String) throws {
        try synchronized {
            guard !threadID.isEmpty, !turnID.isEmpty, !projectID.isEmpty else {
                throw WorkstateStorageError.invalidState("Route binding requires thread, turn, and project ids")
            }
            var state = try loadState()
            var bindings = state.routeBindings ?? [:]
            bindings[threadID] = ThreadRouteBinding(
                threadID: threadID,
                turnID: turnID,
                projectID: projectID
            )
            state.routeBindings = bindings
            try saveState(state)
        }
    }

    public func processingRecord(segmentID: String) throws -> SegmentProcessingRecord {
        try synchronized {
            let state = try loadStateUnlocked()
            return state.processingRecords?[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
        }
    }

    public func beginProcessing(segmentID: String, stage: SegmentProcessingStage) throws {
        try updateProcessingRecord(segmentID: segmentID) { record in
            guard stage == .routing || stage == .stewarding || stage == .applying else {
                throw WorkstateStorageError.invalidState("Unsupported active processing stage: \(stage.rawValue)")
            }
            guard record.stage != .failed && record.stage != .completed else {
                throw WorkstateStorageError.invalidState("Segment \(segmentID) is not eligible for processing")
            }
            record.stage = stage
            record.failedStage = nil
            record.error = ""
        }
    }

    public func recordRouteResult(segmentID: String, route: RouteResult) throws {
        try updateProcessingRecord(segmentID: segmentID) { record in
            record.route = route
            record.stage = .routed
            record.failedStage = nil
            record.error = ""
        }
    }

    public func recordStewardResult(segmentID: String, steward: StewardResult) throws {
        try updateProcessingRecord(segmentID: segmentID) { record in
            guard record.route != nil else {
                throw WorkstateStorageError.invalidState("Steward result requires a persisted route")
            }
            record.steward = steward
            record.stage = .stewarded
            record.failedStage = nil
            record.error = ""
        }
    }

    public func failProcessing(
        segmentID: String,
        failedStage: SegmentProcessingStage,
        error: String
    ) throws {
        try updateProcessingRecord(segmentID: segmentID) { record in
            record.stage = .failed
            record.failedStage = failedStage
            record.error = error
        }
    }

    public func completeProcessing(segmentID: String) throws {
        try updateProcessingRecord(segmentID: segmentID) { record in
            record.stage = .completed
            record.failedStage = nil
            record.error = ""
        }
    }

    private func updateProcessingRecord(
        segmentID: String,
        update: (inout SegmentProcessingRecord) throws -> Void
    ) throws {
        try synchronized {
            var state = try loadStateUnlocked()
            var records = state.processingRecords ?? [:]
            var record = records[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
            try update(&record)
            record.updatedAt = Date()
            records[segmentID] = record
            state.processingRecords = records
            try saveState(state)
        }
    }

    public func recentSegments(threadID: String, before timestamp: Date, limit: Int = 3) throws -> [SessionSegment] {
        try synchronized {
            guard limit > 0 else { return [] }
            let locations = Array(try evidenceLocationIndex().values
                .filter { $0.threadID == threadID && $0.timestamp < timestamp }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(limit)
                .reversed())
            return try locations.map(readEvidence)
        }
    }

    public func pendingSegments() throws -> [SessionSegment] {
        try synchronized {
            let state = try loadState()
            return try loadPendingSegments(ids: state.pendingSegmentIDs)
        }
    }

    @discardableResult
    public func discardUnprocessed(before cutoff: Date) throws -> Int {
        try synchronized {
            var state = try loadStateUnlocked()
            let pendingIDs = Set(state.pendingSegmentIDs)
            guard !pendingIDs.isEmpty else { return 0 }

            let segments = try loadPendingSegments(ids: state.pendingSegmentIDs)
            let discardedIDs = Set(segments.compactMap { segment -> String? in
                effectiveTimestamp(for: segment) < cutoff ? segment.id : nil
            })
            guard !discardedIDs.isEmpty else { return 0 }

            state.pendingSegmentIDs.removeAll { discardedIDs.contains($0) }
            if var records = state.processingRecords {
                for id in discardedIDs {
                    records.removeValue(forKey: id)
                }
                state.processingRecords = records
            }
            try rewriteEvidence(excluding: discardedIDs)
            try saveState(state)
            return discardedIDs.count
        }
    }

    public func activeSessions(
        now: Date = Date(),
        maximumAge: TimeInterval = 10 * 60
    ) throws -> [ActiveSession] {
        try synchronized {
            let state = try loadState()
            let excluded = Set(state.excludedThreadIDs)
            return state.cursors.compactMap { sourcePath, cursor in
                let fileUpdatedAt = (try? FileManager.default.attributesOfItem(atPath: sourcePath)[.modificationDate]) as? Date
                let updatedAt = cursor.lastActivityAt ?? fileUpdatedAt
                guard !cursor.threadID.isEmpty,
                      !excluded.contains(cursor.threadID),
                      !isWorkstateAgentCWD(cursor.cwd),
                      !cursor.activeTurnID.isEmpty,
                      !cursor.userText.isEmpty,
                      let updatedAt,
                      now.timeIntervalSince(updatedAt) <= maximumAge else {
                    return nil
                }
                return ActiveSession(
                    threadID: cursor.threadID,
                    turnID: cursor.activeTurnID,
                    cwd: cursor.cwd,
                    userText: cursor.userText,
                    updatedAt: updatedAt
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public static func timestamp(fromTimeOrderedID id: String) -> Date? {
        let compact = id.replacingOccurrences(of: "-", with: "")
        guard compact.count >= 12 else { return nil }
        let timestampHex = String(compact.prefix(12))
        guard let milliseconds = UInt64(timestampHex, radix: 16) else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private func sessionFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func size(of file: URL) throws -> UInt64 {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    private func primeCursor(for file: URL) throws -> SessionCursor {
        let fileSize = try size(of: file)
        var cursor = SessionCursor()
        guard let metadata = try sessionMetadata(for: file) else {
            return cursor
        }
        cursor.threadID = metadata.threadID
        cursor.cwd = metadata.cwd
        cursor.isInternalAgentSession = metadata.isInternalAgentSession
        cursor.offset = fileSize

        let tailSize = min(fileSize, 8 * 1024 * 1024)
        guard tailSize > 0 else { return cursor }
        let tailStart = fileSize - tailSize
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: tailStart)
        let data = try handle.readToEnd() ?? Data()
        let lines = completeLines(in: data, dropsFirstPartialLine: tailStart > 0)
        for line in lines {
            _ = apply(
                line: line.data,
                lineOffset: tailStart + UInt64(line.offset),
                cursor: &cursor,
                sourcePath: file.path
            )
        }
        // Priming establishes a baseline, so bytes that already existed must never
        // become a later backlog even when the tail starts inside one large JSONL record.
        cursor.offset = fileSize
        return cursor
    }

    private func readAppended(
        file: URL,
        cursor: SessionCursor
    ) throws -> (cursor: SessionCursor, segments: [SessionSegment]) {
        var updated = cursor
        var segments: [SessionSegment] = []
        let completedOffset = try streamRelevantLines(
            in: file,
            startingAt: cursor.offset,
            markers: Self.ingestionLineMarkers
        ) { line in
            if let segment = apply(
                line: line.data,
                lineOffset: line.offset,
                cursor: &updated,
                sourcePath: file.path
            ) {
                segments.append(segment)
            }
        }
        updated.offset = completedOffset
        return (updated, segments)
    }

    private func readHistoricalFile(
        _ file: URL,
        chunkSize: Int = 1024 * 1024
    ) throws -> (cursor: SessionCursor, segments: [SessionSegment]) {
        var cursor = SessionCursor()
        var segments: [SessionSegment] = []
        let completedOffset = try streamRelevantLines(
            in: file,
            chunkSize: chunkSize,
            markers: Self.ingestionLineMarkers
        ) { line in
            if let segment = apply(
                line: line.data,
                lineOffset: line.offset,
                cursor: &cursor,
                sourcePath: file.path
            ) {
                segments.append(segment)
            }
        }
        cursor.offset = completedOffset
        return (cursor, segments)
    }

    private func historicalMetrics(
        _ file: URL,
        interval: DateInterval,
        chunkSize: Int = 1024 * 1024
    ) throws -> (turnCount: Int, evidenceBytes: UInt64) {
        var cursor = SessionCursor()
        var turnCount = 0
        var evidenceBytes: UInt64 = 0
        let encoder = WorkstateCoding.makeEncoder(pretty: false)
        _ = try streamRelevantLines(
            in: file,
            chunkSize: chunkSize,
            markers: Self.ingestionLineMarkers
        ) { line in
            guard let segment = apply(
                line: line.data,
                lineOffset: line.offset,
                cursor: &cursor,
                sourcePath: file.path
            ),
            segment.timestamp >= interval.start,
            segment.timestamp < interval.end else {
                return
            }
            turnCount += 1
            evidenceBytes += UInt64(try encoder.encode(segment).count + 1)
        }
        return (turnCount, evidenceBytes)
    }

    private struct StreamedLine {
        var data: Data
        var offset: UInt64
        var length: Int
    }

    private static let ingestionLineMarkers = [
        Data("\"session_meta\"".utf8),
        Data("\"turn_context\"".utf8),
        Data("\"event_msg\"".utf8)
    ]
    private func streamRelevantLines(
        in file: URL,
        startingAt startOffset: UInt64 = 0,
        chunkSize: Int = 1024 * 1024,
        prefixInspectionLimit: Int = 256 * 1024,
        maximumRelevantLineBytes: Int = 64 * 1024 * 1024,
        markers: [Data],
        body: (StreamedLine) throws -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: startOffset)

        var pending = Data()
        var lineStartOffset = startOffset
        var readOffset = startOffset
        var completedOffset = startOffset
        var discardingLine = false

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            var fragmentStart = chunk.startIndex

            while fragmentStart < chunk.endIndex,
                  let newline = chunk[fragmentStart...].firstIndex(of: 0x0A) {
                if !discardingLine {
                    pending.append(chunk[fragmentStart..<newline])
                    guard pending.count <= maximumRelevantLineBytes else {
                        throw WorkstateStorageError.invalidState(
                            "Relevant session record exceeds 64 MiB: \(file.path)"
                        )
                    }
                    if containsAnyMarker(pending, markers: markers) {
                        let length = Int(readOffset + UInt64(chunk.distance(from: chunk.startIndex, to: newline)) + 1 - lineStartOffset)
                        try body(StreamedLine(data: pending, offset: lineStartOffset, length: length))
                    }
                }

                let next = chunk.index(after: newline)
                completedOffset = readOffset + UInt64(chunk.distance(from: chunk.startIndex, to: next))
                lineStartOffset = completedOffset
                pending.removeAll(keepingCapacity: false)
                discardingLine = false
                fragmentStart = next
            }

            if fragmentStart < chunk.endIndex, !discardingLine {
                pending.append(chunk[fragmentStart..<chunk.endIndex])
                if pending.count >= prefixInspectionLimit,
                   !containsAnyMarker(pending, markers: markers) {
                    pending.removeAll(keepingCapacity: false)
                    discardingLine = true
                } else if pending.count > maximumRelevantLineBytes {
                    throw WorkstateStorageError.invalidState(
                        "Relevant session record exceeds 64 MiB: \(file.path)"
                    )
                }
            }
            readOffset += UInt64(chunk.count)
        }
        return completedOffset
    }

    private func containsAnyMarker(_ data: Data, markers: [Data]) -> Bool {
        markers.isEmpty || markers.contains { data.range(of: $0) != nil }
    }

    private func apply(
        line: Data,
        lineOffset: UInt64,
        cursor: inout SessionCursor,
        sourcePath: String
    ) -> SessionSegment? {
        guard let object = parseObject(line),
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        let eventTimestamp = parseTimestamp(object["timestamp"] as? String) ?? Date()

        if type == "session_meta" {
            cursor.threadID = payload["id"] as? String ?? payload["session_id"] as? String ?? cursor.threadID
            cursor.cwd = payload["cwd"] as? String ?? cursor.cwd
            return nil
        }
        if type == "turn_context" {
            cursor.cwd = payload["cwd"] as? String ?? cursor.cwd
            cursor.activeTurnID = payload["turn_id"] as? String ?? cursor.activeTurnID
            cursor.lastActivityAt = eventTimestamp
            return nil
        }
        guard type == "event_msg", let eventType = payload["type"] as? String else { return nil }

        switch eventType {
        case "task_started":
            cursor.activeTurnID = payload["turn_id"] as? String ?? ""
            cursor.activeTurnOffset = lineOffset
            cursor.userText = ""
            cursor.lastActivityAt = eventTimestamp
        case "user_message":
            let message = (payload["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                cursor.userText = cursor.userText.isEmpty ? message : "\(cursor.userText)\n\n\(message)"
            }
            cursor.lastActivityAt = eventTimestamp
        case "task_complete":
            let turnID = payload["turn_id"] as? String ?? cursor.activeTurnID
            let assistantText = (payload["last_agent_message"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cursor.threadID.isEmpty,
                  !turnID.isEmpty,
                  !cursor.userText.isEmpty,
                  !assistantText.isEmpty else {
                return nil
            }
            let timestamp = Self.timestamp(fromTimeOrderedID: turnID)
                ?? parseTimestamp(object["timestamp"] as? String)
                ?? Date()
            let segment = SessionSegment(
                threadID: cursor.threadID,
                turnID: turnID,
                sourcePath: sourcePath,
                startOffset: cursor.activeTurnOffset,
                endOffset: lineOffset + UInt64(line.count) + 1,
                cwd: cursor.cwd,
                userText: cursor.userText,
                assistantText: assistantText,
                timestamp: timestamp
            )
            cursor.activeTurnID = ""
            cursor.activeTurnOffset = 0
            cursor.userText = ""
            cursor.lastActivityAt = nil
            return segment
        default:
            break
        }
        return nil
    }

    private func appendEvidence(_ segments: [SessionSegment]) throws {
        if !FileManager.default.fileExists(atPath: evidenceURL.path) {
            FileManager.default.createFile(atPath: evidenceURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: evidenceURL)
        defer { try? handle.close() }
        var offset = try handle.seekToEnd()
        for segment in segments {
            var data = try WorkstateCoding.makeEncoder(pretty: false).encode(segment)
            data.append(0x0A)
            try handle.write(contentsOf: data)
            if storage.evidenceLocations != nil {
                storage.evidenceLocations?[segment.id] = EvidenceLocation(
                    offset: offset,
                    length: data.count,
                    threadID: segment.threadID,
                    timestamp: segment.timestamp
                )
            }
            offset += UInt64(data.count)
        }
    }

    private func rewriteEvidence(excluding excludedIDs: Set<String>) throws {
        guard !excludedIDs.isEmpty,
              FileManager.default.fileExists(atPath: evidenceURL.path) else {
            return
        }
        let temporaryURL = evidenceURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(evidenceURL.lastPathComponent).\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporaryURL)
        do {
            _ = try streamRelevantLines(in: evidenceURL, markers: []) { line in
                let segment = try WorkstateCoding.makeDecoder().decode(
                    SessionSegment.self,
                    from: line.data
                )
                guard !excludedIDs.contains(segment.id) else { return }
                try output.write(contentsOf: line.data)
                try output.write(contentsOf: Data([0x0A]))
            }
            try output.close()
            _ = try FileManager.default.replaceItemAt(evidenceURL, withItemAt: temporaryURL)
            storage.evidenceLocations = nil
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func effectiveTimestamp(for segment: SessionSegment) -> Date {
        Self.timestamp(fromTimeOrderedID: segment.turnID) ?? segment.timestamp
    }

    private func loadPendingSegments(ids: [String]) throws -> [SessionSegment] {
        guard !ids.isEmpty else { return [] }
        let index = try evidenceLocationIndex()
        return try ids.compactMap { index[$0] }
            .map(readEvidence)
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func evidenceLocationIndex() throws -> [String: EvidenceLocation] {
        if let cached = storage.evidenceLocations { return cached }
        storage.diagnostics.evidenceIndexLoads += 1
        guard FileManager.default.fileExists(atPath: evidenceURL.path) else {
            storage.evidenceLocations = [:]
            return [:]
        }
        var index: [String: EvidenceLocation] = [:]
        _ = try streamRelevantLines(in: evidenceURL, markers: []) { line in
            let segment = try WorkstateCoding.makeDecoder().decode(
                SessionSegment.self,
                from: line.data
            )
            index[segment.id] = EvidenceLocation(
                offset: line.offset,
                length: line.length,
                threadID: segment.threadID,
                timestamp: segment.timestamp
            )
        }
        storage.evidenceLocations = index
        return index
    }

    private func readEvidence(at location: EvidenceLocation) throws -> SessionSegment {
        let handle = try FileHandle(forReadingFrom: evidenceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: location.offset)
        var data = Data()
        while data.count < location.length {
            let chunk = try handle.read(upToCount: location.length - data.count) ?? Data()
            guard !chunk.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "Evidence ended before its indexed length at \(location.offset)"
                )
            }
            data.append(chunk)
        }
        if data.last == 0x0A { data.removeLast() }
        return try WorkstateCoding.makeDecoder().decode(SessionSegment.self, from: data)
    }

    private func saveState(_ state: IngestionSnapshot) throws {
        let data = try WorkstateCoding.makeEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        storage.state = state
    }

    private func loadStateUnlocked() throws -> IngestionSnapshot {
        if let cached = storage.state { return cached }
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            let empty = IngestionSnapshot()
            storage.state = empty
            return empty
        }
        let state = try WorkstateCoding.makeDecoder().decode(
            IngestionSnapshot.self,
            from: Data(contentsOf: stateURL)
        )
        storage.state = state
        return state
    }

    private func readFirstLine(_ file: URL) throws -> (data: Data, isComplete: Bool)? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var data = Data()
        let maximumBytes = 512 * 1024
        while data.count < maximumBytes {
            let requested = min(16 * 1024, maximumBytes - data.count)
            let chunk = try handle.read(upToCount: requested) ?? Data()
            storage.diagnostics.metadataBytesRead += UInt64(chunk.count)
            if chunk.isEmpty {
                return data.isEmpty ? nil : (data, false)
            }
            if let newline = chunk.firstIndex(of: 0x0A) {
                data.append(chunk[..<newline])
                return (data, true)
            }
            data.append(chunk)
        }
        throw WorkstateStorageError.invalidState("Session metadata exceeds 512 KiB: \(file.path)")
    }

    private func sessionMetadata(for file: URL) throws -> SessionMetadata? {
        storage.diagnostics.metadataReads += 1
        guard let firstLine = try readFirstLine(file) else { return nil }
        guard firstLine.isComplete else { return nil }
        guard let object = parseObject(firstLine.data),
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            throw WorkstateStorageError.invalidState("Invalid session metadata: \(file.path)")
        }
        let cwd = payload["cwd"] as? String ?? ""
        let originator = payload["originator"] as? String ?? ""
        let source = payload["source"] as? [String: Any]
        return SessionMetadata(
            threadID: payload["id"] as? String ?? payload["session_id"] as? String ?? "",
            cwd: cwd,
            isInternalAgentSession: isWorkstateAgentCWD(cwd)
                || originator == "codex_sdk_ts"
                || source?["subagent"] != nil,
            createdAt: parseTimestamp(object["timestamp"] as? String)
        )
    }

    private func loadSessionIndex(_ url: URL) throws -> [String: SessionIndexEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var output: [String: SessionIndexEntry] = [:]
        for line in try Data(contentsOf: url).split(separator: 0x0A) {
            guard let entry = try? WorkstateCoding.makeDecoder().decode(
                SessionIndexEntry.self,
                from: Data(line)
            ) else {
                continue
            }
            if output[entry.id]?.updatedAt ?? Date.distantPast <= entry.updatedAt {
                output[entry.id] = entry
            }
        }
        return output
    }

    private func isWorkstateAgentCWD(_ cwd: String) -> Bool {
        cwd.contains("/Workstate/AgentRuntime")
    }

    private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return try operation()
    }

    private func completeLines(
        in data: Data,
        dropsFirstPartialLine: Bool
    ) -> [(data: Data, length: Int, offset: Int)] {
        guard !data.isEmpty else { return [] }
        var output: [(Data, Int, Int)] = []
        var start = data.startIndex
        var shouldDrop = dropsFirstPartialLine
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let length = data.distance(from: start, to: newline) + 1
            let offset = data.distance(from: data.startIndex, to: start)
            if shouldDrop {
                shouldDrop = false
            } else {
                output.append((Data(data[start..<newline]), length, offset))
            }
            start = data.index(after: newline)
            if start == data.endIndex { break }
        }
        return output
    }

    private func completeByteCount(in data: Data) -> Int {
        guard let newline = data.lastIndex(of: 0x0A) else { return 0 }
        return data.distance(from: data.startIndex, to: newline) + 1
    }

    private func parseObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let fallback = Date.ISO8601FormatStyle()
        return (try? precise.parse(value)) ?? (try? fallback.parse(value))
    }
}

private struct SessionIndexEntry: Codable {
    var id: String
    var title: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title = "thread_name"
        case updatedAt = "updated_at"
    }
}

private func canonicalFileURL(_ url: URL) -> URL {
    func normalizedSystemPrefix(_ path: String) -> String {
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") {
            return "/private\(path)"
        }
        return path
    }
    let inputPath = normalizedSystemPrefix(url.standardizedFileURL.path)
    guard let resolved = Darwin.realpath(inputPath, nil) else {
        return URL(fileURLWithPath: inputPath)
    }
    defer { free(resolved) }
    return URL(fileURLWithPath: normalizedSystemPrefix(String(cString: resolved)))
}
