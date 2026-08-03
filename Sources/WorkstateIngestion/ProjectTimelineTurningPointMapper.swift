import Foundation
import WorkstateCore

public struct ProjectTimelineTurningPointValidationContext: Sendable {
    public let projectID: String
    public let worklineIDs: Set<String>
    public let changeIDs: Set<String>
    public let sourceIDs: Set<String>

    public init(
        projectID: String,
        worklineIDs: [String],
        changeIDs: [String],
        sourceIDs: [String]
    ) {
        self.projectID = projectID
        self.worklineIDs = Set(worklineIDs)
        self.changeIDs = Set(changeIDs)
        self.sourceIDs = Set(sourceIDs)
    }
}

public struct ProjectTimelineTurningPointProposal: Codable, Equatable, Sendable {
    public var id: String
    public var projectID: String
    public var worklineID: String?
    public var title: String
    public var beforeMeaning: String
    public var afterMeaning: String
    public var scope: ProjectTimelineTurningPointScope
    public var timestamp: Date
    public var sourceIDs: [String]
    public var originatingChangeID: String

    public init(
        id: String,
        projectID: String,
        worklineID: String? = nil,
        title: String,
        beforeMeaning: String,
        afterMeaning: String,
        scope: ProjectTimelineTurningPointScope,
        timestamp: Date,
        sourceIDs: [String],
        originatingChangeID: String
    ) {
        self.id = id
        self.projectID = projectID
        self.worklineID = worklineID
        self.title = title
        self.beforeMeaning = beforeMeaning
        self.afterMeaning = afterMeaning
        self.scope = scope
        self.timestamp = timestamp
        self.sourceIDs = sourceIDs
        self.originatingChangeID = originatingChangeID
    }
}

public struct ProjectTimelineTurningPointMapper: Sendable {
    public init() {}

    public func map(
        _ proposal: ProjectTimelineTurningPointProposal?,
        in context: ProjectTimelineTurningPointValidationContext
    ) throws -> ProjectTimelineTurningPoint? {
        guard let proposal else { return nil }
        try validate(proposal, in: context)

        return ProjectTimelineTurningPoint(
            id: proposal.id,
            projectID: proposal.projectID,
            worklineID: proposal.worklineID,
            title: proposal.title,
            beforeMeaning: proposal.beforeMeaning,
            afterMeaning: proposal.afterMeaning,
            scope: proposal.scope,
            timestamp: proposal.timestamp,
            sourceIDs: proposal.sourceIDs.sorted(),
            originatingChangeID: proposal.originatingChangeID
        )
    }

    public func validate(
        _ proposal: ProjectTimelineTurningPointProposal,
        in context: ProjectTimelineTurningPointValidationContext
    ) throws {
        guard !context.projectID.isEmpty,
              proposal.projectID == context.projectID else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point references the wrong project: \(proposal.projectID)"
            )
        }
        guard !proposal.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState("Timeline turning point has no id")
        }
        guard !proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !proposal.beforeMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !proposal.afterMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              proposal.beforeMeaning != proposal.afterMeaning else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point requires a title and before/after meaning"
            )
        }
        guard proposal.timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point has an invalid timestamp: \(proposal.id)"
            )
        }
        guard !proposal.originatingChangeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              context.changeIDs.contains(proposal.originatingChangeID) else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point references an unknown change: \(proposal.originatingChangeID)"
            )
        }
        guard !proposal.sourceIDs.isEmpty else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point has no source ids: \(proposal.id)"
            )
        }
        let sourceIDs = Set(proposal.sourceIDs)
        guard sourceIDs.count == proposal.sourceIDs.count else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point contains duplicate source ids: \(proposal.id)"
            )
        }
        for sourceID in sourceIDs {
            guard context.sourceIDs.contains(sourceID) else {
                throw WorkstateStorageError.invalidState(
                    "Timeline turning point references an unknown source: \(sourceID)"
                )
            }
        }
        if let worklineID = proposal.worklineID {
            guard !worklineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  context.worklineIDs.contains(worklineID) else {
                throw WorkstateStorageError.invalidState(
                    "Timeline turning point references an unknown workline: \(worklineID)"
                )
            }
        }
        if proposal.scope == .workline, proposal.worklineID == nil {
            throw WorkstateStorageError.invalidState(
                "A workline turning point requires a workline id: \(proposal.id)"
            )
        }
    }
}
