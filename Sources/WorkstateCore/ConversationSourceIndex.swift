import Foundation
import SQLite3

public struct ConversationSourcePointerID: Codable, Equatable, Hashable, Sendable {
    public var provider: String
    public var threadID: String
    public var turnID: String

    public init(provider: String, threadID: String, turnID: String) {
        self.provider = provider
        self.threadID = threadID
        self.turnID = turnID
    }
}

public struct ConversationSourceSpan: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case userMessage
        case assistantCompletion
    }

    public var kind: Kind
    public var startOffset: UInt64
    public var endOffset: UInt64

    public init(kind: Kind, startOffset: UInt64, endOffset: UInt64) {
        self.kind = kind
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct ConversationSourcePointer: Codable, Equatable, Identifiable, Sendable {
    public var id: ConversationSourcePointerID {
        ConversationSourcePointerID(provider: provider, threadID: threadID, turnID: turnID)
    }

    public var provider: String
    public var threadID: String
    public var turnID: String
    public var sourcePath: String
    public var startOffset: UInt64
    public var endOffset: UInt64
    public var timestamp: Date
    public var cwd: String
    public var contentHash: String
    public var messageSpans: [ConversationSourceSpan]

    public init(
        provider: String,
        threadID: String,
        turnID: String,
        sourcePath: String,
        startOffset: UInt64,
        endOffset: UInt64,
        timestamp: Date,
        cwd: String,
        contentHash: String,
        messageSpans: [ConversationSourceSpan] = []
    ) {
        self.provider = provider
        self.threadID = threadID
        self.turnID = turnID
        self.sourcePath = sourcePath
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.timestamp = timestamp
        self.cwd = cwd
        self.contentHash = contentHash
        self.messageSpans = messageSpans
    }
}

public struct ConversationScanCursor: Codable, Equatable, Sendable {
    public var provider: String
    public var sourcePath: String
    public var nextOffset: UInt64
    public var updatedAt: Date
    public var threadID: String
    public var cwd: String
    public var activeTurnID: String
    public var activeTurnOffset: UInt64
    public var messageSpans: [ConversationSourceSpan]
    public var lastActivityAt: Date?
    public var isInternalAgentSession: Bool?

    public init(
        provider: String,
        sourcePath: String,
        nextOffset: UInt64,
        updatedAt: Date = Date(),
        threadID: String = "",
        cwd: String = "",
        activeTurnID: String = "",
        activeTurnOffset: UInt64 = 0,
        messageSpans: [ConversationSourceSpan] = [],
        lastActivityAt: Date? = nil,
        isInternalAgentSession: Bool? = nil
    ) {
        self.provider = provider
        self.sourcePath = sourcePath
        self.nextOffset = nextOffset
        self.updatedAt = updatedAt
        self.threadID = threadID
        self.cwd = cwd
        self.activeTurnID = activeTurnID
        self.activeTurnOffset = activeTurnOffset
        self.messageSpans = messageSpans
        self.lastActivityAt = lastActivityAt
        self.isInternalAgentSession = isInternalAgentSession
    }
}

public enum ConversationPointerProcessingState: String, Codable, CaseIterable, Sendable {
    case pending
    case batched
    case completed
    case failed
}

public struct ConversationSourcePointerRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: ConversationSourcePointerID { pointer.id }
    public var sequence: Int64
    public var pointer: ConversationSourcePointer
    public var processingState: ConversationPointerProcessingState
    public var batchID: String?
    public var projectID: String?
    public var failureMessage: String?
    public var insertedAt: Date
    public var updatedAt: Date
}

public struct ConversationBatchHighWaterMark: Codable, Equatable, Sendable {
    public var pointerSequence: Int64

    public init(pointerSequence: Int64) {
        self.pointerSequence = pointerSequence
    }
}

public struct ConversationPendingPointerStats: Codable, Equatable, Sendable {
    public var count: Int
    public var oldestInsertedAt: Date?
    public var latestInsertedAt: Date?

    public init(count: Int, oldestInsertedAt: Date?, latestInsertedAt: Date?) {
        self.count = count
        self.oldestInsertedAt = oldestInsertedAt
        self.latestInsertedAt = latestInsertedAt
    }
}

public struct ConversationPendingThreadStats: Codable, Equatable, Sendable {
    public var provider: String
    public var threadID: String
    public var pointerCount: Int
    public var firstSequence: Int64
    public var latestTimestamp: Date

    public init(
        provider: String,
        threadID: String,
        pointerCount: Int,
        firstSequence: Int64,
        latestTimestamp: Date
    ) {
        self.provider = provider
        self.threadID = threadID
        self.pointerCount = pointerCount
        self.firstSequence = firstSequence
        self.latestTimestamp = latestTimestamp
    }
}

public enum ConversationProcessingBatchStatus: String, Codable, CaseIterable, Sendable {
    case processing
    case completed
    case failed
}

public struct ConversationProcessingBatch: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var highWaterMark: ConversationBatchHighWaterMark
    public var status: ConversationProcessingBatchStatus
    public var pointers: [ConversationSourcePointerRecord]
    public var errorMessage: String?
    public var createdAt: Date
    public var finishedAt: Date?
    public var updatedAt: Date
}

public struct ConversationPointerProjectAssignment: Codable, Equatable, Sendable {
    public var pointerID: ConversationSourcePointerID
    public var projectID: String

    public init(pointerID: ConversationSourcePointerID, projectID: String) {
        self.pointerID = pointerID
        self.projectID = projectID
    }
}

public struct ConversationSemanticBundle: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var threadID: String
    public var projectID: String
    public var title: String
    public var summary: String
    public var pointerIDs: [ConversationSourcePointerID]
    public var updatedAt: Date

    public init(
        id: String,
        threadID: String,
        projectID: String,
        title: String,
        summary: String,
        pointerIDs: [ConversationSourcePointerID],
        updatedAt: Date
    ) {
        self.id = id
        self.threadID = threadID
        self.projectID = projectID
        self.title = title
        self.summary = summary
        self.pointerIDs = pointerIDs
        self.updatedAt = updatedAt
    }
}

public enum ConversationSemanticBundleMutation: Codable, Equatable, Sendable {
    case upsert(ConversationSemanticBundle)
    case close(bundleID: String)
}

public enum ConversationSourceIndexError: LocalizedError, Sendable {
    case invalidInput(String)
    case databaseOpenFailed(path: String, code: Int32, message: String)
    case databaseClosed(path: String)
    case sqliteFailure(path: String, operation: String, code: Int32, message: String)
    case unsupportedSchemaVersion(Int64)
    case corruptData(String)
    case pointerChangedAfterProcessing(ConversationSourcePointerID)
    case missingBatch(String)
    case invalidBatchState(id: String, actual: ConversationProcessingBatchStatus)
    case pointerNotInBatch(pointerID: ConversationSourcePointerID, batchID: String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid conversation source index input: \(message)"
        case .databaseOpenFailed(let path, let code, let message):
            return "Cannot open conversation source index at \(path) (SQLite \(code)): \(message)"
        case .databaseClosed(let path):
            return "Conversation source index is closed: \(path)"
        case .sqliteFailure(let path, let operation, let code, let message):
            return "Conversation source index \(operation) failed at \(path) (SQLite \(code)): \(message)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported conversation source index schema version: \(version)"
        case .corruptData(let message):
            return "Invalid conversation source index data: \(message)"
        case .pointerChangedAfterProcessing(let id):
            return "Conversation pointer changed after processing: \(id.provider)/\(id.threadID)/\(id.turnID)"
        case .missingBatch(let id):
            return "Conversation processing batch not found: \(id)"
        case .invalidBatchState(let id, let actual):
            return "Conversation processing batch \(id) is \(actual.rawValue), expected processing"
        case .pointerNotInBatch(let pointerID, let batchID):
            return "Conversation pointer \(pointerID.provider)/\(pointerID.threadID)/\(pointerID.turnID) is not in batch \(batchID)"
        }
    }
}

public final class ConversationSourceIndex: @unchecked Sendable {
    public let databaseURL: URL

    private static let schemaVersion: Int64 = 4
    private static let maximumSemanticBundlePointers = 100
    private static let maximumSemanticBundleBytes: UInt64 = 768 * 1024
    private let lock = NSLock()
    private var database: OpaquePointer?

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        walAutoCheckpointPages: Int32 = 1_000
    ) throws {
        guard databaseURL.isFileURL else {
            throw ConversationSourceIndexError.invalidInput("databaseURL must be a file URL")
        }
        guard busyTimeoutMilliseconds > 0 else {
            throw ConversationSourceIndexError.invalidInput("busyTimeoutMilliseconds must be positive")
        }
        guard walAutoCheckpointPages > 0 else {
            throw ConversationSourceIndexError.invalidInput("walAutoCheckpointPages must be positive")
        }

        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            let message = sqliteMessage(handle)
            if let handle {
                sqlite3_close_v2(handle)
            }
            throw ConversationSourceIndexError.databaseOpenFailed(
                path: databaseURL.path,
                code: openResult,
                message: message
            )
        }
        database = handle

        do {
            try configureDatabase(
                handle,
                busyTimeoutMilliseconds: busyTimeoutMilliseconds,
                walAutoCheckpointPages: walAutoCheckpointPages
            )
            try initializeSchema(handle)
        } catch {
            sqlite3_close_v2(handle)
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    public func upsertPointer(_ pointer: ConversationSourcePointer, at updatedAt: Date = Date()) throws {
        try upsertPointers([pointer], at: updatedAt)
    }

    public func upsertPointers(_ pointers: [ConversationSourcePointer], at updatedAt: Date = Date()) throws {
        guard !pointers.isEmpty else { return }
        try Self.validateDate(updatedAt, field: "updatedAt")
        for pointer in pointers {
            try Self.validate(pointer)
        }

        try withDatabase { database in
            try withImmediateTransaction(database) {
                for pointer in pointers {
                    if let existing = try pointerRecord(database, id: pointer.id) {
                        guard existing.pointer != pointer else { continue }
                        guard existing.processingState == .pending else {
                            throw ConversationSourceIndexError.pointerChangedAfterProcessing(pointer.id)
                        }
                        try updatePendingPointer(database, pointer: pointer, updatedAt: updatedAt)
                    } else {
                        try insertPointer(database, pointer: pointer, insertedAt: updatedAt)
                    }
                }
            }
        }
    }

    public func upsertScanCursor(_ cursor: ConversationScanCursor) throws {
        try upsertScanCursors([cursor])
    }

    public func upsertScanCursors(_ cursors: [ConversationScanCursor]) throws {
        guard !cursors.isEmpty else { return }
        for cursor in cursors { try Self.validate(cursor) }
        try withDatabase { database in
            try withImmediateTransaction(database) {
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "upsert scan cursor",
                    sql: """
                    INSERT INTO conversation_scan_cursors (
                        provider, source_path, next_offset, updated_at, cursor_json
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(provider, source_path) DO UPDATE SET
                        next_offset = excluded.next_offset,
                        updated_at = excluded.updated_at,
                        cursor_json = excluded.cursor_json
                    """
                )
                for cursor in cursors {
                    try statement.bind(cursor.provider, at: 1)
                    try statement.bind(cursor.sourcePath, at: 2)
                    try statement.bind(Int64(cursor.nextOffset), at: 3)
                    try statement.bind(cursor.updatedAt.timeIntervalSince1970, at: 4)
                    try statement.bind(try Self.encodeCursor(cursor), at: 5)
                    try statement.execute()
                    try statement.reset()
                }
            }
        }
    }

    public func scanCursor(provider: String, sourcePath: String) throws -> ConversationScanCursor? {
        try Self.validateProvider(provider)
        try Self.validateRequiredText(sourcePath, field: "sourcePath")

        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "read scan cursor",
                sql: """
                SELECT provider, source_path, next_offset, updated_at, cursor_json
                FROM conversation_scan_cursors
                WHERE provider = ? AND source_path = ?
                """
            )
            try statement.bind(provider, at: 1)
            try statement.bind(sourcePath, at: 2)
            guard try statement.step() == .row else { return nil }

            let nextOffset = statement.int64(at: 2)
            guard nextOffset >= 0 else {
                throw ConversationSourceIndexError.corruptData("scan cursor has a negative offset")
            }
            return try decodeCursor(statement)
        }
    }

    public func scanCursors(provider: String) throws -> [ConversationScanCursor] {
        try Self.validateProvider(provider)
        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "read scan cursors",
                sql: """
                SELECT provider, source_path, next_offset, updated_at, cursor_json
                FROM conversation_scan_cursors
                WHERE provider = ?
                ORDER BY source_path ASC
                """
            )
            try statement.bind(provider, at: 1)
            var cursors: [ConversationScanCursor] = []
            while try statement.step() == .row {
                cursors.append(try decodeCursor(statement))
            }
            return cursors
        }
    }

    public func deleteScanCursors(provider: String, sourcePaths: [String]) throws {
        guard !sourcePaths.isEmpty else { return }
        try Self.validateProvider(provider)
        for path in sourcePaths { try Self.validateRequiredText(path, field: "sourcePath") }
        try withDatabase { database in
            try withImmediateTransaction(database) {
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "delete scan cursor",
                    sql: "DELETE FROM conversation_scan_cursors WHERE provider = ? AND source_path = ?"
                )
                for path in sourcePaths {
                    try statement.bind(provider, at: 1)
                    try statement.bind(path, at: 2)
                    try statement.execute()
                    try statement.reset()
                }
            }
        }
    }

    public func captureHighWaterMark() throws -> ConversationBatchHighWaterMark? {
        try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "capture batch high-water mark",
                sql: """
                SELECT MAX(sequence)
                FROM conversation_source_pointers
                WHERE processing_state = 'pending'
                """
            )
            guard try statement.step() == .row, !statement.isNull(at: 0) else { return nil }
            let sequence = statement.int64(at: 0)
            guard sequence > 0 else {
                throw ConversationSourceIndexError.corruptData("batch high-water mark is not positive")
            }
            return ConversationBatchHighWaterMark(pointerSequence: sequence)
        }
    }

    public func pendingStats() throws -> ConversationPendingPointerStats {
        try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "read pending pointer stats",
                sql: """
                SELECT COUNT(*), MIN(inserted_at), MAX(inserted_at)
                FROM conversation_source_pointers
                WHERE processing_state = 'pending'
                """
            )
            guard try statement.step() == .row else {
                throw ConversationSourceIndexError.corruptData(
                    "pending pointer stats returned no row"
                )
            }
            let count = Int(statement.int64(at: 0))
            return ConversationPendingPointerStats(
                count: count,
                oldestInsertedAt: count == 0 ? nil : try statement.optionalDate(at: 1),
                latestInsertedAt: count == 0 ? nil : try statement.optionalDate(at: 2)
            )
        }
    }

    public func pendingThreadStats(provider: String = "codex") throws -> [ConversationPendingThreadStats] {
        try Self.validateProvider(provider)
        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "read pending thread stats",
                sql: """
                SELECT provider, thread_id, COUNT(*), MIN(sequence), MAX(timestamp)
                FROM conversation_source_pointers
                WHERE processing_state = 'pending' AND provider = ?
                GROUP BY provider, thread_id
                ORDER BY MIN(sequence) ASC, thread_id ASC
                """
            )
            try statement.bind(provider, at: 1)
            var values: [ConversationPendingThreadStats] = []
            while try statement.step() == .row {
                let pointerCount = statement.int64(at: 2)
                let firstSequence = statement.int64(at: 3)
                guard pointerCount > 0, firstSequence > 0 else {
                    throw ConversationSourceIndexError.corruptData(
                        "pending thread stats contain an invalid count or sequence"
                    )
                }
                values.append(
                    ConversationPendingThreadStats(
                        provider: try statement.requiredText(at: 0),
                        threadID: try statement.requiredText(at: 1),
                        pointerCount: Int(pointerCount),
                        firstSequence: firstSequence,
                        latestTimestamp: try statement.date(at: 4)
                    )
                )
            }
            return values
        }
    }

    public func pendingPointers(
        through highWaterMark: ConversationBatchHighWaterMark? = nil,
        limit: Int = 500
    ) throws -> [ConversationSourcePointerRecord] {
        try Self.validateLimit(limit)
        if let highWaterMark {
            try Self.validate(highWaterMark)
        }

        return try withDatabase { database in
            try loadPendingPointers(
                database,
                through: highWaterMark?.pointerSequence ?? Int64.max,
                limit: limit
            )
        }
    }

    public func pendingPointers(
        provider: String,
        threadIDs: Set<String>,
        through highWaterMark: ConversationBatchHighWaterMark? = nil,
        limit: Int = 500
    ) throws -> [ConversationSourcePointerRecord] {
        try Self.validateProvider(provider)
        try Self.validateLimit(limit)
        if let highWaterMark {
            try Self.validate(highWaterMark)
        }
        guard !threadIDs.isEmpty else { return [] }
        for threadID in threadIDs {
            try Self.validateRequiredText(threadID, field: "threadID")
        }

        return try withDatabase { database in
            var records: [ConversationSourcePointerRecord] = []
            for chunk in threadIDs.sorted().chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "read pending project pointers",
                    sql: """
                    SELECT sequence, provider, thread_id, turn_id, source_path,
                           start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                           processing_state, batch_id, project_id, failure_message,
                           inserted_at, updated_at
                    FROM conversation_source_pointers
                    WHERE processing_state = 'pending'
                      AND sequence <= ?
                      AND provider = ?
                      AND thread_id IN (\(placeholders))
                    ORDER BY sequence ASC
                    LIMIT ?
                    """
                )
                try statement.bind(highWaterMark?.pointerSequence ?? Int64.max, at: 1)
                try statement.bind(provider, at: 2)
                for (offset, threadID) in chunk.enumerated() {
                    try statement.bind(threadID, at: Int32(offset + 3))
                }
                try statement.bind(Int64(limit), at: Int32(chunk.count + 3))
                records.append(contentsOf: try readPointerRecords(statement))
            }
            return Array(records.sorted { $0.sequence < $1.sequence }.prefix(limit))
        }
    }

    public func createBatch(
        through highWaterMark: ConversationBatchHighWaterMark,
        limit: Int = 500,
        createdAt: Date = Date()
    ) throws -> ConversationProcessingBatch? {
        try Self.validate(highWaterMark)
        try Self.validateLimit(limit)
        try Self.validateDate(createdAt, field: "createdAt")

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                let pending = try loadPendingPointers(
                    database,
                    through: highWaterMark.pointerSequence,
                    limit: limit
                )
                guard !pending.isEmpty else { return nil }

                let batchID = UUID().uuidString.lowercased()
                let insertBatch = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "create processing batch",
                    sql: """
                    INSERT INTO conversation_processing_batches (
                        id, high_water_sequence, status, error_message,
                        created_at, finished_at, updated_at
                    ) VALUES (?, ?, ?, NULL, ?, NULL, ?)
                    """
                )
                try insertBatch.bind(batchID, at: 1)
                try insertBatch.bind(highWaterMark.pointerSequence, at: 2)
                try insertBatch.bind(ConversationProcessingBatchStatus.processing.rawValue, at: 3)
                try insertBatch.bind(createdAt.timeIntervalSince1970, at: 4)
                try insertBatch.bind(createdAt.timeIntervalSince1970, at: 5)
                try insertBatch.execute()

                let attachPointer = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "attach pointer to processing batch",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET processing_state = 'batched', batch_id = ?, updated_at = ?
                    WHERE sequence = ? AND processing_state = 'pending' AND batch_id IS NULL
                    """
                )
                for pointer in pending {
                    try attachPointer.bind(batchID, at: 1)
                    try attachPointer.bind(createdAt.timeIntervalSince1970, at: 2)
                    try attachPointer.bind(pointer.sequence, at: 3)
                    try attachPointer.execute()
                    guard sqlite3_changes(database) == 1 else {
                        throw ConversationSourceIndexError.corruptData(
                            "pointer sequence \(pointer.sequence) changed while creating batch"
                        )
                    }
                    try attachPointer.reset()
                }

                let attached = pending.map { record in
                    var record = record
                    record.processingState = .batched
                    record.batchID = batchID
                    record.updatedAt = createdAt
                    return record
                }
                return ConversationProcessingBatch(
                    id: batchID,
                    highWaterMark: highWaterMark,
                    status: .processing,
                    pointers: attached,
                    errorMessage: nil,
                    createdAt: createdAt,
                    finishedAt: nil,
                    updatedAt: createdAt
                )
            }
        }
    }

    public func createBatch(
        pointerIDs: [ConversationSourcePointerID],
        createdAt: Date = Date()
    ) throws -> ConversationProcessingBatch? {
        guard !pointerIDs.isEmpty else { return nil }
        try Self.validateDate(createdAt, field: "createdAt")
        let uniqueIDs = Set(pointerIDs)
        guard uniqueIDs.count == pointerIDs.count else {
            throw ConversationSourceIndexError.invalidInput(
                "targeted batch pointer IDs must be unique"
            )
        }
        for id in pointerIDs { try Self.validate(id) }

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                let records = try pointerIDs.map { id -> ConversationSourcePointerRecord in
                    guard let record = try pointerRecord(database, id: id),
                          record.processingState == .pending,
                          record.batchID == nil else {
                        throw ConversationSourceIndexError.invalidInput(
                            "targeted batch contains a non-pending pointer"
                        )
                    }
                    return record
                }
                let highWaterMark = ConversationBatchHighWaterMark(
                    pointerSequence: records.map(\.sequence).max() ?? 0
                )
                try Self.validate(highWaterMark)
                let batchID = UUID().uuidString.lowercased()
                let insertBatch = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "create targeted processing batch",
                    sql: """
                    INSERT INTO conversation_processing_batches (
                        id, high_water_sequence, status, error_message,
                        created_at, finished_at, updated_at
                    ) VALUES (?, ?, 'processing', NULL, ?, NULL, ?)
                    """
                )
                try insertBatch.bind(batchID, at: 1)
                try insertBatch.bind(highWaterMark.pointerSequence, at: 2)
                try insertBatch.bind(createdAt.timeIntervalSince1970, at: 3)
                try insertBatch.bind(createdAt.timeIntervalSince1970, at: 4)
                try insertBatch.execute()

                let attach = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "attach targeted batch pointer",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET processing_state = 'batched', batch_id = ?, updated_at = ?
                    WHERE provider = ? AND thread_id = ? AND turn_id = ?
                      AND processing_state = 'pending' AND batch_id IS NULL
                    """
                )
                for record in records {
                    try attach.bind(batchID, at: 1)
                    try attach.bind(createdAt.timeIntervalSince1970, at: 2)
                    try attach.bind(record.pointer.provider, at: 3)
                    try attach.bind(record.pointer.threadID, at: 4)
                    try attach.bind(record.pointer.turnID, at: 5)
                    try attach.execute()
                    guard sqlite3_changes(database) == 1 else {
                        throw ConversationSourceIndexError.corruptData(
                            "targeted pointer changed while creating batch"
                        )
                    }
                    try attach.reset()
                }
                let attached = records.map { record in
                    var record = record
                    record.processingState = .batched
                    record.batchID = batchID
                    record.updatedAt = createdAt
                    return record
                }
                return ConversationProcessingBatch(
                    id: batchID,
                    highWaterMark: highWaterMark,
                    status: .processing,
                    pointers: attached,
                    errorMessage: nil,
                    createdAt: createdAt,
                    finishedAt: nil,
                    updatedAt: createdAt
                )
            }
        }
    }

    public func batch(id: String) throws -> ConversationProcessingBatch? {
        try Self.validateRequiredText(id, field: "batchID")
        return try withDatabase { database in
            try loadBatch(database, id: id)
        }
    }

    public func processingBatches() throws -> [ConversationProcessingBatch] {
        let ids = try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "read processing batches",
                sql: """
                SELECT id
                FROM conversation_processing_batches
                WHERE status = 'processing'
                ORDER BY created_at ASC, id ASC
                """
            )
            var values: [String] = []
            while try statement.step() == .row {
                values.append(try statement.requiredText(at: 0))
            }
            return values
        }
        return try ids.compactMap { try batch(id: $0) }
    }

    public func semanticBundles(limit: Int = 100) throws -> [ConversationSemanticBundle] {
        try Self.validateLimit(limit)
        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "read semantic bundles",
                sql: """
                SELECT id
                FROM conversation_semantic_bundles
                ORDER BY updated_at DESC, id ASC
                LIMIT ?
                """
            )
            try statement.bind(Int64(limit), at: 1)
            var bundles: [ConversationSemanticBundle] = []
            while try statement.step() == .row {
                let id = try statement.requiredText(at: 0)
                guard let bundle = try semanticBundle(database, id: id) else {
                    throw ConversationSourceIndexError.corruptData(
                        "semantic bundle disappeared while reading: \(id)"
                    )
                }
                bundles.append(bundle)
            }
            return bundles
        }
    }

    @discardableResult
    public func failInterruptedBatches(
        at failedAt: Date = Date()
    ) throws -> Int {
        let batches = try processingBatches()
        for batch in batches {
            _ = try markBatchFailed(
                batch.id,
                errorMessage: "Processing was interrupted; automatic retry is disabled",
                failedAt: failedAt
            )
        }
        return batches.count
    }

    @discardableResult
    public func markBatchCompleted(
        _ batchID: String,
        projectAssignments: [ConversationPointerProjectAssignment] = [],
        completedAt: Date = Date()
    ) throws -> ConversationProcessingBatch {
        try Self.validateRequiredText(batchID, field: "batchID")
        try Self.validateDate(completedAt, field: "completedAt")

        var assignedPointerIDs = Set<ConversationSourcePointerID>()
        for assignment in projectAssignments {
            try Self.validate(assignment.pointerID)
            try Self.validateRequiredText(assignment.projectID, field: "projectID")
            guard assignedPointerIDs.insert(assignment.pointerID).inserted else {
                throw ConversationSourceIndexError.invalidInput(
                    "projectAssignments contains duplicate pointer IDs"
                )
            }
        }

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                guard let current = try loadBatch(database, id: batchID) else {
                    throw ConversationSourceIndexError.missingBatch(batchID)
                }
                guard current.status == .processing else {
                    throw ConversationSourceIndexError.invalidBatchState(id: batchID, actual: current.status)
                }

                let members = Dictionary(uniqueKeysWithValues: current.pointers.map { ($0.id, $0) })
                let assignProject = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "assign pointer project",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET project_id = ?, updated_at = ?
                    WHERE provider = ? AND thread_id = ? AND turn_id = ?
                      AND batch_id = ? AND processing_state = 'batched'
                    """
                )
                for assignment in projectAssignments {
                    guard members[assignment.pointerID] != nil else {
                        throw ConversationSourceIndexError.pointerNotInBatch(
                            pointerID: assignment.pointerID,
                            batchID: batchID
                        )
                    }
                    try assignProject.bind(assignment.projectID, at: 1)
                    try assignProject.bind(completedAt.timeIntervalSince1970, at: 2)
                    try assignProject.bind(assignment.pointerID.provider, at: 3)
                    try assignProject.bind(assignment.pointerID.threadID, at: 4)
                    try assignProject.bind(assignment.pointerID.turnID, at: 5)
                    try assignProject.bind(batchID, at: 6)
                    try assignProject.execute()
                    guard sqlite3_changes(database) == 1 else {
                        throw ConversationSourceIndexError.pointerNotInBatch(
                            pointerID: assignment.pointerID,
                            batchID: batchID
                        )
                    }
                    try assignProject.reset()
                }

                let completePointers = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "complete batch pointers",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET processing_state = 'completed', failure_message = NULL, updated_at = ?
                    WHERE batch_id = ? AND processing_state = 'batched'
                    """
                )
                try completePointers.bind(completedAt.timeIntervalSince1970, at: 1)
                try completePointers.bind(batchID, at: 2)
                try completePointers.execute()
                guard Int(sqlite3_changes(database)) == current.pointers.count else {
                    throw ConversationSourceIndexError.corruptData(
                        "batch \(batchID) pointer count changed before completion"
                    )
                }

                try finishBatch(
                    database,
                    batchID: batchID,
                    status: .completed,
                    errorMessage: nil,
                    finishedAt: completedAt
                )
                guard let completed = try loadBatch(database, id: batchID) else {
                    throw ConversationSourceIndexError.missingBatch(batchID)
                }
                return completed
            }
        }
    }

    @discardableResult
    public func markBatchFailed(
        _ batchID: String,
        errorMessage: String,
        failedAt: Date = Date()
    ) throws -> ConversationProcessingBatch {
        try Self.validateRequiredText(batchID, field: "batchID")
        try Self.validateRequiredText(errorMessage, field: "errorMessage")
        try Self.validateDate(failedAt, field: "failedAt")

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                guard let current = try loadBatch(database, id: batchID) else {
                    throw ConversationSourceIndexError.missingBatch(batchID)
                }
                guard current.status == .processing else {
                    throw ConversationSourceIndexError.invalidBatchState(id: batchID, actual: current.status)
                }

                let failPointers = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "fail batch pointers",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET processing_state = 'failed', failure_message = ?, updated_at = ?
                    WHERE batch_id = ? AND processing_state = 'batched'
                    """
                )
                try failPointers.bind(errorMessage, at: 1)
                try failPointers.bind(failedAt.timeIntervalSince1970, at: 2)
                try failPointers.bind(batchID, at: 3)
                try failPointers.execute()
                guard Int(sqlite3_changes(database)) == current.pointers.count else {
                    throw ConversationSourceIndexError.corruptData(
                        "batch \(batchID) pointer count changed before failure"
                    )
                }

                try finishBatch(
                    database,
                    batchID: batchID,
                    status: .failed,
                    errorMessage: errorMessage,
                    finishedAt: failedAt
                )
                guard let failed = try loadBatch(database, id: batchID) else {
                    throw ConversationSourceIndexError.missingBatch(batchID)
                }
                return failed
            }
        }
    }

    @discardableResult
    public func finalizeBatch(
        _ batchID: String,
        completedPointerIDs: [ConversationSourcePointerID],
        projectAssignments: [ConversationPointerProjectAssignment] = [],
        failedPointerIDs: [ConversationSourcePointerID] = [],
        semanticBundleMutations: [ConversationSemanticBundleMutation] = [],
        errorMessage: String? = nil,
        finishedAt: Date = Date()
    ) throws -> ConversationProcessingBatch {
        try Self.validateRequiredText(batchID, field: "batchID")
        try Self.validateDate(finishedAt, field: "finishedAt")
        let completed = Set(completedPointerIDs)
        let failed = Set(failedPointerIDs)
        guard completed.count == completedPointerIDs.count,
              failed.count == failedPointerIDs.count,
              completed.isDisjoint(with: failed) else {
            throw ConversationSourceIndexError.invalidInput(
                "finalized pointer IDs must be unique and disjoint"
            )
        }
        for id in completed.union(failed) { try Self.validate(id) }
        if failed.isEmpty {
            guard errorMessage == nil else {
                throw ConversationSourceIndexError.invalidInput(
                    "a completed batch cannot have an error message"
                )
            }
        } else {
            try Self.validateRequiredText(errorMessage ?? "", field: "errorMessage")
        }
        var assignmentByID: [ConversationSourcePointerID: String] = [:]
        for assignment in projectAssignments {
            guard completed.contains(assignment.pointerID),
                  assignmentByID.updateValue(
                    assignment.projectID,
                    forKey: assignment.pointerID
                  ) == nil else {
                throw ConversationSourceIndexError.invalidInput(
                    "project assignments must be unique completed pointers"
                )
            }
        }
        for projectID in assignmentByID.values {
            try Self.validateRequiredText(projectID, field: "projectID")
        }
        try Self.validate(semanticBundleMutations)

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                guard let current = try loadBatch(database, id: batchID) else {
                    throw ConversationSourceIndexError.missingBatch(batchID)
                }
                guard current.status == .processing else {
                    throw ConversationSourceIndexError.invalidBatchState(id: batchID, actual: current.status)
                }
                let members = Set(current.pointers.map(\.id))
                guard completed.union(failed) == members else {
                    throw ConversationSourceIndexError.invalidInput(
                        "batch finalization must account for every pointer exactly once"
                    )
                }

                let complete = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "complete batch pointer",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET processing_state = 'completed', project_id = ?,
                        failure_message = NULL, updated_at = ?
                    WHERE provider = ? AND thread_id = ? AND turn_id = ?
                      AND batch_id = ? AND processing_state = 'batched'
                    """
                )
                for id in completedPointerIDs {
                    try complete.bind(assignmentByID[id], at: 1)
                    try complete.bind(finishedAt.timeIntervalSince1970, at: 2)
                    try complete.bind(id.provider, at: 3)
                    try complete.bind(id.threadID, at: 4)
                    try complete.bind(id.turnID, at: 5)
                    try complete.bind(batchID, at: 6)
                    try complete.execute()
                    guard sqlite3_changes(database) == 1 else {
                        throw ConversationSourceIndexError.pointerNotInBatch(
                            pointerID: id,
                            batchID: batchID
                        )
                    }
                    try complete.reset()
                }

                if !failedPointerIDs.isEmpty {
                    let fail = try ConversationSQLiteStatement(
                        database: database,
                        databasePath: databaseURL.path,
                        operation: "fail batch pointer",
                        sql: """
                        UPDATE conversation_source_pointers
                        SET processing_state = 'failed', failure_message = ?, updated_at = ?
                        WHERE provider = ? AND thread_id = ? AND turn_id = ?
                          AND batch_id = ? AND processing_state = 'batched'
                        """
                    )
                    for id in failedPointerIDs {
                        try fail.bind(errorMessage, at: 1)
                        try fail.bind(finishedAt.timeIntervalSince1970, at: 2)
                        try fail.bind(id.provider, at: 3)
                        try fail.bind(id.threadID, at: 4)
                        try fail.bind(id.turnID, at: 5)
                        try fail.bind(batchID, at: 6)
                        try fail.execute()
                        guard sqlite3_changes(database) == 1 else {
                            throw ConversationSourceIndexError.pointerNotInBatch(
                                pointerID: id,
                                batchID: batchID
                            )
                        }
                        try fail.reset()
                    }
                }

                try applySemanticBundleMutations(
                    semanticBundleMutations,
                    database: database
                )

                try finishBatch(
                    database,
                    batchID: batchID,
                    status: failed.isEmpty ? .completed : .failed,
                    errorMessage: failed.isEmpty ? nil : errorMessage,
                    finishedAt: finishedAt
                )
                guard let result = try loadBatch(database, id: batchID) else {
                    throw ConversationSourceIndexError.missingBatch(batchID)
                }
                return result
            }
        }
    }

    @discardableResult
    public func requeueFailedPointers(
        _ pointerIDs: [ConversationSourcePointerID],
        at updatedAt: Date = Date()
    ) throws -> Int {
        guard !pointerIDs.isEmpty else { return 0 }
        try Self.validateDate(updatedAt, field: "updatedAt")
        let uniqueIDs = Set(pointerIDs)
        guard uniqueIDs.count == pointerIDs.count else {
            throw ConversationSourceIndexError.invalidInput(
                "requeued pointer IDs must be unique"
            )
        }
        for id in pointerIDs { try Self.validate(id) }

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                for id in pointerIDs {
                    guard let record = try pointerRecord(database, id: id),
                          record.processingState == .failed,
                          let batchID = record.batchID,
                          let batch = try loadBatch(database, id: batchID),
                          batch.status == .failed else {
                        throw ConversationSourceIndexError.invalidInput(
                            "only pointers from failed batches can be requeued"
                        )
                    }
                }
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "requeue failed conversation pointer",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET processing_state = 'pending', batch_id = NULL,
                        project_id = NULL, failure_message = NULL, updated_at = ?
                    WHERE provider = ? AND thread_id = ? AND turn_id = ?
                      AND processing_state = 'failed'
                    """
                )
                for id in pointerIDs {
                    try statement.bind(updatedAt.timeIntervalSince1970, at: 1)
                    try statement.bind(id.provider, at: 2)
                    try statement.bind(id.threadID, at: 3)
                    try statement.bind(id.turnID, at: 4)
                    try statement.execute()
                    guard sqlite3_changes(database) == 1 else {
                        throw ConversationSourceIndexError.corruptData(
                            "failed pointer changed before it could be requeued"
                        )
                    }
                    try statement.reset()
                }
                return pointerIDs.count
            }
        }
    }

    public func reassignCompletedPointers(
        _ pointerIDs: [ConversationSourcePointerID],
        to projectID: String,
        at updatedAt: Date = Date()
    ) throws -> Int {
        guard !pointerIDs.isEmpty else { return 0 }
        try Self.validateRequiredText(projectID, field: "projectID")
        try Self.validateDate(updatedAt, field: "updatedAt")
        let uniqueIDs = Set(pointerIDs)
        guard uniqueIDs.count == pointerIDs.count else {
            throw ConversationSourceIndexError.invalidInput(
                "reassigned pointer IDs must be unique"
            )
        }
        for id in pointerIDs { try Self.validate(id) }

        return try withDatabase { database in
            try withImmediateTransaction(database) {
                for id in pointerIDs {
                    guard let record = try pointerRecord(database, id: id),
                          record.processingState == .completed else {
                        throw ConversationSourceIndexError.invalidInput(
                            "only completed pointers can be reassigned"
                        )
                    }
                }
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "reassign completed conversation pointer",
                    sql: """
                    UPDATE conversation_source_pointers
                    SET project_id = ?, updated_at = ?
                    WHERE provider = ? AND thread_id = ? AND turn_id = ?
                      AND processing_state = 'completed'
                    """
                )
                for id in pointerIDs {
                    try statement.bind(projectID, at: 1)
                    try statement.bind(updatedAt.timeIntervalSince1970, at: 2)
                    try statement.bind(id.provider, at: 3)
                    try statement.bind(id.threadID, at: 4)
                    try statement.bind(id.turnID, at: 5)
                    try statement.execute()
                    guard sqlite3_changes(database) == 1 else {
                        throw ConversationSourceIndexError.corruptData(
                            "completed pointer changed before it could be reassigned"
                        )
                    }
                    try statement.reset()
                }
                return pointerIDs.count
            }
        }
    }

    public func pointers(
        projectID: String,
        from: Date? = nil,
        through: Date? = nil,
        afterSequence: Int64? = nil,
        limit: Int = 500
    ) throws -> [ConversationSourcePointerRecord] {
        try Self.validateRequiredText(projectID, field: "projectID")
        try Self.validateRange(from: from, through: through, afterSequence: afterSequence, limit: limit)

        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "query project pointers",
                sql: """
                SELECT sequence, provider, thread_id, turn_id, source_path,
                       start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                       processing_state, batch_id, project_id, failure_message,
                       inserted_at, updated_at
                FROM conversation_source_pointers
                WHERE project_id = ?
                  AND (? IS NULL OR timestamp >= ?)
                  AND (? IS NULL OR timestamp <= ?)
                  AND (? IS NULL OR sequence > ?)
                ORDER BY timestamp ASC, sequence ASC
                LIMIT ?
                """
            )
            try statement.bind(projectID, at: 1)
            try statement.bind(from?.timeIntervalSince1970, at: 2)
            try statement.bind(from?.timeIntervalSince1970, at: 3)
            try statement.bind(through?.timeIntervalSince1970, at: 4)
            try statement.bind(through?.timeIntervalSince1970, at: 5)
            try statement.bind(afterSequence, at: 6)
            try statement.bind(afterSequence, at: 7)
            try statement.bind(Int64(limit), at: 8)
            return try readPointerRecords(statement)
        }
    }

    public func pointers(
        provider: String,
        threadID: String,
        from: Date? = nil,
        through: Date? = nil,
        afterSequence: Int64? = nil,
        limit: Int = 500
    ) throws -> [ConversationSourcePointerRecord] {
        try Self.validateProvider(provider)
        try Self.validateRequiredText(threadID, field: "threadID")
        try Self.validateRange(from: from, through: through, afterSequence: afterSequence, limit: limit)

        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "query thread pointers",
                sql: """
                SELECT sequence, provider, thread_id, turn_id, source_path,
                       start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                       processing_state, batch_id, project_id, failure_message,
                       inserted_at, updated_at
                FROM conversation_source_pointers
                WHERE provider = ? AND thread_id = ?
                  AND (? IS NULL OR timestamp >= ?)
                  AND (? IS NULL OR timestamp <= ?)
                  AND (? IS NULL OR sequence > ?)
                ORDER BY timestamp ASC, sequence ASC
                LIMIT ?
                """
            )
            try statement.bind(provider, at: 1)
            try statement.bind(threadID, at: 2)
            try statement.bind(from?.timeIntervalSince1970, at: 3)
            try statement.bind(from?.timeIntervalSince1970, at: 4)
            try statement.bind(through?.timeIntervalSince1970, at: 5)
            try statement.bind(through?.timeIntervalSince1970, at: 6)
            try statement.bind(afterSequence, at: 7)
            try statement.bind(afterSequence, at: 8)
            try statement.bind(Int64(limit), at: 9)
            return try readPointerRecords(statement)
        }
    }

    public func pointer(id: ConversationSourcePointerID) throws -> ConversationSourcePointerRecord? {
        try Self.validate(id)
        return try withDatabase { database in
            try pointerRecord(database, id: id)
        }
    }

    public func recentPointers(
        provider: String,
        threadID: String,
        before: Date,
        limit: Int
    ) throws -> [ConversationSourcePointerRecord] {
        try Self.validateProvider(provider)
        try Self.validateRequiredText(threadID, field: "threadID")
        try Self.validateDate(before, field: "before")
        try Self.validateLimit(limit)
        return try withDatabase { database in
            let statement = try ConversationSQLiteStatement(
                database: database,
                databasePath: databaseURL.path,
                operation: "query recent thread pointers",
                sql: """
                SELECT sequence, provider, thread_id, turn_id, source_path,
                       start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                       processing_state, batch_id, project_id, failure_message,
                       inserted_at, updated_at
                FROM conversation_source_pointers
                WHERE provider = ? AND thread_id = ? AND timestamp < ?
                ORDER BY timestamp DESC, sequence DESC
                LIMIT ?
                """
            )
            try statement.bind(provider, at: 1)
            try statement.bind(threadID, at: 2)
            try statement.bind(before.timeIntervalSince1970, at: 3)
            try statement.bind(Int64(limit), at: 4)
            return Array(try readPointerRecords(statement).reversed())
        }
    }

    public func pointers(ids: [ConversationSourcePointerID]) throws -> [ConversationSourcePointerRecord] {
        guard !ids.isEmpty else { return [] }
        for id in ids {
            try Self.validate(id)
        }
        return try withDatabase { database in
            try ids.compactMap { try pointerRecord(database, id: $0) }
        }
    }

    @discardableResult
    public func deletePendingPointers(ids: [ConversationSourcePointerID]) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        for id in ids {
            try Self.validate(id)
        }
        return try withDatabase { database in
            try withImmediateTransaction(database) {
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "delete pending conversation pointer",
                    sql: """
                    DELETE FROM conversation_source_pointers
                    WHERE provider = ? AND thread_id = ? AND turn_id = ?
                      AND processing_state = 'pending'
                    """
                )
                var deleted = 0
                for id in ids {
                    try statement.bind(id.provider, at: 1)
                    try statement.bind(id.threadID, at: 2)
                    try statement.bind(id.turnID, at: 3)
                    try statement.execute()
                    deleted += Int(sqlite3_changes(database))
                    try statement.reset()
                }
                return deleted
            }
        }
    }

    @discardableResult
    public func deletePendingPointers(before cutoff: Date) throws -> [ConversationSourcePointerID] {
        try Self.validateDate(cutoff, field: "cutoff")
        return try withDatabase { database in
            try withImmediateTransaction(database) {
                let query = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "read disabled-period pending pointers",
                    sql: """
                    SELECT provider, thread_id, turn_id
                    FROM conversation_source_pointers
                    WHERE processing_state = 'pending' AND timestamp < ?
                    ORDER BY sequence ASC
                    """
                )
                try query.bind(cutoff.timeIntervalSince1970, at: 1)
                var ids: [ConversationSourcePointerID] = []
                while try query.step() == .row {
                    ids.append(
                        ConversationSourcePointerID(
                            provider: try query.requiredText(at: 0),
                            threadID: try query.requiredText(at: 1),
                            turnID: try query.requiredText(at: 2)
                        )
                    )
                }
                guard !ids.isEmpty else { return [] }

                let delete = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "delete disabled-period pending pointers",
                    sql: """
                    DELETE FROM conversation_source_pointers
                    WHERE processing_state = 'pending' AND timestamp < ?
                    """
                )
                try delete.bind(cutoff.timeIntervalSince1970, at: 1)
                try delete.execute()
                guard Int(sqlite3_changes(database)) == ids.count else {
                    throw ConversationSourceIndexError.corruptData(
                        "disabled-period pending pointers changed during deletion"
                    )
                }
                return ids
            }
        }
    }

    private func configureDatabase(
        _ database: OpaquePointer,
        busyTimeoutMilliseconds: Int32,
        walAutoCheckpointPages: Int32
    ) throws {
        let timeoutResult = sqlite3_busy_timeout(database, busyTimeoutMilliseconds)
        try checkSQLite(
            timeoutResult,
            database: database,
            operation: "configure busy timeout"
        )

        try executeStatic(database, sql: "PRAGMA foreign_keys = ON", operation: "enable foreign keys")
        guard try scalarInt64(database, sql: "PRAGMA foreign_keys", operation: "verify foreign keys") == 1 else {
            throw ConversationSourceIndexError.corruptData("SQLite foreign_keys could not be enabled")
        }

        let journalMode = try scalarText(
            database,
            sql: "PRAGMA journal_mode = WAL",
            operation: "enable WAL"
        )
        guard journalMode.lowercased() == "wal" else {
            throw ConversationSourceIndexError.corruptData(
                "SQLite journal mode is \(journalMode), expected wal"
            )
        }

        try executeStatic(database, sql: "PRAGMA synchronous = NORMAL", operation: "configure synchronous mode")
        let checkpointResult = sqlite3_wal_autocheckpoint(database, walAutoCheckpointPages)
        try checkSQLite(
            checkpointResult,
            database: database,
            operation: "configure WAL autocheckpoint"
        )
    }

    private func initializeSchema(_ database: OpaquePointer) throws {
        let version = try scalarInt64(database, sql: "PRAGMA user_version", operation: "read schema version")
        guard version == 0 || version == 1 || version == 2 || version == 3
                || version == Self.schemaVersion else {
            throw ConversationSourceIndexError.unsupportedSchemaVersion(version)
        }

        try withImmediateTransaction(database) {
            try executeStatic(
                database,
                sql: """
                CREATE TABLE IF NOT EXISTS conversation_processing_batches (
                    id TEXT PRIMARY KEY NOT NULL CHECK(length(id) > 0),
                    high_water_sequence INTEGER NOT NULL CHECK(high_water_sequence > 0),
                    status TEXT NOT NULL CHECK(status IN ('processing', 'completed', 'failed')),
                    error_message TEXT,
                    created_at REAL NOT NULL,
                    finished_at REAL,
                    updated_at REAL NOT NULL,
                    CHECK(
                        (status = 'processing' AND error_message IS NULL AND finished_at IS NULL)
                        OR (status = 'completed' AND error_message IS NULL AND finished_at IS NOT NULL)
                        OR (status = 'failed' AND error_message IS NOT NULL AND finished_at IS NOT NULL)
                    )
                )
                """,
                operation: "create batch schema"
            )
            try executeStatic(
                database,
                sql: """
                CREATE TABLE IF NOT EXISTS conversation_source_pointers (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider TEXT NOT NULL CHECK(length(provider) > 0),
                    thread_id TEXT NOT NULL CHECK(length(thread_id) > 0),
                    turn_id TEXT NOT NULL CHECK(length(turn_id) > 0),
                    source_path TEXT NOT NULL CHECK(length(source_path) > 0),
                    start_offset INTEGER NOT NULL CHECK(start_offset >= 0),
                    end_offset INTEGER NOT NULL CHECK(end_offset >= start_offset),
                    timestamp REAL NOT NULL,
                    cwd TEXT NOT NULL,
                    content_hash TEXT NOT NULL CHECK(length(content_hash) > 0),
                    message_spans_json TEXT NOT NULL,
                    processing_state TEXT NOT NULL CHECK(
                        processing_state IN ('pending', 'batched', 'completed', 'failed')
                    ),
                    batch_id TEXT REFERENCES conversation_processing_batches(id) ON DELETE RESTRICT,
                    project_id TEXT CHECK(project_id IS NULL OR length(project_id) > 0),
                    failure_message TEXT,
                    inserted_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    UNIQUE(provider, thread_id, turn_id),
                    CHECK(
                        (processing_state = 'pending' AND batch_id IS NULL AND failure_message IS NULL)
                        OR (processing_state = 'batched' AND batch_id IS NOT NULL AND failure_message IS NULL)
                        OR (processing_state = 'completed' AND batch_id IS NOT NULL AND failure_message IS NULL)
                        OR (processing_state = 'failed' AND batch_id IS NOT NULL AND failure_message IS NOT NULL)
                    )
                )
                """,
                operation: "create pointer schema"
            )
            try executeStatic(
                database,
                sql: """
                CREATE TABLE IF NOT EXISTS conversation_scan_cursors (
                    provider TEXT NOT NULL CHECK(length(provider) > 0),
                    source_path TEXT NOT NULL CHECK(length(source_path) > 0),
                    next_offset INTEGER NOT NULL CHECK(next_offset >= 0),
                    updated_at REAL NOT NULL,
                    cursor_json TEXT NOT NULL,
                    PRIMARY KEY(provider, source_path)
                )
                """,
                operation: "create scan cursor schema"
            )
            try executeStatic(
                database,
                sql: """
                CREATE TABLE IF NOT EXISTS conversation_semantic_bundles (
                    id TEXT PRIMARY KEY NOT NULL CHECK(length(id) > 0),
                    thread_id TEXT NOT NULL CHECK(length(thread_id) > 0),
                    project_id TEXT NOT NULL CHECK(length(project_id) > 0),
                    title TEXT NOT NULL CHECK(length(title) > 0),
                    summary TEXT NOT NULL CHECK(length(summary) > 0),
                    updated_at REAL NOT NULL
                )
                """,
                operation: "create semantic bundle schema"
            )
            try executeStatic(
                database,
                sql: """
                CREATE TABLE IF NOT EXISTS conversation_semantic_bundle_members (
                    bundle_id TEXT NOT NULL REFERENCES conversation_semantic_bundles(id)
                        ON DELETE CASCADE,
                    provider TEXT NOT NULL,
                    thread_id TEXT NOT NULL,
                    turn_id TEXT NOT NULL,
                    position INTEGER NOT NULL CHECK(position >= 0),
                    PRIMARY KEY(bundle_id, provider, thread_id, turn_id),
                    UNIQUE(provider, thread_id, turn_id),
                    FOREIGN KEY(provider, thread_id, turn_id)
                        REFERENCES conversation_source_pointers(provider, thread_id, turn_id)
                        ON DELETE RESTRICT
                )
                """,
                operation: "create semantic bundle member schema"
            )
            try executeStatic(
                database,
                sql: """
                CREATE INDEX IF NOT EXISTS idx_conversation_pointers_pending
                ON conversation_source_pointers(processing_state, sequence)
                """,
                operation: "create pending pointer index"
            )
            try executeStatic(
                database,
                sql: """
                CREATE INDEX IF NOT EXISTS idx_conversation_pointers_thread_time
                ON conversation_source_pointers(provider, thread_id, timestamp, sequence)
                """,
                operation: "create thread pointer index"
            )
            try executeStatic(
                database,
                sql: """
                CREATE INDEX IF NOT EXISTS idx_conversation_pointers_project_time
                ON conversation_source_pointers(project_id, timestamp, sequence)
                WHERE project_id IS NOT NULL
                """,
                operation: "create project pointer index"
            )
            try executeStatic(
                database,
                sql: """
                CREATE INDEX IF NOT EXISTS idx_conversation_pointers_batch
                ON conversation_source_pointers(batch_id, timestamp, sequence)
                WHERE batch_id IS NOT NULL
                """,
                operation: "create batch pointer index"
            )
            if version == 1 {
                try executeStatic(
                    database,
                    sql: """
                    ALTER TABLE conversation_source_pointers
                    ADD COLUMN message_spans_json TEXT NOT NULL DEFAULT '[]'
                    """,
                    operation: "migrate pointer message spans"
                )
            }
            if version == 1 || version == 2 {
                try executeStatic(
                    database,
                    sql: """
                    ALTER TABLE conversation_scan_cursors
                    ADD COLUMN cursor_json TEXT NOT NULL DEFAULT ''
                    """,
                    operation: "migrate scan cursor metadata"
                )
            }
            if version < Self.schemaVersion {
                try executeStatic(
                    database,
                    sql: "PRAGMA user_version = 4",
                    operation: "write schema version"
                )
            }
        }
    }

    private func insertPointer(
        _ database: OpaquePointer,
        pointer: ConversationSourcePointer,
        insertedAt: Date
    ) throws {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "insert conversation pointer",
            sql: """
            INSERT INTO conversation_source_pointers (
                provider, thread_id, turn_id, source_path,
                start_offset, end_offset, timestamp, cwd, content_hash,
                message_spans_json,
                processing_state, batch_id, project_id, failure_message,
                inserted_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, NULL, ?, ?)
            """
        )
        try bind(pointer, to: statement)
        try statement.bind(insertedAt.timeIntervalSince1970, at: 11)
        try statement.bind(insertedAt.timeIntervalSince1970, at: 12)
        try statement.execute()
    }

    private func semanticBundle(
        _ database: OpaquePointer,
        id: String
    ) throws -> ConversationSemanticBundle? {
        let bundleStatement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "read semantic bundle",
            sql: """
            SELECT id, thread_id, project_id, title, summary, updated_at
            FROM conversation_semantic_bundles
            WHERE id = ?
            """
        )
        try bundleStatement.bind(id, at: 1)
        guard try bundleStatement.step() == .row else { return nil }

        let memberStatement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "read semantic bundle members",
            sql: """
            SELECT provider, thread_id, turn_id
            FROM conversation_semantic_bundle_members
            WHERE bundle_id = ?
            ORDER BY position ASC
            """
        )
        try memberStatement.bind(id, at: 1)
        var pointerIDs: [ConversationSourcePointerID] = []
        while try memberStatement.step() == .row {
            pointerIDs.append(
                ConversationSourcePointerID(
                    provider: try memberStatement.requiredText(at: 0),
                    threadID: try memberStatement.requiredText(at: 1),
                    turnID: try memberStatement.requiredText(at: 2)
                )
            )
        }
        guard !pointerIDs.isEmpty else {
            throw ConversationSourceIndexError.corruptData(
                "semantic bundle has no members: \(id)"
            )
        }
        return ConversationSemanticBundle(
            id: try bundleStatement.requiredText(at: 0),
            threadID: try bundleStatement.requiredText(at: 1),
            projectID: try bundleStatement.requiredText(at: 2),
            title: try bundleStatement.requiredText(at: 3),
            summary: try bundleStatement.requiredText(at: 4),
            pointerIDs: pointerIDs,
            updatedAt: try bundleStatement.date(at: 5)
        )
    }

    private func applySemanticBundleMutations(
        _ mutations: [ConversationSemanticBundleMutation],
        database: OpaquePointer
    ) throws {
        for mutation in mutations {
            switch mutation {
            case .close(let bundleID):
                let statement = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "close semantic bundle",
                    sql: "DELETE FROM conversation_semantic_bundles WHERE id = ?"
                )
                try statement.bind(bundleID, at: 1)
                try statement.execute()
                guard sqlite3_changes(database) == 1 else {
                    throw ConversationSourceIndexError.corruptData(
                        "semantic bundle is missing while closing: \(bundleID)"
                    )
                }
            case .upsert(let bundle):
                guard bundle.pointerIDs.count <= Self.maximumSemanticBundlePointers else {
                    throw ConversationSourceIndexError.invalidInput(
                        "semantic bundle exceeds 100 source pointers"
                    )
                }
                var sourceBytes: UInt64 = 0
                for pointerID in bundle.pointerIDs {
                    guard let pointer = try pointerRecord(database, id: pointerID),
                          pointer.processingState == .completed else {
                        throw ConversationSourceIndexError.corruptData(
                            "semantic bundle member is not completed: \(pointerID.threadID)/\(pointerID.turnID)"
                        )
                    }
                    let bytes = Self.relevantBytes(pointer.pointer)
                    let (nextBytes, overflow) = sourceBytes.addingReportingOverflow(bytes)
                    guard !overflow, nextBytes <= Self.maximumSemanticBundleBytes else {
                        throw ConversationSourceIndexError.invalidInput(
                            "semantic bundle exceeds 768 KiB of source evidence"
                        )
                    }
                    sourceBytes = nextBytes
                }
                let upsert = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "upsert semantic bundle",
                    sql: """
                    INSERT INTO conversation_semantic_bundles (
                        id, thread_id, project_id, title, summary, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        thread_id = excluded.thread_id,
                        project_id = excluded.project_id,
                        title = excluded.title,
                        summary = excluded.summary,
                        updated_at = excluded.updated_at
                    """
                )
                try upsert.bind(bundle.id, at: 1)
                try upsert.bind(bundle.threadID, at: 2)
                try upsert.bind(bundle.projectID, at: 3)
                try upsert.bind(bundle.title, at: 4)
                try upsert.bind(bundle.summary, at: 5)
                try upsert.bind(bundle.updatedAt.timeIntervalSince1970, at: 6)
                try upsert.execute()

                let deleteMembers = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "replace semantic bundle members",
                    sql: "DELETE FROM conversation_semantic_bundle_members WHERE bundle_id = ?"
                )
                try deleteMembers.bind(bundle.id, at: 1)
                try deleteMembers.execute()

                let insertMember = try ConversationSQLiteStatement(
                    database: database,
                    databasePath: databaseURL.path,
                    operation: "insert semantic bundle member",
                    sql: """
                    INSERT INTO conversation_semantic_bundle_members (
                        bundle_id, provider, thread_id, turn_id, position
                    ) VALUES (?, ?, ?, ?, ?)
                    """
                )
                for (position, pointerID) in bundle.pointerIDs.enumerated() {
                    try insertMember.bind(bundle.id, at: 1)
                    try insertMember.bind(pointerID.provider, at: 2)
                    try insertMember.bind(pointerID.threadID, at: 3)
                    try insertMember.bind(pointerID.turnID, at: 4)
                    try insertMember.bind(Int64(position), at: 5)
                    try insertMember.execute()
                    try insertMember.reset()
                }
            }
        }
    }

    private func updatePendingPointer(
        _ database: OpaquePointer,
        pointer: ConversationSourcePointer,
        updatedAt: Date
    ) throws {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "update pending conversation pointer",
            sql: """
            UPDATE conversation_source_pointers
            SET source_path = ?, start_offset = ?, end_offset = ?, timestamp = ?,
                cwd = ?, content_hash = ?, message_spans_json = ?, updated_at = ?
            WHERE provider = ? AND thread_id = ? AND turn_id = ?
              AND processing_state = 'pending'
            """
        )
        try statement.bind(pointer.sourcePath, at: 1)
        try statement.bind(Int64(pointer.startOffset), at: 2)
        try statement.bind(Int64(pointer.endOffset), at: 3)
        try statement.bind(pointer.timestamp.timeIntervalSince1970, at: 4)
        try statement.bind(pointer.cwd, at: 5)
        try statement.bind(pointer.contentHash, at: 6)
        try statement.bind(try Self.encodeSpans(pointer.messageSpans), at: 7)
        try statement.bind(updatedAt.timeIntervalSince1970, at: 8)
        try statement.bind(pointer.provider, at: 9)
        try statement.bind(pointer.threadID, at: 10)
        try statement.bind(pointer.turnID, at: 11)
        try statement.execute()
        guard sqlite3_changes(database) == 1 else {
            throw ConversationSourceIndexError.pointerChangedAfterProcessing(pointer.id)
        }
    }

    private func bind(
        _ pointer: ConversationSourcePointer,
        to statement: ConversationSQLiteStatement
    ) throws {
        try statement.bind(pointer.provider, at: 1)
        try statement.bind(pointer.threadID, at: 2)
        try statement.bind(pointer.turnID, at: 3)
        try statement.bind(pointer.sourcePath, at: 4)
        try statement.bind(Int64(pointer.startOffset), at: 5)
        try statement.bind(Int64(pointer.endOffset), at: 6)
        try statement.bind(pointer.timestamp.timeIntervalSince1970, at: 7)
        try statement.bind(pointer.cwd, at: 8)
        try statement.bind(pointer.contentHash, at: 9)
        try statement.bind(try Self.encodeSpans(pointer.messageSpans), at: 10)
    }

    private func pointerRecord(
        _ database: OpaquePointer,
        id: ConversationSourcePointerID
    ) throws -> ConversationSourcePointerRecord? {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "read conversation pointer",
            sql: """
            SELECT sequence, provider, thread_id, turn_id, source_path,
                   start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                   processing_state, batch_id, project_id, failure_message,
                   inserted_at, updated_at
            FROM conversation_source_pointers
            WHERE provider = ? AND thread_id = ? AND turn_id = ?
            """
        )
        try statement.bind(id.provider, at: 1)
        try statement.bind(id.threadID, at: 2)
        try statement.bind(id.turnID, at: 3)
        guard try statement.step() == .row else { return nil }
        return try decodePointerRecord(statement)
    }

    private func loadPendingPointers(
        _ database: OpaquePointer,
        through highWaterSequence: Int64,
        limit: Int
    ) throws -> [ConversationSourcePointerRecord] {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "read pending conversation pointers",
            sql: """
            SELECT sequence, provider, thread_id, turn_id, source_path,
                   start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                   processing_state, batch_id, project_id, failure_message,
                   inserted_at, updated_at
            FROM conversation_source_pointers
            WHERE processing_state = 'pending' AND sequence <= ?
            ORDER BY timestamp ASC, sequence ASC
            LIMIT ?
            """
        )
        try statement.bind(highWaterSequence, at: 1)
        try statement.bind(Int64(limit), at: 2)
        return try readPointerRecords(statement)
    }

    private func loadBatch(
        _ database: OpaquePointer,
        id: String
    ) throws -> ConversationProcessingBatch? {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "read processing batch",
            sql: """
            SELECT id, high_water_sequence, status, error_message,
                   created_at, finished_at, updated_at
            FROM conversation_processing_batches
            WHERE id = ?
            """
        )
        try statement.bind(id, at: 1)
        guard try statement.step() == .row else { return nil }

        let highWaterSequence = statement.int64(at: 1)
        guard highWaterSequence > 0 else {
            throw ConversationSourceIndexError.corruptData("batch \(id) has an invalid high-water mark")
        }
        let rawStatus = try statement.requiredText(at: 2)
        guard let status = ConversationProcessingBatchStatus(rawValue: rawStatus) else {
            throw ConversationSourceIndexError.corruptData("batch \(id) has unknown status \(rawStatus)")
        }

        let pointerStatement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "read batch pointers",
            sql: """
            SELECT sequence, provider, thread_id, turn_id, source_path,
                   start_offset, end_offset, timestamp, cwd, content_hash, message_spans_json,
                   processing_state, batch_id, project_id, failure_message,
                   inserted_at, updated_at
            FROM conversation_source_pointers
            WHERE batch_id = ?
            ORDER BY timestamp ASC, sequence ASC
            """
        )
        try pointerStatement.bind(id, at: 1)
        let pointers = try readPointerRecords(pointerStatement)
        guard !pointers.isEmpty else {
            throw ConversationSourceIndexError.corruptData("batch \(id) has no pointers")
        }

        return ConversationProcessingBatch(
            id: try statement.requiredText(at: 0),
            highWaterMark: ConversationBatchHighWaterMark(pointerSequence: highWaterSequence),
            status: status,
            pointers: pointers,
            errorMessage: try statement.optionalText(at: 3),
            createdAt: try statement.date(at: 4),
            finishedAt: try statement.optionalDate(at: 5),
            updatedAt: try statement.date(at: 6)
        )
    }

    private func finishBatch(
        _ database: OpaquePointer,
        batchID: String,
        status: ConversationProcessingBatchStatus,
        errorMessage: String?,
        finishedAt: Date
    ) throws {
        guard status != .processing else {
            throw ConversationSourceIndexError.invalidInput("finishBatch requires a terminal status")
        }
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: "finish processing batch",
            sql: """
            UPDATE conversation_processing_batches
            SET status = ?, error_message = ?, finished_at = ?, updated_at = ?
            WHERE id = ? AND status = 'processing'
            """
        )
        try statement.bind(status.rawValue, at: 1)
        try statement.bind(errorMessage, at: 2)
        try statement.bind(finishedAt.timeIntervalSince1970, at: 3)
        try statement.bind(finishedAt.timeIntervalSince1970, at: 4)
        try statement.bind(batchID, at: 5)
        try statement.execute()
        guard sqlite3_changes(database) == 1 else {
            throw ConversationSourceIndexError.corruptData("batch \(batchID) changed while finishing")
        }
    }

    private func readPointerRecords(
        _ statement: ConversationSQLiteStatement
    ) throws -> [ConversationSourcePointerRecord] {
        var records: [ConversationSourcePointerRecord] = []
        while try statement.step() == .row {
            records.append(try decodePointerRecord(statement))
        }
        return records
    }

    private func decodePointerRecord(
        _ statement: ConversationSQLiteStatement
    ) throws -> ConversationSourcePointerRecord {
        let sequence = statement.int64(at: 0)
        let startOffset = statement.int64(at: 5)
        let endOffset = statement.int64(at: 6)
        guard sequence > 0, startOffset >= 0, endOffset >= startOffset else {
            throw ConversationSourceIndexError.corruptData("conversation pointer has invalid sequence or offsets")
        }

        let rawState = try statement.requiredText(at: 11)
        guard let state = ConversationPointerProcessingState(rawValue: rawState) else {
            throw ConversationSourceIndexError.corruptData("conversation pointer has unknown state \(rawState)")
        }

        return ConversationSourcePointerRecord(
            sequence: sequence,
            pointer: ConversationSourcePointer(
                provider: try statement.requiredText(at: 1),
                threadID: try statement.requiredText(at: 2),
                turnID: try statement.requiredText(at: 3),
                sourcePath: try statement.requiredText(at: 4),
                startOffset: UInt64(startOffset),
                endOffset: UInt64(endOffset),
                timestamp: try statement.date(at: 7),
                cwd: try statement.requiredText(at: 8),
                contentHash: try statement.requiredText(at: 9),
                messageSpans: try Self.decodeSpans(try statement.requiredText(at: 10))
            ),
            processingState: state,
            batchID: try statement.optionalText(at: 12),
            projectID: try statement.optionalText(at: 13),
            failureMessage: try statement.optionalText(at: 14),
            insertedAt: try statement.date(at: 15),
            updatedAt: try statement.date(at: 16)
        )
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let database else {
            throw ConversationSourceIndexError.databaseClosed(path: databaseURL.path)
        }
        return try body(database)
    }

    private func withImmediateTransaction<T>(
        _ database: OpaquePointer,
        body: () throws -> T
    ) throws -> T {
        try executeStatic(database, sql: "BEGIN IMMEDIATE", operation: "begin transaction")
        do {
            let result = try body()
            try executeStatic(database, sql: "COMMIT", operation: "commit transaction")
            return result
        } catch {
            try? executeStatic(database, sql: "ROLLBACK", operation: "rollback transaction")
            throw error
        }
    }

    private func executeStatic(
        _ database: OpaquePointer,
        sql: String,
        operation: String
    ) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        try checkSQLite(result, database: database, operation: operation)
    }

    private func scalarInt64(
        _ database: OpaquePointer,
        sql: String,
        operation: String
    ) throws -> Int64 {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: operation,
            sql: sql
        )
        guard try statement.step() == .row else {
            throw ConversationSourceIndexError.corruptData("\(operation) returned no row")
        }
        return statement.int64(at: 0)
    }

    private func scalarText(
        _ database: OpaquePointer,
        sql: String,
        operation: String
    ) throws -> String {
        let statement = try ConversationSQLiteStatement(
            database: database,
            databasePath: databaseURL.path,
            operation: operation,
            sql: sql
        )
        guard try statement.step() == .row else {
            throw ConversationSourceIndexError.corruptData("\(operation) returned no row")
        }
        return try statement.requiredText(at: 0)
    }

    private func checkSQLite(
        _ code: Int32,
        database: OpaquePointer,
        operation: String
    ) throws {
        guard code == SQLITE_OK else {
            throw ConversationSourceIndexError.sqliteFailure(
                path: databaseURL.path,
                operation: operation,
                code: code,
                message: sqliteMessage(database)
            )
        }
    }

    private static func validate(_ pointer: ConversationSourcePointer) throws {
        try validate(pointer.id)
        try validateRequiredText(pointer.sourcePath, field: "sourcePath")
        try validateOffset(pointer.startOffset, field: "startOffset")
        try validateOffset(pointer.endOffset, field: "endOffset")
        guard pointer.endOffset >= pointer.startOffset else {
            throw ConversationSourceIndexError.invalidInput("endOffset must be at or after startOffset")
        }
        try validateDate(pointer.timestamp, field: "timestamp")
        try validateText(pointer.cwd, field: "cwd", allowEmpty: true)
        try validateRequiredText(pointer.contentHash, field: "contentHash")
        for span in pointer.messageSpans {
            try validateOffset(span.startOffset, field: "messageSpan.startOffset")
            try validateOffset(span.endOffset, field: "messageSpan.endOffset")
            guard span.startOffset >= pointer.startOffset,
                  span.endOffset <= pointer.endOffset,
                  span.endOffset > span.startOffset else {
                throw ConversationSourceIndexError.invalidInput(
                    "message spans must be non-empty and contained by the turn pointer"
                )
            }
        }
    }

    private static func relevantBytes(_ pointer: ConversationSourcePointer) -> UInt64 {
        if !pointer.messageSpans.isEmpty {
            var total: UInt64 = 0
            for span in pointer.messageSpans {
                let bytes = span.endOffset - span.startOffset
                if total > maximumSemanticBundleBytes || bytes > maximumSemanticBundleBytes - total {
                    return maximumSemanticBundleBytes + 1
                }
                total += bytes
            }
            return total
        }
        return pointer.endOffset - pointer.startOffset
    }

    private static func encodeSpans(_ spans: [ConversationSourceSpan]) throws -> String {
        let data = try JSONEncoder().encode(spans)
        guard let value = String(data: data, encoding: .utf8) else {
            throw ConversationSourceIndexError.corruptData("message spans are not UTF-8")
        }
        return value
    }

    private static func decodeSpans(_ value: String) throws -> [ConversationSourceSpan] {
        guard let data = value.data(using: .utf8) else {
            throw ConversationSourceIndexError.corruptData("message spans are not UTF-8")
        }
        do {
            return try JSONDecoder().decode([ConversationSourceSpan].self, from: data)
        } catch {
            throw ConversationSourceIndexError.corruptData("message spans cannot be decoded")
        }
    }

    private static func encodeCursor(_ cursor: ConversationScanCursor) throws -> String {
        let data = try JSONEncoder().encode(cursor)
        guard let value = String(data: data, encoding: .utf8) else {
            throw ConversationSourceIndexError.corruptData("scan cursor is not UTF-8")
        }
        return value
    }

    private func decodeCursor(
        _ statement: ConversationSQLiteStatement
    ) throws -> ConversationScanCursor {
        let provider = try statement.requiredText(at: 0)
        let sourcePath = try statement.requiredText(at: 1)
        let nextOffset = statement.int64(at: 2)
        guard nextOffset >= 0 else {
            throw ConversationSourceIndexError.corruptData("scan cursor has a negative offset")
        }
        let updatedAt = try statement.date(at: 3)
        let encoded = try statement.requiredText(at: 4)
        if !encoded.isEmpty, let data = encoded.data(using: .utf8) {
            do {
                var cursor = try JSONDecoder().decode(ConversationScanCursor.self, from: data)
                cursor.provider = provider
                cursor.sourcePath = sourcePath
                cursor.nextOffset = UInt64(nextOffset)
                cursor.updatedAt = updatedAt
                return cursor
            } catch {
                throw ConversationSourceIndexError.corruptData("scan cursor metadata cannot be decoded")
            }
        }
        return ConversationScanCursor(
            provider: provider,
            sourcePath: sourcePath,
            nextOffset: UInt64(nextOffset),
            updatedAt: updatedAt
        )
    }

    private static func validate(_ cursor: ConversationScanCursor) throws {
        try validateProvider(cursor.provider)
        try validateRequiredText(cursor.sourcePath, field: "sourcePath")
        try validateOffset(cursor.nextOffset, field: "nextOffset")
        try validateDate(cursor.updatedAt, field: "cursor.updatedAt")
        try validateText(cursor.threadID, field: "threadID", allowEmpty: true)
        try validateText(cursor.cwd, field: "cwd", allowEmpty: true)
        try validateText(cursor.activeTurnID, field: "activeTurnID", allowEmpty: true)
        try validateOffset(cursor.activeTurnOffset, field: "activeTurnOffset")
        for span in cursor.messageSpans {
            try validateOffset(span.startOffset, field: "cursor.messageSpan.startOffset")
            try validateOffset(span.endOffset, field: "cursor.messageSpan.endOffset")
            guard span.endOffset > span.startOffset else {
                throw ConversationSourceIndexError.invalidInput(
                    "scan cursor message spans must be non-empty"
                )
            }
        }
        if let lastActivityAt = cursor.lastActivityAt {
            try validateDate(lastActivityAt, field: "cursor.lastActivityAt")
        }
    }

    private static func validate(_ id: ConversationSourcePointerID) throws {
        try validateProvider(id.provider)
        try validateRequiredText(id.threadID, field: "threadID")
        try validateRequiredText(id.turnID, field: "turnID")
    }

    private static func validate(
        _ mutations: [ConversationSemanticBundleMutation]
    ) throws {
        var bundleIDs = Set<String>()
        var memberIDs = Set<ConversationSourcePointerID>()
        for mutation in mutations {
            switch mutation {
            case .close(let bundleID):
                try validateRequiredText(bundleID, field: "semanticBundle.id")
                guard bundleIDs.insert(bundleID).inserted else {
                    throw ConversationSourceIndexError.invalidInput(
                        "one batch cannot mutate a semantic bundle twice"
                    )
                }
            case .upsert(let bundle):
                try validateRequiredText(bundle.id, field: "semanticBundle.id")
                try validateRequiredText(bundle.threadID, field: "semanticBundle.threadID")
                try validateRequiredText(bundle.projectID, field: "semanticBundle.projectID")
                try validateRequiredText(bundle.title, field: "semanticBundle.title")
                try validateRequiredText(bundle.summary, field: "semanticBundle.summary")
                try validateDate(bundle.updatedAt, field: "semanticBundle.updatedAt")
                guard bundleIDs.insert(bundle.id).inserted,
                      !bundle.pointerIDs.isEmpty,
                      Set(bundle.pointerIDs).count == bundle.pointerIDs.count else {
                    throw ConversationSourceIndexError.invalidInput(
                        "semantic bundles require one mutation and unique members"
                    )
                }
                for pointerID in bundle.pointerIDs {
                    try validate(pointerID)
                    guard memberIDs.insert(pointerID).inserted else {
                        throw ConversationSourceIndexError.invalidInput(
                            "one pointer cannot belong to multiple open semantic bundles"
                        )
                    }
                }
            }
        }
    }

    private static func validate(_ highWaterMark: ConversationBatchHighWaterMark) throws {
        guard highWaterMark.pointerSequence > 0 else {
            throw ConversationSourceIndexError.invalidInput("high-water sequence must be positive")
        }
    }

    private static func validateProvider(_ provider: String) throws {
        try validateRequiredText(provider, field: "provider")
    }

    private static func validateRequiredText(_ value: String, field: String) throws {
        try validateText(value, field: field, allowEmpty: false)
    }

    private static func validateText(_ value: String, field: String, allowEmpty: Bool) throws {
        if !allowEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConversationSourceIndexError.invalidInput("\(field) must not be empty")
        }
        if value.utf8.contains(0) {
            throw ConversationSourceIndexError.invalidInput("\(field) must not contain NUL bytes")
        }
    }

    private static func validateOffset(_ offset: UInt64, field: String) throws {
        guard offset <= UInt64(Int64.max) else {
            throw ConversationSourceIndexError.invalidInput("\(field) exceeds SQLite INTEGER range")
        }
    }

    private static func validateDate(_ date: Date, field: String) throws {
        guard date.timeIntervalSince1970.isFinite else {
            throw ConversationSourceIndexError.invalidInput("\(field) must be finite")
        }
    }

    private static func validateLimit(_ limit: Int) throws {
        guard limit > 0 else {
            throw ConversationSourceIndexError.invalidInput("limit must be positive")
        }
    }

    private static func validateRange(
        from: Date?,
        through: Date?,
        afterSequence: Int64?,
        limit: Int
    ) throws {
        if let from {
            try validateDate(from, field: "from")
        }
        if let through {
            try validateDate(through, field: "through")
        }
        if let from, let through, from > through {
            throw ConversationSourceIndexError.invalidInput("from must not be after through")
        }
        if let afterSequence, afterSequence < 0 {
            throw ConversationSourceIndexError.invalidInput("afterSequence must not be negative")
        }
        try validateLimit(limit)
    }
}

private enum ConversationSQLiteStep {
    case row
    case done
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        precondition(size > 0)
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

private final class ConversationSQLiteStatement {
    private let database: OpaquePointer
    private let databasePath: String
    private let operation: String
    private let statement: OpaquePointer

    init(
        database: OpaquePointer,
        databasePath: String,
        operation: String,
        sql: String
    ) throws {
        self.database = database
        self.databasePath = databasePath
        self.operation = operation

        var prepared: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &prepared, nil)
        guard result == SQLITE_OK, let prepared else {
            if let prepared {
                sqlite3_finalize(prepared)
            }
            throw ConversationSourceIndexError.sqliteFailure(
                path: databasePath,
                operation: operation,
                code: result,
                message: sqliteMessage(database)
            )
        }
        statement = prepared
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String, at index: Int32) throws {
        if value.utf8.contains(0) {
            throw ConversationSourceIndexError.invalidInput(
                "SQLite text parameter \(index) for \(operation) contains a NUL byte"
            )
        }
        let byteCount = value.lengthOfBytes(using: .utf8)
        guard byteCount <= Int(Int32.max) else {
            throw ConversationSourceIndexError.invalidInput(
                "SQLite text parameter \(index) for \(operation) is too large"
            )
        }
        let result = value.withCString { pointer in
            sqlite3_bind_text(
                statement,
                index,
                pointer,
                Int32(byteCount),
                sqliteTransientDestructor()
            )
        }
        try check(result, action: "bind text parameter \(index)")
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let value else {
            try bindNull(at: index)
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(statement, index, value), action: "bind integer parameter \(index)")
    }

    func bind(_ value: Int64?, at index: Int32) throws {
        guard let value else {
            try bindNull(at: index)
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(statement, index, value), action: "bind real parameter \(index)")
    }

    func bind(_ value: Double?, at index: Int32) throws {
        guard let value else {
            try bindNull(at: index)
            return
        }
        try bind(value, at: index)
    }

    func execute() throws {
        guard try step() == .done else {
            throw ConversationSourceIndexError.corruptData("\(operation) unexpectedly returned rows")
        }
    }

    func step() throws -> ConversationSQLiteStep {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return .row
        case SQLITE_DONE:
            return .done
        default:
            throw ConversationSourceIndexError.sqliteFailure(
                path: databasePath,
                operation: operation,
                code: result,
                message: sqliteMessage(database)
            )
        }
    }

    func reset() throws {
        let resetResult = sqlite3_reset(statement)
        try check(resetResult, action: "reset statement")
        let clearResult = sqlite3_clear_bindings(statement)
        try check(clearResult, action: "clear statement bindings")
    }

    func isNull(at index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func requiredText(at index: Int32) throws -> String {
        guard !isNull(at: index), let value = sqlite3_column_text(statement, index) else {
            throw ConversationSourceIndexError.corruptData(
                "\(operation) returned NULL for required column \(index)"
            )
        }
        return String(cString: value)
    }

    func optionalText(at index: Int32) throws -> String? {
        guard !isNull(at: index) else { return nil }
        return try requiredText(at: index)
    }

    func date(at index: Int32) throws -> Date {
        let seconds = sqlite3_column_double(statement, index)
        guard seconds.isFinite else {
            throw ConversationSourceIndexError.corruptData(
                "\(operation) returned a non-finite date at column \(index)"
            )
        }
        return Date(timeIntervalSince1970: seconds)
    }

    func optionalDate(at index: Int32) throws -> Date? {
        guard !isNull(at: index) else { return nil }
        return try date(at: index)
    }

    private func bindNull(at index: Int32) throws {
        try check(sqlite3_bind_null(statement, index), action: "bind NULL parameter \(index)")
    }

    private func check(_ code: Int32, action: String) throws {
        guard code == SQLITE_OK else {
            throw ConversationSourceIndexError.sqliteFailure(
                path: databasePath,
                operation: "\(operation): \(action)",
                code: code,
                message: sqliteMessage(database)
            )
        }
    }
}

private func sqliteMessage(_ database: OpaquePointer?) -> String {
    guard let database else { return "No SQLite handle" }
    return String(cString: sqlite3_errmsg(database))
}

private func sqliteTransientDestructor() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
