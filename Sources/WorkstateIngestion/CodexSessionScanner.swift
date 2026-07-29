import Darwin
import CryptoKit
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
    public var sourceSpans: [ConversationSourceSpan]?

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
        relatedTurnIDs: [String]? = nil,
        sourceSpans: [ConversationSourceSpan]? = nil
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
        self.sourceSpans = sourceSpans
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
    public var routeBindingHistory: [String: [ThreadRouteBinding]]?
    public var processingRecords: [String: SegmentProcessingRecord]?
    public var stewardBatches: [String: StewardBatchProcessingRecord]?
    public var lastScanAt: Date?

    public init(
        initialized: Bool = false,
        cursors: [String: SessionCursor] = [:],
        pendingSegmentIDs: [String] = [],
        excludedThreadIDs: [String] = [],
        routeBindings: [String: ThreadRouteBinding]? = nil,
        routeBindingHistory: [String: [ThreadRouteBinding]]? = nil,
        processingRecords: [String: SegmentProcessingRecord]? = nil,
        stewardBatches: [String: StewardBatchProcessingRecord]? = nil,
        lastScanAt: Date? = nil
    ) {
        self.initialized = initialized
        self.cursors = cursors
        self.pendingSegmentIDs = pendingSegmentIDs
        self.excludedThreadIDs = excludedThreadIDs
        self.routeBindings = routeBindings
        self.routeBindingHistory = routeBindingHistory
        self.processingRecords = processingRecords
        self.stewardBatches = stewardBatches
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
    public var batchID: String?
    public var failedStage: SegmentProcessingStage?
    public var error: String
    public var updatedAt: Date

    public init(
        segmentID: String,
        stage: SegmentProcessingStage = .queued,
        route: RouteResult? = nil,
        steward: StewardResult? = nil,
        batchID: String? = nil,
        failedStage: SegmentProcessingStage? = nil,
        error: String = "",
        updatedAt: Date = Date()
    ) {
        self.segmentID = segmentID
        self.stage = stage
        self.route = route
        self.steward = steward
        self.batchID = batchID
        self.failedStage = failedStage
        self.error = error
        self.updatedAt = updatedAt
    }
}

public struct StewardBatchProcessingRecord: Codable, Equatable, Sendable {
    public var id: String
    public var projectID: String
    public var segmentIDs: [String]
    public var result: BatchStewardResult
    public var updatedAt: Date

    public init(
        id: String,
        projectID: String,
        segmentIDs: [String],
        result: BatchStewardResult,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.segmentIDs = segmentIDs
        self.result = result
        self.updatedAt = updatedAt
    }
}

public struct ProcessedSegmentRoute: Codable, Sendable {
    public var segmentID: String
    public var threadID: String
    public var turnID: String
    public var projectID: String?

    public init(
        segmentID: String,
        threadID: String,
        turnID: String,
        projectID: String?
    ) {
        self.segmentID = segmentID
        self.threadID = threadID
        self.turnID = turnID
        self.projectID = projectID
    }
}

public struct OpenSemanticBundle: Codable, Equatable, Sendable {
    public var id: String
    public var threadID: String
    public var projectID: String
    public var disposition: String
    public var title: String
    public var summary: String
    public var evidenceIDs: [String]
    public var updatedAt: Date

    public init(
        id: String,
        threadID: String,
        projectID: String,
        disposition: String,
        title: String,
        summary: String,
        evidenceIDs: [String],
        updatedAt: Date
    ) {
        self.id = id
        self.threadID = threadID
        self.projectID = projectID
        self.disposition = disposition
        self.title = title
        self.summary = summary
        self.evidenceIDs = evidenceIDs
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
    public var sourceSpans: [ConversationSourceSpan]?
    public var lastActivityAt: Date?
    public var isInternalAgentSession: Bool?

    public init(
        offset: UInt64 = 0,
        threadID: String = "",
        cwd: String = "",
        activeTurnID: String = "",
        activeTurnOffset: UInt64 = 0,
        userText: String = "",
        sourceSpans: [ConversationSourceSpan]? = nil,
        lastActivityAt: Date? = nil,
        isInternalAgentSession: Bool? = nil
    ) {
        self.offset = offset
        self.threadID = threadID
        self.cwd = cwd
        self.activeTurnID = activeTurnID
        self.activeTurnOffset = activeTurnOffset
        self.userText = userText
        self.sourceSpans = sourceSpans
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
    public var sourceResolutionBytesRead: UInt64 = 0
    public var recentContextFailures = 0
    public var repairedLegacyPointerHashes = 0
}

private final class SessionScannerStorage: @unchecked Sendable {
    let lock = NSRecursiveLock()
    var state: IngestionSnapshot?
    var sourceIndex: ConversationSourceIndex?
    var cursorsDirty = false
    var persistAllCursors = false
    var diagnostics = ScannerDiagnostics()
}

private struct SessionMetadata {
    var threadID: String
    var cwd: String
    var isInternalAgentSession: Bool
    var createdAt: Date?
}

private struct ResolvedConversationMessages {
    var user: [String]
    var assistant: String
    var completionTurnID: String
}

public struct CodexSessionScanner: Sendable {
    public let sessionsRoot: URL
    public let runtimeRoot: URL
    public let retainsLegacyPendingState: Bool
    private let storage: SessionScannerStorage

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root,
        retainsLegacyPendingState: Bool = true
    ) {
        self.sessionsRoot = canonicalFileURL(sessionsRoot)
        self.runtimeRoot = canonicalFileURL(runtimeRoot)
        self.retainsLegacyPendingState = retainsLegacyPendingState
        storage = SessionScannerStorage()
    }

    public var stateURL: URL {
        runtimeRoot.appendingPathComponent("ingestion-state.json")
    }

    public var evidenceURL: URL {
        runtimeRoot.appendingPathComponent("evidence.jsonl")
    }

    public var sourceIndexURL: URL {
        runtimeRoot.appendingPathComponent("conversation-source-index.sqlite")
    }

    public func scan(minimumTimestamp: Date? = nil) throws -> [SessionSegment] {
        try synchronized {
            storage.diagnostics.fullScans += 1
            return try scanUnlocked(
                files: sessionFiles(),
                minimumTimestamp: minimumTimestamp,
                prunesMissingCursors: true
            )
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
                minimumTimestamp: minimumTimestamp,
                prunesMissingCursors: false
            )
        }
    }

    public func diagnostics() -> ScannerDiagnostics {
        synchronized { storage.diagnostics }
    }

    public func knownSessionPathsWithSizeChanges() throws -> [String] {
        try synchronized {
            let state = try loadStateUnlocked()
            return try state.cursors.compactMap { path, cursor in
                // Deleted files are pruned by the low-frequency full reconciliation.
                // Returning them here would make the fast poll report the same
                // non-existent path forever.
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                let fileSize = try size(of: URL(fileURLWithPath: path))
                return fileSize == cursor.offset ? nil : path
            }
            .sorted()
        }
    }

    public func latestActivityAt(threadID: String) throws -> Date? {
        try synchronized {
            let state = try loadStateUnlocked()
            return state.cursors.values
                .filter { $0.threadID == threadID }
                .compactMap(\.lastActivityAt)
                .max()
        }
    }

    private func scanUnlocked(
        files: [URL],
        minimumTimestamp: Date?,
        prunesMissingCursors: Bool
    ) throws -> [SessionSegment] {
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        var state = try loadStateUnlocked()
        let previousState = state
        var segments: [SessionSegment] = []

        if !state.initialized {
            for file in files {
                let cursor = try primeCursor(for: file)
                if cursor.isInternalAgentSession != true {
                    state.cursors[file.path] = cursor
                }
            }
            state.excludedThreadIDs = []
            state.initialized = true
            state.lastScanAt = Date()
            try saveState(state)
            return []
        }

        var excludedThreadIDs = Set(state.excludedThreadIDs)
        let scannedPaths = Set(files.map(\.path))
        if prunesMissingCursors {
            state.cursors = state.cursors.filter { scannedPaths.contains($0.key) }
        }
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
                    excludedThreadIDs.remove(cursor.threadID)
                }
                state.cursors.removeValue(forKey: file.path)
                continue
            }
            if excludedThreadIDs.contains(cursor.threadID) {
                excludedThreadIDs.remove(cursor.threadID)
                state.cursors.removeValue(forKey: file.path)
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
            segments = Array(Dictionary(
                segments.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            ).values)
            .sorted { $0.timestamp < $1.timestamp }
            let index = try sourceIndex()
            let newSegments = try segments.filter {
                try index.pointer(id: sourcePointerID(for: $0)) == nil
            }
            try storeSourcePointers(newSegments, in: index)
            segments = try segments.filter {
                try index.pointer(id: sourcePointerID(for: $0))?.processingState == .pending
            }
            if retainsLegacyPendingState {
                let existing = Set(state.pendingSegmentIDs)
                state.pendingSegmentIDs.append(
                    contentsOf: segments.map(\.id).filter { !existing.contains($0) }
                )
            }
        }
        let cursorsChanged = state.cursors != previousState.cursors
        var comparableState = state
        comparableState.cursors = [:]
        comparableState.lastScanAt = previousState.lastScanAt
        var comparablePreviousState = previousState
        comparablePreviousState.cursors = [:]
        let durableStateChanged = comparableState != comparablePreviousState
        if durableStateChanged {
            state.lastScanAt = Date()
        }
        if durableStateChanged || cursorsChanged {
            try saveState(state)
        }
        return retainsLegacyPendingState
            ? try loadPendingSegments(ids: state.pendingSegmentIDs)
            : segments
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
                    excluded.remove(metadata.threadID)
                    state.cursors.removeValue(forKey: file.path)
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

            let index = try sourceIndex()
            let newSegments = try imported.filter {
                try index.pointer(id: sourcePointerID(for: $0)) == nil
            }
            try storeSourcePointers(newSegments, in: index)

            let importedIDs = try imported.compactMap { segment -> String? in
                let record = try index.pointer(id: sourcePointerID(for: segment))
                return record?.processingState == .pending ? segment.id : nil
            }
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
            var state = try loadStateUnlocked()
            let processed = Set(segmentIDs)
            try validateCompleteBatchCommit(processed, in: state)
            state.pendingSegmentIDs.removeAll { processed.contains($0) }
            if var records = state.processingRecords {
                for segmentID in processed {
                    records.removeValue(forKey: segmentID)
                }
                state.processingRecords = records
            }
            if var batches = state.stewardBatches {
                batches = batches.filter { _, batch in
                    !Set(batch.segmentIDs).isSubset(of: processed)
                }
                state.stewardBatches = batches
            }
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
                    if record.batchID.flatMap({ state.stewardBatches?[$0] }) != nil {
                        record.stage = .stewarded
                    } else if record.steward != nil {
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
                    if record.batchID.flatMap({ state.stewardBatches?[$0] }) != nil {
                        record.stage = .stewarded
                    } else {
                        record.stage = record.steward == nil ? .routed : .stewarded
                    }
                case .applying:
                    if record.batchID.flatMap({ state.stewardBatches?[$0] }) != nil {
                        record.stage = .stewarded
                    } else {
                        record.stage = record.steward == nil ? .routed : .stewarded
                    }
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

    @discardableResult
    public func requeueLegacyPendingRoutes() throws -> Int {
        try synchronized {
            var state = try loadStateUnlocked()
            var records = state.processingRecords ?? [:]
            var requeued = 0
            for segmentID in state.pendingSegmentIDs {
                guard var record = records[segmentID],
                      let route = record.route,
                      route.normalizedDisposition != "ignore",
                      (route.bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      record.steward == nil,
                      record.batchID == nil else {
                    continue
                }
                record.route = nil
                record.stage = .queued
                record.failedStage = nil
                record.error = ""
                record.updatedAt = Date()
                records[segmentID] = record
                requeued += 1
            }
            if requeued > 0 {
                state.processingRecords = records
                try saveState(state)
            }
            return requeued
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
            latestRouteBinding(threadID: threadID, state: try loadState())
        }
    }

    public func routeBinding(
        threadID: String,
        before timestamp: Date
    ) throws -> ThreadRouteBinding? {
        try synchronized {
            let state = try loadState()
            let history = state.routeBindingHistory?[threadID]
                ?? state.routeBindings?[threadID].map { [$0] }
                ?? []
            return history
                .filter { $0.updatedAt < timestamp }
                .max { $0.updatedAt < $1.updatedAt }
        }
    }

    public func routeBindingHistory(threadID: String) throws -> [ThreadRouteBinding] {
        try synchronized {
            let state = try loadState()
            if let history = state.routeBindingHistory?[threadID], !history.isEmpty {
                return history.sorted { $0.updatedAt < $1.updatedAt }
            }
            return state.routeBindings?[threadID].map { [$0] } ?? []
        }
    }

    public func routedThreadIDs(projectID: String) throws -> Set<String> {
        guard !projectID.isEmpty else {
            throw WorkstateStorageError.invalidState("Project id is required")
        }
        return try synchronized {
            let state = try loadState()
            let threadIDs = Set(state.routeBindings?.keys.map { $0 } ?? [])
                .union(state.routeBindingHistory?.keys.map { $0 } ?? [])
            return Set(threadIDs.compactMap { threadID in
                latestRouteBinding(threadID: threadID, state: state)?.projectID == projectID
                    ? threadID
                    : nil
            })
        }
    }

    public func recordRoute(threadID: String, turnID: String, projectID: String) throws {
        try synchronized {
            guard !threadID.isEmpty, !turnID.isEmpty, !projectID.isEmpty else {
                throw WorkstateStorageError.invalidState("Route binding requires thread, turn, and project ids")
            }
            var state = try loadState()
            appendRouteBinding(ThreadRouteBinding(
                threadID: threadID,
                turnID: turnID,
                projectID: projectID,
                updatedAt: Self.timestamp(fromTimeOrderedID: turnID) ?? Date()
            ), to: &state)
            try saveState(state)
        }
    }

    public func commitProcessed(_ routes: [ProcessedSegmentRoute]) throws {
        try synchronized {
            guard !routes.isEmpty else { return }
            var state = try loadStateUnlocked()
            let processed = Set(routes.map(\.segmentID))
            try validateCompleteBatchCommit(processed, in: state)
            for route in routes {
                if let projectID = route.projectID {
                    guard !route.threadID.isEmpty,
                          !route.turnID.isEmpty,
                          !projectID.isEmpty else {
                        throw WorkstateStorageError.invalidState(
                            "A processed route requires thread, turn, and project ids"
                        )
                    }
                    appendRouteBinding(ThreadRouteBinding(
                        threadID: route.threadID,
                        turnID: route.turnID,
                        projectID: projectID,
                        updatedAt: Self.timestamp(fromTimeOrderedID: route.turnID) ?? Date()
                    ), to: &state)
                }
            }
            state.pendingSegmentIDs.removeAll { processed.contains($0) }
            if var records = state.processingRecords {
                for segmentID in processed {
                    records.removeValue(forKey: segmentID)
                }
                state.processingRecords = records
            }
            let pending = Set(state.pendingSegmentIDs)
            if var batches = state.stewardBatches {
                batches = batches.filter { _, batch in
                    !Set(batch.segmentIDs).isDisjoint(with: pending)
                }
                state.stewardBatches = batches
            }
            try saveState(state)
        }
    }

    public func finalizePointerBatch(
        successfulRoutes: [ProcessedSegmentRoute],
        failedSegmentIDs: [String]
    ) throws {
        try synchronized {
            let successfulIDs = Set(successfulRoutes.map(\.segmentID))
            let failedIDs = Set(failedSegmentIDs)
            guard successfulIDs.count == successfulRoutes.count,
                  failedIDs.count == failedSegmentIDs.count,
                  successfulIDs.isDisjoint(with: failedIDs) else {
                throw WorkstateStorageError.invalidState(
                    "A pointer batch must finalize unique, disjoint segment ids"
                )
            }
            let finalized = successfulIDs.union(failedIDs)
            guard !finalized.isEmpty else { return }
            var state = try loadStateUnlocked()
            for route in successfulRoutes {
                if let projectID = route.projectID {
                    guard !route.threadID.isEmpty,
                          !route.turnID.isEmpty,
                          !projectID.isEmpty else {
                        throw WorkstateStorageError.invalidState(
                            "A processed route requires thread, turn, and project ids"
                        )
                    }
                    appendRouteBinding(ThreadRouteBinding(
                        threadID: route.threadID,
                        turnID: route.turnID,
                        projectID: projectID,
                        updatedAt: Self.timestamp(fromTimeOrderedID: route.turnID) ?? Date()
                    ), to: &state)
                }
            }
            state.pendingSegmentIDs.removeAll { finalized.contains($0) }
            if var records = state.processingRecords {
                for segmentID in finalized { records.removeValue(forKey: segmentID) }
                state.processingRecords = records
            }
            if var batches = state.stewardBatches {
                batches = batches.filter { _, batch in
                    Set(batch.segmentIDs).isDisjoint(with: finalized)
                }
                state.stewardBatches = batches
            }
            try saveState(state)
        }
    }

    private func latestRouteBinding(
        threadID: String,
        state: IngestionSnapshot
    ) -> ThreadRouteBinding? {
        if let history = state.routeBindingHistory?[threadID], !history.isEmpty {
            return history.max { $0.updatedAt < $1.updatedAt }
        }
        return state.routeBindings?[threadID]
    }

    private func appendRouteBinding(
        _ binding: ThreadRouteBinding,
        to state: inout IngestionSnapshot
    ) {
        var history = state.routeBindingHistory ?? [:]
        var threadHistory = history[binding.threadID]
            ?? state.routeBindings?[binding.threadID].map { [$0] }
            ?? []
        threadHistory.sort { $0.updatedAt < $1.updatedAt }
        if let existingIndex = threadHistory.firstIndex(where: { $0.turnID == binding.turnID }) {
            threadHistory[existingIndex] = binding
            threadHistory.sort { $0.updatedAt < $1.updatedAt }
            history[binding.threadID] = threadHistory
            state.routeBindingHistory = history
            state.routeBindings?.removeValue(forKey: binding.threadID)
            return
        }
        if let latest = threadHistory.last, latest.projectID == binding.projectID {
            history[binding.threadID] = threadHistory
            state.routeBindingHistory = history
            state.routeBindings?.removeValue(forKey: binding.threadID)
            if state.routeBindings?.isEmpty == true {
                state.routeBindings = nil
            }
            return
        } else {
            threadHistory.append(binding)
            threadHistory.sort { $0.updatedAt < $1.updatedAt }
        }
        history[binding.threadID] = threadHistory
        state.routeBindingHistory = history
        state.routeBindings?.removeValue(forKey: binding.threadID)
        if state.routeBindings?.isEmpty == true {
            state.routeBindings = nil
        }
    }

    public func processingRecord(segmentID: String) throws -> SegmentProcessingRecord {
        try synchronized {
            let state = try loadStateUnlocked()
            return state.processingRecords?[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
        }
    }

    public func beginProcessing(segmentID: String, stage: SegmentProcessingStage) throws {
        try beginProcessing(segmentIDs: [segmentID], stage: stage)
    }

    public func beginProcessing(
        segmentIDs: [String],
        stage: SegmentProcessingStage
    ) throws {
        try synchronized {
            guard !segmentIDs.isEmpty else { return }
            guard stage == .routing || stage == .stewarding || stage == .applying else {
                throw WorkstateStorageError.invalidState(
                    "Unsupported active processing stage: \(stage.rawValue)"
                )
            }
            var state = try loadStateUnlocked()
            var records = state.processingRecords ?? [:]
            for segmentID in segmentIDs {
                var record = records[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
                guard record.stage != .failed && record.stage != .completed else {
                    throw WorkstateStorageError.invalidState(
                        "Segment \(segmentID) is not eligible for processing"
                    )
                }
                record.stage = stage
                record.failedStage = nil
                record.error = ""
                record.updatedAt = Date()
                records[segmentID] = record
            }
            state.processingRecords = records
            try saveState(state)
        }
    }

    public func recordRouteResult(segmentID: String, route: RouteResult) throws {
        try recordRouteResults([segmentID: route])
    }

    public func recordRouteResults(_ routes: [String: RouteResult]) throws {
        try synchronized {
            guard !routes.isEmpty else { return }
            var state = try loadStateUnlocked()
            var records = state.processingRecords ?? [:]
            for (segmentID, route) in routes {
                var record = records[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
                record.route = route
                record.stage = .routed
                record.failedStage = nil
                record.error = ""
                record.updatedAt = Date()
                records[segmentID] = record
            }
            state.processingRecords = records
            try saveState(state)
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

    public func recordStewardBatch(
        id: String,
        projectID: String,
        segmentIDs: [String],
        result: BatchStewardResult
    ) throws {
        try synchronized {
            guard !id.isEmpty,
                  !projectID.isEmpty,
                  !segmentIDs.isEmpty,
                  Set(segmentIDs).count == segmentIDs.count else {
                throw WorkstateStorageError.invalidState(
                    "A Steward batch requires unique segments, id, and project"
                )
            }
            var state = try loadStateUnlocked()
            var records = state.processingRecords ?? [:]
            for segmentID in segmentIDs {
                var record = records[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
                guard record.route != nil else {
                    throw WorkstateStorageError.invalidState(
                        "Steward batch requires a persisted route for \(segmentID)"
                    )
                }
                record.steward = nil
                record.batchID = id
                record.stage = .stewarded
                record.failedStage = nil
                record.error = ""
                record.updatedAt = Date()
                records[segmentID] = record
            }
            var batches = state.stewardBatches ?? [:]
            if let existing = batches[id] {
                guard existing.projectID == projectID,
                      existing.segmentIDs == segmentIDs,
                      existing.result == result else {
                    throw WorkstateStorageError.invalidState(
                        "A Steward batch id cannot be reused for different content"
                    )
                }
            } else {
                batches[id] = StewardBatchProcessingRecord(
                    id: id,
                    projectID: projectID,
                    segmentIDs: segmentIDs,
                    result: result
                )
            }
            state.processingRecords = records
            state.stewardBatches = batches
            try saveState(state)
        }
    }

    public func pendingStewardBatches() throws -> [StewardBatchProcessingRecord] {
        try synchronized {
            let state = try loadStateUnlocked()
            let pending = Set(state.pendingSegmentIDs)
            return (state.stewardBatches ?? [:]).values
                .filter { batch in
                    !Set(batch.segmentIDs).isDisjoint(with: pending)
                        && batch.segmentIDs.allSatisfy { segmentID in
                            state.processingRecords?[segmentID]?.stage == .stewarded
                        }
                }
                .sorted { lhs, rhs in
                    if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
                    return lhs.updatedAt < rhs.updatedAt
                }
        }
    }

    public func failStewardBatch(id: String, error: String) throws {
        try synchronized {
            var state = try loadStateUnlocked()
            guard let batch = state.stewardBatches?[id] else {
                throw WorkstateStorageError.invalidState("Unknown Steward batch: \(id)")
            }
            var records = state.processingRecords ?? [:]
            for segmentID in batch.segmentIDs {
                var record = records[segmentID] ?? SegmentProcessingRecord(segmentID: segmentID)
                record.stage = .failed
                record.failedStage = .applying
                record.error = error
                record.updatedAt = Date()
                records[segmentID] = record
            }
            state.processingRecords = records
            try saveState(state)
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
            let records = try sourceIndex().recentPointers(
                provider: "codex",
                threadID: threadID,
                before: timestamp,
                limit: limit
            )
            return records.compactMap { record in
                do {
                    return try materialize(record.pointer)
                } catch {
                    storage.diagnostics.recentContextFailures += 1
                    return nil
                }
            }
        }
    }

    public func pendingSegments() throws -> [SessionSegment] {
        try synchronized {
            let state = try loadState()
            return try loadPendingSegments(ids: state.pendingSegmentIDs)
        }
    }

    public func pendingIndexedSegments(limit: Int = 50) throws -> [SessionSegment] {
        try synchronized {
            guard limit > 0 else { return [] }
            return try sourceIndex().pendingPointers(limit: limit).map {
                try materialize($0.pointer)
            }
        }
    }

    public func routeBindingHistory() throws -> [String: [ThreadRouteBinding]] {
        try synchronized {
            let state = try loadState()
            var history = state.routeBindingHistory ?? [:]
            for (threadID, binding) in state.routeBindings ?? [:]
            where history[threadID]?.isEmpty != false {
                history[threadID] = [binding]
            }
            return history
        }
    }

    public func openSemanticBundles() throws -> [OpenSemanticBundle] {
        try synchronized {
            let indexed = try sourceIndex().semanticBundles(limit: 100).map { bundle in
                OpenSemanticBundle(
                    id: bundle.id,
                    threadID: bundle.threadID,
                    projectID: bundle.projectID,
                    disposition: "carry",
                    title: bundle.title,
                    summary: bundle.summary,
                    evidenceIDs: bundle.pointerIDs.map {
                        "\($0.threadID):\($0.turnID)"
                    },
                    updatedAt: bundle.updatedAt
                )
            }
            let state = try loadStateUnlocked()
            let records = state.processingRecords ?? [:]
            let routedIDs = state.pendingSegmentIDs.filter { segmentID in
                guard let route = records[segmentID]?.route else { return false }
                return route.normalizedDisposition != "ignore"
                    && !(route.bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !routedIDs.isEmpty else { return indexed }
            let segments = try loadPendingSegments(ids: routedIDs)
            let segmentByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
            let grouped = Dictionary(grouping: routedIDs) { records[$0]!.route!.bundleId! }
            let legacy: [OpenSemanticBundle] = grouped.compactMap { element in
                let (bundleID, evidenceIDs) = element
                let orderedIDs = evidenceIDs.sorted {
                    guard let lhs = segmentByID[$0], let rhs = segmentByID[$1] else { return $0 < $1 }
                    return lhs.timestamp < rhs.timestamp
                }
                guard let latestID = orderedIDs.max(by: {
                    (records[$0]?.updatedAt ?? .distantPast) < (records[$1]?.updatedAt ?? .distantPast)
                }), let latestRoute = records[latestID]?.route,
                      let latestSegment = segmentByID[latestID] else {
                    return nil
                }
                return OpenSemanticBundle(
                    id: bundleID,
                    threadID: latestSegment.threadID,
                    projectID: latestRoute.projectId,
                    disposition: latestRoute.normalizedDisposition,
                    title: latestRoute.bundleTitle ?? "",
                    summary: latestRoute.bundleSummary ?? "",
                    evidenceIDs: orderedIDs,
                    updatedAt: records[latestID]?.updatedAt ?? latestSegment.timestamp
                )
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
                return lhs.updatedAt < rhs.updatedAt
            }
            var byID = Dictionary(uniqueKeysWithValues: legacy.map { ($0.id, $0) })
            for bundle in indexed { byID[bundle.id] = bundle }
            return byID.values.sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    public func indexedSemanticBundles() throws -> [ConversationSemanticBundle] {
        try synchronized {
            try sourceIndex().semanticBundles(limit: 100)
        }
    }

    public func segments(ids: [String]) throws -> [SessionSegment] {
        try synchronized {
            try loadPendingSegments(ids: ids)
        }
    }

    public func segments(
        pointerRecords: [ConversationSourcePointerRecord]
    ) throws -> [SessionSegment] {
        try synchronized {
            try pointerRecords.map { try materialize($0.pointer) }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }

    public func segment(
        pointerRecord: ConversationSourcePointerRecord
    ) throws -> SessionSegment {
        try synchronized {
            try materialize(
                pointerRecord.pointer,
                repairsPendingLegacyHash: pointerRecord.processingState == .pending
            )
        }
    }

    public func pointerRecords(
        ids: [ConversationSourcePointerID]
    ) throws -> [ConversationSourcePointerRecord] {
        try synchronized {
            try sourceIndex().pointers(ids: ids)
        }
    }

    public func resolveMessages(for source: SourceReference) throws -> [ConversationMessage] {
        try synchronized {
            if !source.excerpt.isEmpty { return source.excerpt }
            guard source.kind == "conversation",
                  !source.threadID.isEmpty,
                  !source.turnIDs.isEmpty else { return [] }
            let index = try sourceIndex()
            var messages: [ConversationMessage] = []
            for turnID in source.turnIDs {
                let id = ConversationSourcePointerID(
                    provider: source.provider ?? "codex",
                    threadID: source.threadID,
                    turnID: turnID
                )
                let pointer: ConversationSourcePointer
                if let record = try index.pointer(id: id) {
                    pointer = record.pointer
                } else if source.turnIDs.count == 1,
                          let startOffset = source.startOffset,
                          let endOffset = source.endOffset,
                          !source.locator.isEmpty,
                          !source.contentHash.isEmpty {
                    pointer = ConversationSourcePointer(
                        provider: source.provider ?? "codex",
                        threadID: source.threadID,
                        turnID: turnID,
                        sourcePath: source.locator,
                        startOffset: startOffset,
                        endOffset: endOffset,
                        timestamp: .distantPast,
                        cwd: "",
                        contentHash: source.contentHash,
                        messageSpans: source.messageSpans ?? []
                    )
                } else {
                    throw WorkstateStorageError.invalidState(
                        "Conversation source pointer is missing: \(source.threadID)/\(turnID)"
                    )
                }
                let segment = try materialize(pointer)
                messages.append(
                    ConversationMessage(role: "user", text: segment.userText, timestamp: segment.timestamp)
                )
                messages.append(
                    ConversationMessage(role: "assistant", text: segment.assistantText, timestamp: segment.timestamp)
                )
            }
            return messages
        }
    }

    @discardableResult
    public func discardUnprocessed(before cutoff: Date) throws -> Int {
        try synchronized {
            var state = try loadStateUnlocked()
            let discardedPointers = try sourceIndex().deletePendingPointers(before: cutoff)
            let discardedIDs = Set(discardedPointers.map {
                "\($0.threadID):\($0.turnID)"
            })
            guard !discardedIDs.isEmpty else { return 0 }

            state.pendingSegmentIDs.removeAll { discardedIDs.contains($0) }
            if var records = state.processingRecords {
                for id in discardedIDs {
                    records.removeValue(forKey: id)
                }
                state.processingRecords = records
            }
            try saveState(state)
            return discardedPointers.count
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
                let userText = (try? readUserText(
                    sourcePath: sourcePath,
                    spans: cursor.sourceSpans ?? []
                )) ?? ""
                guard !cursor.threadID.isEmpty,
                      !excluded.contains(cursor.threadID),
                      !isWorkstateAgentCWD(cursor.cwd),
                      !cursor.activeTurnID.isEmpty,
                      !userText.isEmpty,
                      let updatedAt,
                      now.timeIntervalSince(updatedAt) <= maximumAge else {
                    return nil
                }
                return ActiveSession(
                    threadID: cursor.threadID,
                    turnID: cursor.activeTurnID,
                    cwd: cursor.cwd,
                    userText: userText,
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

        let modifiedAt = try file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate ?? .distantPast
        guard Date().timeIntervalSince(modifiedAt) <= 30 * 60 else {
            return cursor
        }
        let tailSize = min(fileSize, 256 * 1024)
        guard tailSize > 0 else { return cursor }
        let tailStart = fileSize - tailSize
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: tailStart)
        let data = try handle.readToEnd() ?? Data()
        let lines = completeLines(in: data, dropsFirstPartialLine: tailStart > 0)
        for line in lines {
            _ = try apply(
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
            if let segment = try apply(
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
            if let segment = try apply(
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
            guard let segment = try apply(
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
        endingAt endOffset: UInt64? = nil,
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
            if let endOffset, readOffset >= endOffset { break }
            let remaining = endOffset.map { Int(min(UInt64(chunkSize), $0 - readOffset)) }
                ?? chunkSize
            let chunk = try handle.read(upToCount: remaining) ?? Data()
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
        if let endOffset, completedOffset != endOffset {
            throw WorkstateStorageError.invalidState(
                "Conversation source range does not end on a complete JSONL record: \(file.path)"
            )
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
    ) throws -> SessionSegment? {
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
            cursor.sourceSpans = []
            cursor.lastActivityAt = eventTimestamp
        case "user_message":
            let message = (payload["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                cursor.userText = cursor.userText.isEmpty ? message : "\(cursor.userText)\n\n\(message)"
                cursor.sourceSpans = (cursor.sourceSpans ?? []) + [
                    ConversationSourceSpan(
                        kind: .userMessage,
                        startOffset: lineOffset,
                        endOffset: lineOffset + UInt64(line.count) + 1
                    )
                ]
            }
            cursor.lastActivityAt = eventTimestamp
        case "task_complete":
            let turnID = payload["turn_id"] as? String ?? cursor.activeTurnID
            let assistantText = (payload["last_agent_message"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var userSpans = cursor.sourceSpans ?? []
            if userSpans.isEmpty, !cursor.userText.isEmpty {
                userSpans = try recoverLegacyUserSpans(
                    sourcePath: sourcePath,
                    startOffset: cursor.activeTurnOffset,
                    endOffset: lineOffset,
                    expectedUserText: cursor.userText
                )
            }
            let userText = userSpans.isEmpty
                ? cursor.userText
                : try readUserText(sourcePath: sourcePath, spans: userSpans)
            let turnStartOffset = cursor.activeTurnOffset
            cursor.activeTurnID = ""
            cursor.activeTurnOffset = 0
            cursor.userText = ""
            cursor.sourceSpans = nil
            cursor.lastActivityAt = nil
            guard !cursor.threadID.isEmpty,
                  !turnID.isEmpty,
                  !userText.isEmpty,
                  !assistantText.isEmpty else {
                return nil
            }
            let timestamp = Self.timestamp(fromTimeOrderedID: turnID)
                ?? parseTimestamp(object["timestamp"] as? String)
                ?? Date()
            let completionSpan = ConversationSourceSpan(
                kind: .assistantCompletion,
                startOffset: lineOffset,
                endOffset: lineOffset + UInt64(line.count) + 1
            )
            let segment = SessionSegment(
                threadID: cursor.threadID,
                turnID: turnID,
                sourcePath: sourcePath,
                startOffset: turnStartOffset,
                endOffset: lineOffset + UInt64(line.count) + 1,
                cwd: cursor.cwd,
                userText: userText,
                assistantText: assistantText,
                timestamp: timestamp,
                sourceSpans: userSpans + [completionSpan]
            )
            return segment
        default:
            break
        }
        return nil
    }

    private func recoverLegacyUserSpans(
        sourcePath: String,
        startOffset: UInt64,
        endOffset: UInt64,
        expectedUserText: String,
        maximumBytes: UInt64 = 8 * 1024 * 1024
    ) throws -> [ConversationSourceSpan] {
        guard endOffset > startOffset else {
            throw WorkstateStorageError.invalidState(
                "Legacy active turn has no readable source range: \(sourcePath)"
            )
        }
        let sourceURL = canonicalFileURL(URL(fileURLWithPath: sourcePath))
        let length = min(endOffset - startOffset, maximumBytes)
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: startOffset)
        guard let data = try handle.read(upToCount: Int(length)), !data.isEmpty else {
            throw WorkstateStorageError.invalidState(
                "Legacy active turn source cannot be read: \(sourceURL.path)"
            )
        }

        var messages: [String] = []
        var spans: [ConversationSourceSpan] = []
        for line in completeLines(in: data, dropsFirstPartialLine: false) {
            guard let object = parseObject(line.data),
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message" else {
                continue
            }
            let message = (payload["message"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }
            messages.append(message)
            let lineStart = startOffset + UInt64(line.offset)
            spans.append(
                ConversationSourceSpan(
                    kind: .userMessage,
                    startOffset: lineStart,
                    endOffset: lineStart + UInt64(line.length)
                )
            )
            if messages.joined(separator: "\n\n") == expectedUserText {
                return spans
            }
        }
        throw WorkstateStorageError.invalidState(
            "Legacy active turn user message could not be located within 8 MiB: \(sourceURL.path)"
        )
    }

    private func sourceIndex() throws -> ConversationSourceIndex {
        if let index = storage.sourceIndex { return index }
        let index = try ConversationSourceIndex(databaseURL: sourceIndexURL)
        storage.sourceIndex = index
        return index
    }

    private func sourcePointerID(for segment: SessionSegment) -> ConversationSourcePointerID {
        ConversationSourcePointerID(
            provider: "codex",
            threadID: segment.threadID,
            turnID: segment.turnID
        )
    }

    private func sourcePointerID(forSegmentID id: String) throws -> ConversationSourcePointerID {
        let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw WorkstateStorageError.invalidState("Invalid conversation source id: \(id)")
        }
        return ConversationSourcePointerID(
            provider: "codex",
            threadID: String(parts[0]),
            turnID: String(parts[1])
        )
    }

    private func storeSourcePointers(
        _ segments: [SessionSegment],
        in index: ConversationSourceIndex
    ) throws {
        guard !segments.isEmpty else { return }
        try index.upsertPointers(segments.map { segment in
            ConversationSourcePointer(
                provider: "codex",
                threadID: segment.threadID,
                turnID: segment.turnID,
                sourcePath: canonicalFileURL(URL(fileURLWithPath: segment.sourcePath)).path,
                startOffset: segment.startOffset,
                endOffset: segment.endOffset,
                timestamp: segment.timestamp,
                cwd: segment.cwd,
                contentHash: contentHash(
                    userText: segment.userText,
                    assistantText: segment.assistantText
                ),
                messageSpans: segment.sourceSpans ?? []
            )
        })
    }

    private func materialize(
        _ pointer: ConversationSourcePointer,
        repairsPendingLegacyHash: Bool = false
    ) throws -> SessionSegment {
        let messages = pointer.messageSpans.isEmpty
            ? try readMessagesInTurn(pointer)
            : try readMessages(sourcePath: pointer.sourcePath, spans: pointer.messageSpans)
        let userText = messages.user.joined(separator: "\n\n")
        guard !userText.isEmpty,
              !messages.assistant.isEmpty,
              messages.completionTurnID == pointer.turnID else {
            throw WorkstateStorageError.invalidState(
                "Conversation source no longer contains the indexed turn: \(pointer.threadID)/\(pointer.turnID)"
            )
        }
        let resolvedHash = contentHash(userText: userText, assistantText: messages.assistant)
        if resolvedHash != pointer.contentHash {
            guard repairsPendingLegacyHash,
                  legacySuffixHashMatches(
                    pointer.contentHash,
                    userMessages: messages.user,
                    assistantText: messages.assistant
                  ) else {
                throw WorkstateStorageError.invalidState(
                    "Conversation source changed after indexing: \(pointer.threadID)/\(pointer.turnID)"
                )
            }
            var repaired = pointer
            repaired.contentHash = resolvedHash
            try sourceIndex().upsertPointer(repaired)
            storage.diagnostics.repairedLegacyPointerHashes += 1
        }
        return SessionSegment(
            threadID: pointer.threadID,
            turnID: pointer.turnID,
            sourcePath: pointer.sourcePath,
            startOffset: pointer.startOffset,
            endOffset: pointer.endOffset,
            cwd: pointer.cwd,
            userText: userText,
            assistantText: messages.assistant,
            timestamp: pointer.timestamp,
            sourceSpans: pointer.messageSpans
        )
    }

    private func readUserText(
        sourcePath: String,
        spans: [ConversationSourceSpan]
    ) throws -> String {
        let userSpans = spans.filter { $0.kind == .userMessage }
        guard !userSpans.isEmpty else { return "" }
        return try readMessages(sourcePath: sourcePath, spans: userSpans)
            .user
            .joined(separator: "\n\n")
    }

    private func readMessages(
        sourcePath: String,
        spans: [ConversationSourceSpan]
    ) throws -> ResolvedConversationMessages {
        let sourceURL = canonicalFileURL(URL(fileURLWithPath: sourcePath))
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw WorkstateStorageError.invalidState("Conversation source is missing: \(sourceURL.path)")
        }
        var userMessages: [String] = []
        var assistant = ""
        var completionTurnID = ""
        for span in spans {
            let line = try readSourceSpan(span, from: sourceURL)
            guard let object = parseObject(line),
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String else {
                throw WorkstateStorageError.invalidState(
                    "Conversation pointer does not reference an event message: \(sourceURL.path)"
                )
            }
            switch (span.kind, eventType) {
            case (.userMessage, "user_message"):
                let value = (payload["message"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { userMessages.append(value) }
            case (.assistantCompletion, "task_complete"):
                assistant = (payload["last_agent_message"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completionTurnID = payload["turn_id"] as? String ?? ""
            default:
                throw WorkstateStorageError.invalidState(
                    "Conversation pointer kind does not match its source event: \(sourceURL.path)"
                )
            }
        }
        return ResolvedConversationMessages(
            user: userMessages,
            assistant: assistant,
            completionTurnID: completionTurnID
        )
    }

    private func readMessagesInTurn(
        _ pointer: ConversationSourcePointer
    ) throws -> ResolvedConversationMessages {
        let sourceURL = canonicalFileURL(URL(fileURLWithPath: pointer.sourcePath))
        var userMessages: [String] = []
        var assistant = ""
        var completionTurnID = ""
        _ = try streamRelevantLines(
            in: sourceURL,
            startingAt: pointer.startOffset,
            endingAt: pointer.endOffset,
            markers: [Data("\"event_msg\"".utf8)]
        ) { line in
            guard let object = parseObject(line.data),
                  let payload = object["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String else { return }
            if eventType == "user_message" {
                let value = (payload["message"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { userMessages.append(value) }
            } else if eventType == "task_complete",
                      payload["turn_id"] as? String == pointer.turnID {
                assistant = (payload["last_agent_message"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completionTurnID = pointer.turnID
            }
        }
        return ResolvedConversationMessages(
            user: userMessages,
            assistant: assistant,
            completionTurnID: completionTurnID
        )
    }

    private func readSourceSpan(
        _ span: ConversationSourceSpan,
        from sourceURL: URL,
        maximumBytes: UInt64 = 8 * 1024 * 1024
    ) throws -> Data {
        guard span.endOffset > span.startOffset else {
            throw WorkstateStorageError.invalidState("Conversation source span is empty")
        }
        let length = span.endOffset - span.startOffset
        guard length <= maximumBytes else {
            throw WorkstateStorageError.invalidState(
                "Conversation source message exceeds 8 MiB: \(sourceURL.path)"
            )
        }
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: span.startOffset)
        guard var data = try handle.read(upToCount: Int(length)), data.count == Int(length) else {
            throw WorkstateStorageError.invalidState(
                "Conversation source ended before its indexed span: \(sourceURL.path)"
            )
        }
        storage.diagnostics.sourceResolutionBytesRead += UInt64(data.count)
        if data.last == 0x0A { data.removeLast() }
        return data
    }

    private func contentHash(userText: String, assistantText: String) -> String {
        let digest = SHA256.hash(data: Data("\(userText)\u{0}\(assistantText)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func legacySuffixHashMatches(
        _ storedHash: String,
        userMessages: [String],
        assistantText: String
    ) -> Bool {
        guard userMessages.count > 1 else { return false }
        for start in 1..<userMessages.count {
            let suffix = userMessages[start...].joined(separator: "\n\n")
            if contentHash(userText: suffix, assistantText: assistantText) == storedHash {
                return true
            }
        }
        return false
    }

    private func effectiveTimestamp(for segment: SessionSegment) -> Date {
        Self.timestamp(fromTimeOrderedID: segment.turnID) ?? segment.timestamp
    }

    private func loadPendingSegments(ids: [String]) throws -> [SessionSegment] {
        guard !ids.isEmpty else { return [] }
        let index = try sourceIndex()
        let pointerIDs = try ids.map(sourcePointerID(forSegmentID:))
        let records = try index.pointers(ids: pointerIDs)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.pointer) })
        return try pointerIDs.compactMap { byID[$0] }
            .map { try materialize($0) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func saveState(_ state: IngestionSnapshot) throws {
        let needsLegacyCursorRewrite = storage.persistAllCursors
        var cached = state
        let pending = Set(cached.pendingSegmentIDs)
        if var records = cached.processingRecords {
            records = records.filter { pending.contains($0.key) }
            cached.processingRecords = records
        }
        if var batches = cached.stewardBatches {
            batches = batches.filter { _, batch in
                !Set(batch.segmentIDs).isDisjoint(with: pending)
            }
            cached.stewardBatches = batches
        }
        cached.cursors = cached.cursors.filter {
            $0.value.isInternalAgentSession != true
        }
        for path in cached.cursors.keys {
            cached.cursors[path]?.userText = ""
        }
        cached.excludedThreadIDs = Array(Set(cached.excludedThreadIDs)).sorted()

        let previousCursors = storage.state?.cursors ?? [:]
        if previousCursors != cached.cursors {
            storage.cursorsDirty = true
        }
        if storage.cursorsDirty {
            let index = try sourceIndex()
            let changedCursors = cached.cursors.filter { path, cursor in
                storage.persistAllCursors || previousCursors[path] != cursor
            }
            let currentPaths = Set(cached.cursors.keys)
            try index.deleteScanCursors(
                provider: "codex",
                sourcePaths: Array(Set(previousCursors.keys).subtracting(currentPaths))
            )
            try index.upsertScanCursors(changedCursors.map { path, cursor in
                ConversationScanCursor(
                    provider: "codex",
                    sourcePath: path,
                    nextOffset: cursor.offset,
                    threadID: cursor.threadID,
                    cwd: cursor.cwd,
                    activeTurnID: cursor.activeTurnID,
                    activeTurnOffset: cursor.activeTurnOffset,
                    messageSpans: cursor.sourceSpans ?? [],
                    lastActivityAt: cursor.lastActivityAt,
                    isInternalAgentSession: cursor.isInternalAgentSession
                )
            })
            storage.cursorsDirty = false
            storage.persistAllCursors = false
        }

        var persisted = cached
        persisted.cursors = [:]
        var previousPersisted = storage.state
        previousPersisted?.cursors = [:]
        if !needsLegacyCursorRewrite,
           previousPersisted == persisted,
           FileManager.default.fileExists(atPath: stateURL.path) {
            storage.state = cached
            return
        }
        let data = try WorkstateCoding.makeEncoder().encode(persisted)
        try data.write(to: stateURL, options: .atomic)
        storage.state = cached
    }

    private func validateCompleteBatchCommit(
        _ processed: Set<String>,
        in state: IngestionSnapshot
    ) throws {
        for batch in (state.stewardBatches ?? [:]).values {
            let batchSegments = Set(batch.segmentIDs)
            guard batchSegments.isDisjoint(with: processed)
                    || batchSegments.isSubset(of: processed) else {
                throw WorkstateStorageError.invalidState(
                    "A persisted Steward batch must be committed as one unit: \(batch.id)"
                )
            }
        }
    }

    private func loadStateUnlocked() throws -> IngestionSnapshot {
        if let cached = storage.state { return cached }
        var state = if FileManager.default.fileExists(atPath: stateURL.path) {
            try WorkstateCoding.makeDecoder().decode(
                IngestionSnapshot.self,
                from: Data(contentsOf: stateURL)
            )
        } else {
            IngestionSnapshot()
        }
        let indexedCursors = try sourceIndex().scanCursors(provider: "codex")
        if !indexedCursors.isEmpty {
            state.cursors = Dictionary(uniqueKeysWithValues: indexedCursors.map { cursor in
                (
                    cursor.sourcePath,
                    SessionCursor(
                        offset: cursor.nextOffset,
                        threadID: cursor.threadID,
                        cwd: cursor.cwd,
                        activeTurnID: cursor.activeTurnID,
                        activeTurnOffset: cursor.activeTurnOffset,
                        sourceSpans: cursor.messageSpans,
                        lastActivityAt: cursor.lastActivityAt,
                        isInternalAgentSession: cursor.isInternalAgentSession
                    )
                )
            })
        } else if !state.cursors.isEmpty {
            storage.cursorsDirty = true
            storage.persistAllCursors = true
        }
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
