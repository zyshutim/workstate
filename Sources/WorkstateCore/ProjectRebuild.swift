import Foundation

public struct ProjectRebuildProposal: Codable, Equatable, Sendable {
    public var projectId: String
    public var status: String
    public var currentSummary: String
    public var purpose: String
    public var inScope: [String]
    public var outOfScope: [String]
    public var objectModel: [RebuildStatement]
    public var understanding: [RebuildUnderstanding]
    public var acceptedDecisions: [RebuildDecision]
    public var forbiddenDirections: [RebuildStatement]
    public var topics: [RebuildTopic]
    public var worklines: [RebuildWorkline]
    public var deltas: [RebuildDelta]

    public init(
        projectId: String,
        status: String,
        currentSummary: String,
        purpose: String,
        inScope: [String],
        outOfScope: [String],
        objectModel: [RebuildStatement],
        understanding: [RebuildUnderstanding],
        acceptedDecisions: [RebuildDecision],
        forbiddenDirections: [RebuildStatement],
        topics: [RebuildTopic],
        worklines: [RebuildWorkline],
        deltas: [RebuildDelta]
    ) {
        self.projectId = projectId
        self.status = status
        self.currentSummary = currentSummary
        self.purpose = purpose
        self.inScope = inScope
        self.outOfScope = outOfScope
        self.objectModel = objectModel
        self.understanding = understanding
        self.acceptedDecisions = acceptedDecisions
        self.forbiddenDirections = forbiddenDirections
        self.topics = topics
        self.worklines = worklines
        self.deltas = deltas
    }
}

public struct RebuildStatement: Codable, Equatable, Sendable {
    public var text: String
    public var evidenceIds: [String]

    public init(text: String, evidenceIds: [String]) {
        self.text = text
        self.evidenceIds = evidenceIds
    }
}

public struct RebuildUnderstanding: Codable, Equatable, Sendable {
    public var text: String
    public var status: String
    public var evidenceIds: [String]

    public init(text: String, status: String, evidenceIds: [String]) {
        self.text = text
        self.status = status
        self.evidenceIds = evidenceIds
    }
}

public struct RebuildDecision: Codable, Equatable, Sendable {
    public var text: String
    public var rationale: String
    public var evidenceIds: [String]

    public init(text: String, rationale: String, evidenceIds: [String]) {
        self.text = text
        self.rationale = rationale
        self.evidenceIds = evidenceIds
    }
}

public struct RebuildTopic: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var kind: String
    public var disposition: String
    public var currentUnderstanding: String
    public var proposedDirection: String
    public var deferredReason: String
    public var revisitTrigger: String
    public var openQuestions: [String]
    public var evidenceIds: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        kind: String,
        disposition: String,
        currentUnderstanding: String,
        proposedDirection: String,
        deferredReason: String,
        revisitTrigger: String,
        openQuestions: [String],
        evidenceIds: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.disposition = disposition
        self.currentUnderstanding = currentUnderstanding
        self.proposedDirection = proposedDirection
        self.deferredReason = deferredReason
        self.revisitTrigger = revisitTrigger
        self.openQuestions = openQuestions
        self.evidenceIds = evidenceIds
    }
}

public struct RebuildWorkline: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var objective: String
    public var status: String
    public var stage: String
    public var startedAt: String
    public var updatedAt: String
    public var completedAt: String
    public var tags: [String]
    public var evidenceIds: [String]

    public init(
        id: String,
        title: String,
        objective: String,
        status: String,
        stage: String,
        startedAt: String,
        updatedAt: String,
        completedAt: String,
        tags: [String],
        evidenceIds: [String]
    ) {
        self.id = id
        self.title = title
        self.objective = objective
        self.status = status
        self.stage = stage
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.tags = tags
        self.evidenceIds = evidenceIds
    }
}

public struct RebuildDelta: Codable, Equatable, Sendable {
    public var id: String
    public var worklineId: String
    public var timestamp: String
    public var title: String
    public var summary: String
    public var kind: String
    public var stage: String
    public var delivery: String
    public var facts: [String]
    public var decisions: [String]
    public var evidenceIds: [String]

    public init(
        id: String,
        worklineId: String,
        timestamp: String,
        title: String,
        summary: String,
        kind: String,
        stage: String,
        delivery: String,
        facts: [String],
        decisions: [String],
        evidenceIds: [String]
    ) {
        self.id = id
        self.worklineId = worklineId
        self.timestamp = timestamp
        self.title = title
        self.summary = summary
        self.kind = kind
        self.stage = stage
        self.delivery = delivery
        self.facts = facts
        self.decisions = decisions
        self.evidenceIds = evidenceIds
    }
}
