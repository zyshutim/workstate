import Foundation

public enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active
    case waiting
    case parked
    case completed
    case archived
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case active
    case waiting
    case parked
    case completed
    case abandoned
}

public enum ProjectAccent: String, Codable, CaseIterable, Sendable {
    case blue
    case green
    case red
    case amber
    case violet
    case cyan
}

public enum RelationKind: String, Codable, CaseIterable, Sendable {
    case workTransferred
    case sharesContext
    case dependsOn
    case spawnedFrom
}

public enum EvidenceStatus: String, Codable, CaseIterable, Sendable {
    case observed
    case inferred
    case confirmed
    case superseded
    case prohibited
}

public enum LoopStage: String, Codable, CaseIterable, Sendable {
    case intake
    case reconstruction
    case audit
    case modeling
    case confirmation
    case implementation
    case verification
    case acceptance
    case integration
    case completed
}

public enum EventKind: String, Codable, CaseIterable, Sendable {
    case projectStarted
    case taskStarted
    case contextUpdate
    case investigation
    case decision
    case implementation
    case verification
    case accepted
    case integrated
    case operational
    case interruption
    case resumed
    case handedOff
    case completed
}

public enum DeliveryStage: String, Codable, CaseIterable, Sendable {
    case unchanged
    case changed
    case checked
    case rendered
    case userAccepted
    case integrated
    case published
}

public enum ReviewKind: String, Codable, CaseIterable, Sendable {
    case ambiguousRouting
    case candidateProject
    case projectUpdate
    case projectStructure
    case understandingConflict
    case decisionConflict
}

public struct ReviewEventProposal: Codable, Equatable, Sendable {
    public var eventID: String
    public var timestamp: Date
    public var taskID: String?
    public var kind: EventKind
    public var stage: LoopStage
    public var delivery: DeliveryStage
    public var facts: [String]
    public var openIssues: [String]
    public var operations: OperationalContext

    public init(
        eventID: String,
        timestamp: Date,
        taskID: String? = nil,
        kind: EventKind,
        stage: LoopStage,
        delivery: DeliveryStage,
        facts: [String] = [],
        openIssues: [String] = [],
        operations: OperationalContext = .init()
    ) {
        self.eventID = eventID
        self.timestamp = timestamp
        self.taskID = taskID
        self.kind = kind
        self.stage = stage
        self.delivery = delivery
        self.facts = facts
        self.openIssues = openIssues
        self.operations = operations
    }
}

public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case deferred
    case confirmed
    case rejected
}

public enum DaemonActivity: String, Codable, CaseIterable, Sendable {
    case stopped
    case idle
    case scanning
    case analyzing
    case paused
    case failed
}

public enum ProjectTopicStatus: String, Codable, CaseIterable, Sendable {
    case captured
    case discussing
    case converted
    case closed
}

public enum ProjectTopicKind: String, Codable, CaseIterable, Sendable {
    case product
    case frontend
    case backend
}

public enum ProjectTopicDisposition: String, Codable, CaseIterable, Sendable {
    case futureDecision
    case awaitingVerification
}

public enum ProjectTopicResolution: String, Codable, CaseIterable, Sendable {
    case completed
    case cancelled
}

public enum ProjectTopicPromotionKind: String, Codable, CaseIterable, Sendable {
    case decision
    case task
}

public enum ProjectTopicNoteKind: String, Codable, CaseIterable, Sendable {
    case origin
    case ownerAnalysis
    case userCorrection
    case confirmation
    case statusChange
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var updatedAt: Date
    public var projects: [ProjectRecord]
    public var relations: [ProjectRelation]
    public var sources: [SourceReference]
    public var reviewInbox: [ReviewItem]

    public init(
        schemaVersion: Int = 4,
        updatedAt: Date = Date(),
        projects: [ProjectRecord] = [],
        relations: [ProjectRelation] = [],
        sources: [SourceReference] = [],
        reviewInbox: [ReviewItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.projects = projects
        self.relations = relations
        self.sources = sources
        self.reviewInbox = reviewInbox
    }
}

public struct ProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var status: ProjectStatus
    public var accent: ProjectAccent
    public var createdAt: Date
    public var updatedAt: Date
    public var lastActivityAt: Date
    public var graphPosition: GraphPosition
    public var context: ProjectContext
    public var focusedTaskID: String?
    public var tasks: [TaskRecord]
    public var events: [ProjectEvent]
    public var topics: [ProjectTopic]
    public var sourceIDs: [String]

    public init(
        id: String,
        name: String,
        summary: String,
        status: ProjectStatus = .active,
        accent: ProjectAccent = .blue,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastActivityAt: Date = Date(),
        graphPosition: GraphPosition = .init(x: 0, y: 0),
        context: ProjectContext = .init(),
        focusedTaskID: String? = nil,
        tasks: [TaskRecord] = [],
        events: [ProjectEvent] = [],
        topics: [ProjectTopic] = [],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.status = status
        self.accent = accent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.graphPosition = graphPosition
        self.context = context
        self.focusedTaskID = focusedTaskID
        self.tasks = tasks
        self.events = events
        self.topics = topics
        self.sourceIDs = sourceIDs
    }
}

public struct ProjectTopicNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Date
    public var kind: ProjectTopicNoteKind
    public var title: String
    public var detail: String
    public var ownerMessageIDs: [String]
    public var sourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        timestamp: Date = Date(),
        kind: ProjectTopicNoteKind,
        title: String,
        detail: String,
        ownerMessageIDs: [String] = [],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.detail = detail
        self.ownerMessageIDs = ownerMessageIDs
        self.sourceIDs = sourceIDs
    }
}

public struct ProjectTopic: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var status: ProjectTopicStatus
    public var kind: ProjectTopicKind
    public var disposition: ProjectTopicDisposition?
    public var resolution: ProjectTopicResolution?
    public var currentUnderstanding: String
    public var proposedDirection: String
    public var deferredReason: String
    public var revisitTrigger: String
    public var openQuestions: [String]
    public var notes: [ProjectTopicNote]
    public var sourceIDs: [String]
    public var derivedTaskIDs: [String]
    public var promotedDecisionID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var confirmedAt: Date?

    public init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        summary: String,
        status: ProjectTopicStatus = .captured,
        kind: ProjectTopicKind = .product,
        disposition: ProjectTopicDisposition? = .futureDecision,
        resolution: ProjectTopicResolution? = nil,
        currentUnderstanding: String,
        proposedDirection: String = "",
        deferredReason: String = "",
        revisitTrigger: String = "",
        openQuestions: [String] = [],
        notes: [ProjectTopicNote] = [],
        sourceIDs: [String] = [],
        derivedTaskIDs: [String] = [],
        promotedDecisionID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        confirmedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.kind = kind
        self.disposition = disposition
        self.resolution = resolution
        self.currentUnderstanding = currentUnderstanding
        self.proposedDirection = proposedDirection
        self.deferredReason = deferredReason
        self.revisitTrigger = revisitTrigger
        self.openQuestions = openQuestions
        self.notes = notes
        self.sourceIDs = sourceIDs
        self.derivedTaskIDs = derivedTaskIDs
        self.promotedDecisionID = promotedDecisionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.confirmedAt = confirmedAt
    }
}

public struct GraphPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ProjectRelation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var fromProjectID: String
    public var toProjectID: String
    public var kind: RelationKind
    public var label: String
    public var status: EvidenceStatus
    public var createdAt: Date
    public var sourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        fromProjectID: String,
        toProjectID: String,
        kind: RelationKind,
        label: String,
        status: EvidenceStatus = .confirmed,
        createdAt: Date = Date(),
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.fromProjectID = fromProjectID
        self.toProjectID = toProjectID
        self.kind = kind
        self.label = label
        self.status = status
        self.createdAt = createdAt
        self.sourceIDs = sourceIDs
    }
}

public struct ProjectContext: Codable, Equatable, Sendable {
    public var currentSummary: String
    public var purpose: String
    public var inScope: [String]
    public var outOfScope: [String]
    public var understanding: [ContextStatement]
    public var revisions: [ContextRevision]
    public var objectModel: [String]
    public var acceptedDecisions: [DecisionRecord]
    public var forbiddenDirections: [String]
    public var openIssues: [String]

    public init(
        currentSummary: String = "",
        purpose: String = "",
        inScope: [String] = [],
        outOfScope: [String] = [],
        understanding: [ContextStatement] = [],
        revisions: [ContextRevision] = [],
        objectModel: [String] = [],
        acceptedDecisions: [DecisionRecord] = [],
        forbiddenDirections: [String] = [],
        openIssues: [String] = []
    ) {
        self.currentSummary = currentSummary
        self.purpose = purpose
        self.inScope = inScope
        self.outOfScope = outOfScope
        self.understanding = understanding
        self.revisions = revisions
        self.objectModel = objectModel
        self.acceptedDecisions = acceptedDecisions
        self.forbiddenDirections = forbiddenDirections
        self.openIssues = openIssues
    }
}

public struct ContextStatement: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var status: EvidenceStatus
    public var updatedAt: Date
    public var sourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        text: String,
        status: EvidenceStatus,
        updatedAt: Date = Date(),
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.text = text
        self.status = status
        self.updatedAt = updatedAt
        self.sourceIDs = sourceIDs
    }
}

public struct ContextRevision: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Date
    public var title: String
    public var summary: String
    public var status: EvidenceStatus
    public var changes: [String]
    public var sourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        timestamp: Date = Date(),
        title: String,
        summary: String,
        status: EvidenceStatus,
        changes: [String] = [],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.summary = summary
        self.status = status
        self.changes = changes
        self.sourceIDs = sourceIDs
    }
}

public struct TaskRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var objective: String
    public var status: TaskStatus
    public var accent: ProjectAccent
    public var currentStage: LoopStage
    public var startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var branchedFromEventID: String
    public var mergedByEventID: String?
    public var tags: [String]
    public var sourceIDs: [String]

    public init(
        id: String,
        title: String,
        objective: String,
        status: TaskStatus = .active,
        accent: ProjectAccent = .blue,
        currentStage: LoopStage = .intake,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        branchedFromEventID: String,
        mergedByEventID: String? = nil,
        tags: [String] = [],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.objective = objective
        self.status = status
        self.accent = accent
        self.currentStage = currentStage
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.branchedFromEventID = branchedFromEventID
        self.mergedByEventID = mergedByEventID
        self.tags = tags
        self.sourceIDs = sourceIDs
    }
}

public struct ProjectEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var taskID: String?
    public var timestamp: Date
    public var title: String
    public var summary: String
    public var kind: EventKind
    public var loopStage: LoopStage
    public var parentEventIDs: [String]
    public var facts: [String]
    public var decisions: [DecisionRecord]
    public var operations: OperationalContext
    public var delivery: DeliverySnapshot
    public var tags: [String]
    public var sourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        taskID: String? = nil,
        timestamp: Date = Date(),
        title: String,
        summary: String,
        kind: EventKind,
        loopStage: LoopStage,
        parentEventIDs: [String] = [],
        facts: [String] = [],
        decisions: [DecisionRecord] = [],
        operations: OperationalContext = .init(),
        delivery: DeliverySnapshot = .init(),
        tags: [String] = [],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.taskID = taskID
        self.timestamp = timestamp
        self.title = title
        self.summary = summary
        self.kind = kind
        self.loopStage = loopStage
        self.parentEventIDs = parentEventIDs
        self.facts = facts
        self.decisions = decisions
        self.operations = operations
        self.delivery = delivery
        self.tags = tags
        self.sourceIDs = sourceIDs
    }
}

public struct DecisionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var status: EvidenceStatus
    public var rationale: String
    public var sourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        text: String,
        status: EvidenceStatus,
        rationale: String = "",
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.text = text
        self.status = status
        self.rationale = rationale
        self.sourceIDs = sourceIDs
    }
}

public struct OperationalContext: Codable, Equatable, Sendable {
    public var cwd: String
    public var repository: String
    public var branch: String
    public var commit: String
    public var files: [String]
    public var runtime: [String]

    public init(
        cwd: String = "",
        repository: String = "",
        branch: String = "",
        commit: String = "",
        files: [String] = [],
        runtime: [String] = []
    ) {
        self.cwd = cwd
        self.repository = repository
        self.branch = branch
        self.commit = commit
        self.files = files
        self.runtime = runtime
    }
}

public struct DeliverySnapshot: Codable, Equatable, Sendable {
    public var stage: DeliveryStage
    public var checks: [String]
    public var verifiedAt: Date?

    public init(
        stage: DeliveryStage = .unchanged,
        checks: [String] = [],
        verifiedAt: Date? = nil
    ) {
        self.stage = stage
        self.checks = checks
        self.verifiedAt = verifiedAt
    }
}

public struct SourceReference: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: String
    public var label: String
    public var locator: String
    public var threadID: String
    public var turnIDs: [String]
    public var excerpt: [ConversationMessage]
    public var contentHash: String

    public init(
        id: String = UUID().uuidString.lowercased(),
        kind: String,
        label: String,
        locator: String,
        threadID: String = "",
        turnIDs: [String] = [],
        excerpt: [ConversationMessage] = [],
        contentHash: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.locator = locator
        self.threadID = threadID
        self.turnIDs = turnIDs
        self.excerpt = excerpt
        self.contentHash = contentHash
    }
}

public struct ConversationMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var role: String
    public var text: String
    public var timestamp: Date?

    public init(
        id: String = UUID().uuidString.lowercased(),
        role: String,
        text: String,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct ReviewItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: ReviewKind
    public var status: ReviewStatus
    public var projectID: String?
    public var taskID: String?
    public var title: String
    public var summary: String
    public var reason: String
    public var previousValue: String
    public var proposedValue: String
    public var proposedChanges: [String]
    public var proposedEvent: ReviewEventProposal?
    public var sourceIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        kind: ReviewKind,
        status: ReviewStatus = .pending,
        projectID: String? = nil,
        taskID: String? = nil,
        title: String,
        summary: String,
        reason: String,
        previousValue: String = "",
        proposedValue: String = "",
        proposedChanges: [String] = [],
        proposedEvent: ReviewEventProposal? = nil,
        sourceIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.projectID = projectID
        self.taskID = taskID
        self.title = title
        self.summary = summary
        self.reason = reason
        self.previousValue = previousValue
        self.proposedValue = proposedValue
        self.proposedChanges = proposedChanges
        self.proposedEvent = proposedEvent
        self.sourceIDs = sourceIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DaemonSnapshot: Codable, Equatable, Sendable {
    public var activity: DaemonActivity
    public var lastScanAt: Date?
    public var lastAnalysisAt: Date?
    public var pendingEvidenceCount: Int
    public var detail: String
    public var dailyInputTokens: Int?
    public var dailyInputTokenLimit: Int?

    public init(
        activity: DaemonActivity = .stopped,
        lastScanAt: Date? = nil,
        lastAnalysisAt: Date? = nil,
        pendingEvidenceCount: Int = 0,
        detail: String = "",
        dailyInputTokens: Int? = nil,
        dailyInputTokenLimit: Int? = nil
    ) {
        self.activity = activity
        self.lastScanAt = lastScanAt
        self.lastAnalysisAt = lastAnalysisAt
        self.pendingEvidenceCount = pendingEvidenceCount
        self.detail = detail
        self.dailyInputTokens = dailyInputTokens
        self.dailyInputTokenLimit = dailyInputTokenLimit
    }
}

public struct WorkspaceMutation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Date
    public var kind: String
    public var summary: String
    public var projectID: String?
    public var taskID: String?
    public var eventID: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        timestamp: Date = Date(),
        kind: String,
        summary: String,
        projectID: String? = nil,
        taskID: String? = nil,
        eventID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.summary = summary
        self.projectID = projectID
        self.taskID = taskID
        self.eventID = eventID
    }
}

public struct CompactProjectContext: Codable, Equatable, Sendable {
    public var project: ProjectRecord
    public var relations: [ProjectRelation]
    public var activeTasks: [TaskRecord]
    public var recentEvents: [ProjectEvent]
    public var recentRevisions: [ContextRevision]
}

public struct TaskContext: Codable, Equatable, Sendable {
    public var projectID: String
    public var projectName: String
    public var task: TaskRecord
    public var events: [ProjectEvent]
    public var sources: [SourceReference]
}

public enum WorkstateCoding {
    public static func makeEncoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let fallback = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? precise.parse(value) { return date }
            if let date = try? fallback.parse(value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}

public extension WorkspaceSnapshot {
    func project(id: String) -> ProjectRecord? {
        projects.first { $0.id == id }
    }

    func source(id: String) -> SourceReference? {
        sources.first { $0.id == id }
    }

    var pendingReviews: [ReviewItem] {
        reviewInbox
            .filter { $0.status == .pending || $0.status == .deferred }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

public extension ProjectRecord {
    var latestEvent: ProjectEvent? {
        events.max { $0.timestamp < $1.timestamp }
    }

    var activeTasks: [TaskRecord] {
        tasks.filter { $0.status == .active }
    }

    func task(id: String) -> TaskRecord? {
        tasks.first { $0.id == id }
    }

    func event(id: String) -> ProjectEvent? {
        events.first { $0.id == id }
    }

    func topic(id: String) -> ProjectTopic? {
        topics.first { $0.id == id }
    }

    func events(for taskID: String?) -> [ProjectEvent] {
        events
            .filter { $0.taskID == taskID }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
