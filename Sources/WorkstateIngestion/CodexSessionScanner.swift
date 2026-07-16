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

    public init(
        threadID: String,
        turnID: String,
        sourcePath: String,
        startOffset: UInt64,
        endOffset: UInt64,
        cwd: String,
        userText: String,
        assistantText: String,
        timestamp: Date
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
    }
}

public struct IngestionSnapshot: Codable, Equatable, Sendable {
    public var initialized: Bool
    public var cursors: [String: SessionCursor]
    public var pendingSegmentIDs: [String]
    public var excludedThreadIDs: [String]
    public var lastScanAt: Date?

    public init(
        initialized: Bool = false,
        cursors: [String: SessionCursor] = [:],
        pendingSegmentIDs: [String] = [],
        excludedThreadIDs: [String] = [],
        lastScanAt: Date? = nil
    ) {
        self.initialized = initialized
        self.cursors = cursors
        self.pendingSegmentIDs = pendingSegmentIDs
        self.excludedThreadIDs = excludedThreadIDs
        self.lastScanAt = lastScanAt
    }
}

public struct SessionCursor: Codable, Equatable, Sendable {
    public var offset: UInt64
    public var threadID: String
    public var cwd: String
    public var activeTurnID: String
    public var activeTurnOffset: UInt64
    public var userText: String

    public init(
        offset: UInt64 = 0,
        threadID: String = "",
        cwd: String = "",
        activeTurnID: String = "",
        activeTurnOffset: UInt64 = 0,
        userText: String = ""
    ) {
        self.offset = offset
        self.threadID = threadID
        self.cwd = cwd
        self.activeTurnID = activeTurnID
        self.activeTurnOffset = activeTurnOffset
        self.userText = userText
    }
}

public struct CodexSessionScanner: Sendable {
    public let sessionsRoot: URL
    public let runtimeRoot: URL

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root
    ) {
        self.sessionsRoot = sessionsRoot
        self.runtimeRoot = runtimeRoot
    }

    public var stateURL: URL {
        runtimeRoot.appendingPathComponent("ingestion-state.json")
    }

    public var evidenceURL: URL {
        runtimeRoot.appendingPathComponent("evidence.jsonl")
    }

    public func scan() throws -> [SessionSegment] {
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        var state = try loadState()
        let files = try sessionFiles()
        var segments: [SessionSegment] = []

        if !state.initialized {
            for file in files {
                state.cursors[file.path] = try primeCursor(for: file)
            }
            state.initialized = true
            state.lastScanAt = Date()
            try saveState(state)
            return []
        }

        for file in files {
            var cursor = state.cursors[file.path] ?? SessionCursor()
            let fileSize = try size(of: file)
            if fileSize < cursor.offset {
                cursor = SessionCursor()
            }
            guard fileSize > cursor.offset else {
                state.cursors[file.path] = cursor
                continue
            }

            if cursor.threadID.isEmpty {
                cursor.threadID = try threadID(for: file)
            }
            if state.excludedThreadIDs.contains(cursor.threadID) {
                cursor.offset = fileSize
                state.cursors[file.path] = cursor
                continue
            }

            let result = try readAppended(file: file, cursor: cursor)
            cursor = result.cursor
            state.cursors[file.path] = cursor
            segments.append(contentsOf: result.segments)
        }

        if !segments.isEmpty {
            try appendEvidence(segments)
            let existing = Set(state.pendingSegmentIDs)
            state.pendingSegmentIDs.append(contentsOf: segments.map(\.id).filter { !existing.contains($0) })
        }
        state.lastScanAt = Date()
        try saveState(state)
        return try pendingSegments(ids: state.pendingSegmentIDs)
    }

    public func loadState() throws -> IngestionSnapshot {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return IngestionSnapshot()
        }
        return try WorkstateCoding.makeDecoder().decode(
            IngestionSnapshot.self,
            from: Data(contentsOf: stateURL)
        )
    }

    public func markProcessed(segmentIDs: [String]) throws {
        guard !segmentIDs.isEmpty else { return }
        var state = try loadState()
        let processed = Set(segmentIDs)
        state.pendingSegmentIDs.removeAll { processed.contains($0) }
        try saveState(state)
    }

    public func excludeThread(_ threadID: String) throws {
        guard !threadID.isEmpty else { return }
        var state = try loadState()
        if !state.excludedThreadIDs.contains(threadID) {
            state.excludedThreadIDs.append(threadID)
            try saveState(state)
        }
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
        var cursor = SessionCursor(offset: fileSize)

        if let firstLine = try readFirstLine(file),
           let object = parseObject(firstLine),
           object["type"] as? String == "session_meta",
           let payload = object["payload"] as? [String: Any] {
            cursor.threadID = payload["id"] as? String ?? payload["session_id"] as? String ?? ""
            cursor.cwd = payload["cwd"] as? String ?? ""
        }

        let tailSize = min(fileSize, 8 * 1024 * 1024)
        guard tailSize > 0 else { return cursor }
        let tailStart = fileSize - tailSize
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: tailStart)
        let data = try handle.readToEnd() ?? Data()
        let lines = completeLines(in: data, dropsFirstPartialLine: tailStart > 0)
        var lineOffset = tailStart
        for line in lines {
            _ = apply(line: line.data, lineOffset: lineOffset, cursor: &cursor, sourcePath: file.path)
            lineOffset += UInt64(line.length)
        }
        cursor.offset = fileSize
        return cursor
    }

    private func readAppended(
        file: URL,
        cursor: SessionCursor
    ) throws -> (cursor: SessionCursor, segments: [SessionSegment]) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: cursor.offset)
        let data = try handle.readToEnd() ?? Data()
        var updated = cursor
        var segments: [SessionSegment] = []
        var lineOffset = cursor.offset

        for line in completeLines(in: data, dropsFirstPartialLine: false) {
            if let segment = apply(
                line: line.data,
                lineOffset: lineOffset,
                cursor: &updated,
                sourcePath: file.path
            ) {
                segments.append(segment)
            }
            lineOffset += UInt64(line.length)
        }
        updated.offset = cursor.offset + UInt64(data.count)
        return (updated, segments)
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

        if type == "session_meta" {
            cursor.threadID = payload["id"] as? String ?? payload["session_id"] as? String ?? cursor.threadID
            cursor.cwd = payload["cwd"] as? String ?? cursor.cwd
            return nil
        }
        if type == "turn_context" {
            cursor.cwd = payload["cwd"] as? String ?? cursor.cwd
            cursor.activeTurnID = payload["turn_id"] as? String ?? cursor.activeTurnID
            return nil
        }
        guard type == "event_msg", let eventType = payload["type"] as? String else { return nil }

        switch eventType {
        case "task_started":
            cursor.activeTurnID = payload["turn_id"] as? String ?? ""
            cursor.activeTurnOffset = lineOffset
            cursor.userText = ""
        case "user_message":
            cursor.userText = (payload["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            let timestamp = parseTimestamp(object["timestamp"] as? String) ?? Date()
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
        try handle.seekToEnd()
        for segment in segments {
            var data = try WorkstateCoding.makeEncoder(pretty: false).encode(segment)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
    }

    private func pendingSegments(ids: [String]) throws -> [SessionSegment] {
        guard !ids.isEmpty, FileManager.default.fileExists(atPath: evidenceURL.path) else { return [] }
        let pending = Set(ids)
        let data = try Data(contentsOf: evidenceURL)
        return data.split(separator: 0x0A).compactMap { line in
            guard let segment = try? WorkstateCoding.makeDecoder().decode(SessionSegment.self, from: Data(line)),
                  pending.contains(segment.id) else { return nil }
            return segment
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private func saveState(_ state: IngestionSnapshot) throws {
        let data = try WorkstateCoding.makeEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    private func readFirstLine(_ file: URL) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
        guard let newline = data.firstIndex(of: 0x0A) else { return data.isEmpty ? nil : data }
        return data[..<newline]
    }

    private func threadID(for file: URL) throws -> String {
        guard let firstLine = try readFirstLine(file),
              let object = parseObject(firstLine),
              let payload = object["payload"] as? [String: Any] else {
            return ""
        }
        return payload["id"] as? String ?? payload["session_id"] as? String ?? ""
    }

    private func completeLines(
        in data: Data,
        dropsFirstPartialLine: Bool
    ) -> [(data: Data, length: Int)] {
        var output: [(Data, Int)] = []
        var start = data.startIndex
        var shouldDrop = dropsFirstPartialLine
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let length = data.distance(from: start, to: newline) + 1
            if shouldDrop {
                shouldDrop = false
            } else {
                output.append((Data(data[start..<newline]), length))
            }
            start = data.index(after: newline)
            if start == data.endIndex { break }
        }
        return output
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
