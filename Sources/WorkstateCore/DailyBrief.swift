import CryptoKit
import Darwin
import Foundation

public struct DailyBrief: Codable, Equatable, Identifiable, Sendable {
    public var id: String { dateKey }
    public var dateKey: String
    public var intervalStart: Date
    public var intervalEnd: Date
    public var generatedAt: Date
    public var sourceRevision: String
    public var projects: [DailyProjectBrief]
    public var narrative: DailyBriefNarrative?

    public init(
        dateKey: String,
        intervalStart: Date,
        intervalEnd: Date,
        generatedAt: Date = Date(),
        sourceRevision: String,
        projects: [DailyProjectBrief],
        narrative: DailyBriefNarrative? = nil
    ) {
        self.dateKey = dateKey
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.generatedAt = generatedAt
        self.sourceRevision = sourceRevision
        self.projects = projects
        self.narrative = narrative
    }

    public var isEmpty: Bool {
        projects.isEmpty
    }

    public var progressCount: Int {
        projects.reduce(0) { $0 + $1.progress.count }
    }

    public var confirmedCount: Int {
        projects.reduce(0) { $0 + $1.confirmed.count }
    }

    public var unresolvedCount: Int {
        projects.reduce(0) { $0 + $1.unresolved.count }
    }

    public var resumeCount: Int {
        projects.reduce(0) { $0 + $1.resumePoints.count }
    }

    public var rawRecordCount: Int {
        progressCount + confirmedCount + unresolvedCount + resumeCount
    }

    public var currentNarrative: DailyBriefNarrative? {
        guard narrative?.sourceRevision == sourceRevision else { return nil }
        return narrative
    }
}

public struct DailyBriefNarrative: Codable, Equatable, Sendable {
    public var sourceRevision: String
    public var generatedAt: Date
    public var overview: String
    public var projectSummaries: [DailyProjectNarrative]
    public var nextStep: String

    public init(
        sourceRevision: String,
        generatedAt: Date = Date(),
        overview: String,
        projectSummaries: [DailyProjectNarrative],
        nextStep: String
    ) {
        self.sourceRevision = sourceRevision
        self.generatedAt = generatedAt
        self.overview = overview
        self.projectSummaries = projectSummaries
        self.nextStep = nextStep
    }
}

public struct DailyProjectNarrative: Codable, Equatable, Identifiable, Sendable {
    public var id: String { projectID }
    public var projectID: String
    public var summary: String

    public init(projectID: String, summary: String) {
        self.projectID = projectID
        self.summary = summary
    }
}

public struct DailyProjectBrief: Codable, Equatable, Identifiable, Sendable {
    public var id: String { projectID }
    public var projectID: String
    public var projectName: String
    public var accent: ProjectAccent
    public var progress: [DailyBriefItem]
    public var confirmed: [DailyBriefItem]
    public var unresolved: [DailyBriefItem]
    public var resumePoints: [DailyBriefItem]

    public init(
        projectID: String,
        projectName: String,
        accent: ProjectAccent,
        progress: [DailyBriefItem] = [],
        confirmed: [DailyBriefItem] = [],
        unresolved: [DailyBriefItem] = [],
        resumePoints: [DailyBriefItem] = []
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.accent = accent
        self.progress = progress
        self.confirmed = confirmed
        self.unresolved = unresolved
        self.resumePoints = resumePoints
    }

    public var isEmpty: Bool {
        progress.isEmpty && confirmed.isEmpty && unresolved.isEmpty && resumePoints.isEmpty
    }
}

public enum DailyBriefItemKind: String, Codable, Equatable, Sendable {
    case progress
    case confirmed
    case unresolved
    case resume
}

public struct DailyBriefItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: DailyBriefItemKind
    public var title: String
    public var detail: String
    public var timestamp: Date?
    public var projectID: String
    public var taskID: String?
    public var eventID: String?
    public var sourceIDs: [String]

    public init(
        id: String,
        kind: DailyBriefItemKind,
        title: String,
        detail: String,
        timestamp: Date? = nil,
        projectID: String,
        taskID: String? = nil,
        eventID: String? = nil,
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.projectID = projectID
        self.taskID = taskID
        self.eventID = eventID
        self.sourceIDs = sourceIDs
    }
}

public struct DailyBriefBuilder: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func build(
        workspace: WorkspaceSnapshot,
        for day: Date,
        generatedAt: Date = Date(),
        includeCurrentState: Bool = true
    ) throws -> DailyBrief {
        let intervalStart = calendar.startOfDay(for: day)
        guard let intervalEnd = calendar.date(byAdding: .day, value: 1, to: intervalStart) else {
            throw WorkstateStorageError.invalidState("Could not resolve the daily brief interval")
        }
        let projects = workspace.projects.compactMap { project in
            projectBrief(
                project,
                start: intervalStart,
                end: intervalEnd,
                includeCurrentState: includeCurrentState
            )
        }
        .sorted { lhs, rhs in
            let left = latestTimestamp(in: lhs) ?? .distantPast
            let right = latestTimestamp(in: rhs) ?? .distantPast
            if left == right { return lhs.projectID < rhs.projectID }
            return left > right
        }
        let revision = sourceRevision(projects: projects)
        return DailyBrief(
            dateKey: dateKey(intervalStart),
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            generatedAt: generatedAt,
            sourceRevision: revision,
            projects: projects
        )
    }

    public func activityDays(
        in workspace: WorkspaceSnapshot,
        through referenceDate: Date = Date()
    ) throws -> [Date] {
        let referenceStart = calendar.startOfDay(for: referenceDate)
        guard let cutoff = calendar.date(byAdding: .day, value: 1, to: referenceStart) else {
            throw WorkstateStorageError.invalidState("Could not resolve the activity brief cutoff")
        }
        var days: Set<Date> = []

        func include(_ timestamp: Date) {
            guard timestamp < cutoff else { return }
            days.insert(calendar.startOfDay(for: timestamp))
        }

        for project in workspace.projects {
            project.events.forEach { include($0.timestamp) }
            project.context.revisions.forEach { include($0.timestamp) }
            project.topics.forEach { include($0.updatedAt) }
            project.tasks.forEach { include($0.updatedAt) }
        }

        return days.sorted()
    }

    private func projectBrief(
        _ project: ProjectRecord,
        start: Date,
        end: Date,
        includeCurrentState: Bool
    ) -> DailyProjectBrief? {
        let events = project.events
            .filter { contains($0.timestamp, start: start, end: end) }
            .sorted {
                if $0.timestamp == $1.timestamp { return $0.id < $1.id }
                return $0.timestamp > $1.timestamp
            }
        let revisions = project.context.revisions
            .filter { contains($0.timestamp, start: start, end: end) }
            .sorted {
                if $0.timestamp == $1.timestamp { return $0.id < $1.id }
                return $0.timestamp > $1.timestamp
            }
        let topics = project.topics
            .filter { contains($0.updatedAt, start: start, end: end) }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return $0.updatedAt > $1.updatedAt
            }
        let changedTasks = project.tasks.filter { contains($0.updatedAt, start: start, end: end) }

        guard !events.isEmpty || !revisions.isEmpty || !topics.isEmpty || !changedTasks.isEmpty else {
            return nil
        }

        var progress = events
            .filter { event in
                event.kind != .decision
            }
            .prefix(5)
            .map { event in
                DailyBriefItem(
                    id: "progress:\(project.id):\(event.id)",
                    kind: .progress,
                    title: event.title,
                    detail: event.summary,
                    timestamp: event.timestamp,
                    projectID: project.id,
                    taskID: event.taskID,
                    eventID: event.id,
                    sourceIDs: event.sourceIDs
                )
            }

        let eventTaskIDs = Set(events.compactMap(\.taskID))
        for task in changedTasks where !eventTaskIDs.contains(task.id) {
            progress.append(
                DailyBriefItem(
                    id: "progress-task:\(project.id):\(task.id)",
                    kind: .progress,
                    title: task.title,
                    detail: task.objective,
                    timestamp: task.updatedAt,
                    projectID: project.id,
                    taskID: task.id,
                    sourceIDs: task.sourceIDs
                )
            )
        }
        progress = Array(
            progress
                .sorted {
                    let left = $0.timestamp ?? .distantPast
                    let right = $1.timestamp ?? .distantPast
                    if left == right { return $0.id < $1.id }
                    return left > right
                }
                .prefix(5)
        )

        var confirmed: [DailyBriefItem] = []
        for event in events where event.kind == .decision || event.kind == .accepted {
            confirmed.append(
                DailyBriefItem(
                    id: "confirmed-event:\(project.id):\(event.id)",
                    kind: .confirmed,
                    title: event.title,
                    detail: event.summary,
                    timestamp: event.timestamp,
                    projectID: project.id,
                    taskID: event.taskID,
                    eventID: event.id,
                    sourceIDs: event.sourceIDs
                )
            )
        }
        for revision in revisions where revision.status == .confirmed {
            confirmed.append(
                DailyBriefItem(
                    id: "confirmed-revision:\(project.id):\(revision.id)",
                    kind: .confirmed,
                    title: revision.title,
                    detail: revision.summary,
                    timestamp: revision.timestamp,
                    projectID: project.id,
                    sourceIDs: revision.sourceIDs
                )
            )
        }
        for topic in topics where topic.status == .converted || topic.confirmedAt != nil {
            confirmed.append(
                DailyBriefItem(
                    id: "confirmed-topic:\(project.id):\(topic.id)",
                    kind: .confirmed,
                    title: topic.title,
                    detail: topic.currentUnderstanding,
                    timestamp: topic.confirmedAt ?? topic.updatedAt,
                    projectID: project.id,
                    sourceIDs: topic.sourceIDs
                )
            )
        }
        confirmed = Array(
            Dictionary(confirmed.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
                .values
                .sorted {
                    let left = $0.timestamp ?? .distantPast
                    let right = $1.timestamp ?? .distantPast
                    if left == right { return $0.id < $1.id }
                    return left > right
                }
                .prefix(4)
        )

        let unresolved: [DailyBriefItem] = includeCurrentState
            ? project.context.openIssues.prefix(4).enumerated().map { index, issue in
                DailyBriefItem(
                    id: "unresolved:\(project.id):\(index):\(stableComponent(issue))",
                    kind: .unresolved,
                    title: issue,
                    detail: "仍需继续确认或处理",
                    projectID: project.id,
                    sourceIDs: project.sourceIDs
                )
            }
            : []

        let resumePoints: [DailyBriefItem] = includeCurrentState
            ? project.tasks
                .filter { task in
                    task.startedAt < end
                        && task.status != .abandoned
                        && (task.completedAt.map { $0 >= end } ?? true)
                }
                .sorted {
                    if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                    return $0.updatedAt > $1.updatedAt
                }
                .prefix(3)
                .map { task in
                    DailyBriefItem(
                        id: "resume:\(project.id):\(task.id)",
                        kind: .resume,
                        title: task.title,
                        detail: task.objective,
                        timestamp: task.updatedAt,
                        projectID: project.id,
                        taskID: task.id,
                        sourceIDs: task.sourceIDs
                    )
                }
            : []

        let brief = DailyProjectBrief(
            projectID: project.id,
            projectName: project.name,
            accent: project.accent,
            progress: Array(progress),
            confirmed: confirmed,
            unresolved: Array(unresolved),
            resumePoints: Array(resumePoints)
        )
        return brief.isEmpty ? nil : brief
    }

    private func contains(_ date: Date, start: Date, end: Date) -> Bool {
        date >= start && date < end
    }

    private func latestTimestamp(in project: DailyProjectBrief) -> Date? {
        (project.progress + project.confirmed + project.resumePoints)
            .compactMap(\.timestamp)
            .max()
    }

    private func sourceRevision(projects: [DailyProjectBrief]) -> String {
        let components = projects.flatMap { project in
            (project.progress + project.confirmed + project.unresolved + project.resumePoints).map { item in
                [
                    project.projectID,
                    item.id,
                    item.title,
                    item.detail,
                    item.timestamp?.timeIntervalSince1970.description ?? ""
                ].joined(separator: "|")
            }
        }
        let digest = SHA256.hash(data: Data(components.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func dateKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func stableComponent(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

public struct DailyBriefRepository: Sendable {
    public let root: URL
    public let directory: URL
    public let readStateURL: URL
    public let lockURL: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        self.root = root
        directory = root.appendingPathComponent("daily-briefs", isDirectory: true)
        readStateURL = root.appendingPathComponent("daily-brief-read-state.json")
        lockURL = root.appendingPathComponent("daily-brief.lock")
    }

    public func brief(
        for day: Date,
        workspace: WorkspaceSnapshot,
        calendar: Calendar = .current,
        includeCurrentState: Bool = true
    ) throws -> DailyBrief {
        try withLock(exclusive: true) {
            let candidate = try DailyBriefBuilder(calendar: calendar).build(
                workspace: workspace,
                for: day,
                includeCurrentState: includeCurrentState
            )
            if let existing = try load(dateKey: candidate.dateKey),
               existing.currentNarrative != nil {
                return existing
            }
            if candidate.isEmpty {
                let url = directory.appendingPathComponent("\(candidate.dateKey).json")
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return candidate
            }
            if let existing = try load(dateKey: candidate.dateKey),
               existing.sourceRevision == candidate.sourceRevision {
                return existing
            }
            try save(candidate)
            guard let stored = try load(dateKey: candidate.dateKey) else {
                throw WorkstateStorageError.invalidState("Daily brief was not persisted")
            }
            return stored
        }
    }

    public func synchronize(
        workspace: WorkspaceSnapshot,
        through referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [DailyBrief] {
        try withLock(exclusive: true) {
            let builder = DailyBriefBuilder(calendar: calendar)
            let activityDays = try builder.activityDays(in: workspace, through: referenceDate)
            let latestActivityDay = activityDays.last
            let candidates = try activityDays
                .map {
                    try builder.build(
                        workspace: workspace,
                        for: $0,
                        includeCurrentState: $0 == latestActivityDay
                    )
                }
                .filter { !$0.isEmpty }
            let activeDateKeys = Set(candidates.map(\.dateKey))

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for url in try briefURLs() where !activeDateKeys.contains(url.deletingPathExtension().lastPathComponent) {
                let existing = try load(dateKey: url.deletingPathExtension().lastPathComponent)
                if existing?.currentNarrative == nil {
                    try FileManager.default.removeItem(at: url)
                }
            }

            return try candidates.map { candidate in
                if let existing = try load(dateKey: candidate.dateKey), !existing.isEmpty {
                    if existing.currentNarrative != nil
                        || existing.sourceRevision == candidate.sourceRevision {
                        return existing
                    }
                }
                try save(candidate)
                guard let stored = try load(dateKey: candidate.dateKey) else {
                    throw WorkstateStorageError.invalidState("Activity brief was not persisted")
                }
                return stored
            }
        }
    }

    public func applyNarrative(
        _ narrative: DailyBriefNarrative,
        to dateKey: String
    ) throws -> DailyBrief {
        try withLock(exclusive: true) {
            guard var brief = try load(dateKey: dateKey) else {
                throw WorkstateStorageError.invalidState("Activity brief not found: \(dateKey)")
            }
            guard narrative.sourceRevision == brief.sourceRevision else {
                throw WorkstateStorageError.invalidState("Activity brief changed while its narrative was being generated")
            }
            let expectedProjectIDs = Set(brief.projects.map(\.projectID))
            let actualProjectIDs = Set(narrative.projectSummaries.map(\.projectID))
            guard actualProjectIDs.count == narrative.projectSummaries.count,
                  actualProjectIDs == expectedProjectIDs else {
                throw WorkstateStorageError.invalidState("Narrative project summaries do not match the activity brief")
            }
            guard !narrative.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  narrative.projectSummaries.allSatisfy({
                      !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }) else {
                throw WorkstateStorageError.invalidState("Narrative contains empty required text")
            }
            brief.narrative = narrative
            try save(brief)
            guard let stored = try load(dateKey: dateKey) else {
                throw WorkstateStorageError.invalidState("Narrative activity brief was not persisted")
            }
            return stored
        }
    }

    public func load(dateKey: String) throws -> DailyBrief? {
        let url = directory.appendingPathComponent("\(dateKey).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try WorkstateCoding.makeDecoder().decode(DailyBrief.self, from: Data(contentsOf: url))
    }

    public func availableDateKeys() throws -> [String] {
        try briefURLs()
            .compactMap { url in
                let brief = try WorkstateCoding.makeDecoder().decode(
                    DailyBrief.self,
                    from: Data(contentsOf: url)
                )
                return brief.isEmpty ? nil : brief.dateKey
            }
            .sorted()
    }

    public func save(_ brief: DailyBrief) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(brief.dateKey).json")
        try WorkstateCoding.makeEncoder().encode(brief).write(to: url, options: .atomic)
    }

    public func isUnread(_ brief: DailyBrief) throws -> Bool {
        let state = try loadReadState()
        return state.viewedRevisions[brief.dateKey] != brief.sourceRevision
    }

    public func markViewed(_ brief: DailyBrief) throws {
        try withLock(exclusive: true) {
            var state = try loadReadState()
            state.viewedRevisions[brief.dateKey] = brief.sourceRevision
            state.viewedAt = Date()
            try WorkstateCoding.makeEncoder().encode(state).write(to: readStateURL, options: .atomic)
        }
    }

    private func briefURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    private func loadReadState() throws -> DailyBriefReadState {
        guard FileManager.default.fileExists(atPath: readStateURL.path) else {
            return DailyBriefReadState()
        }
        return try WorkstateCoding.makeDecoder().decode(
            DailyBriefReadState.self,
            from: Data(contentsOf: readStateURL)
        )
    }

    private func withLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw WorkstateStorageError.cannotCreateLock(lockURL.path)
        }
        defer { close(descriptor) }
        let operation = exclusive ? LOCK_EX : LOCK_SH
        guard flock(descriptor, operation) == 0 else {
            throw WorkstateStorageError.cannotLock(lockURL.path)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

private struct DailyBriefReadState: Codable {
    var viewedRevisions: [String: String] = [:]
    var viewedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case viewedRevisions
        case viewedAt
    }

    init(viewedRevisions: [String: String] = [:], viewedAt: Date? = nil) {
        self.viewedRevisions = viewedRevisions
        self.viewedAt = viewedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewedRevisions = try container.decodeIfPresent([String: String].self, forKey: .viewedRevisions) ?? [:]
        viewedAt = try container.decodeIfPresent(Date.self, forKey: .viewedAt)
    }
}
