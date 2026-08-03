import Foundation

public enum ProjectTimelineTurningPointScope: String, Codable, CaseIterable, Sendable {
    case project
    case module
    case interaction
    case informationArchitecture
    case workline
    case productModel
}

// Keep turning points separate from ProjectEvent so existing event JSON needs no migration.
public struct ProjectTimelineTurningPoint: Codable, Equatable, Identifiable, Sendable {
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

public enum ProjectTimelineTurningPointApplication {
    public static func appending(
        _ turningPoint: ProjectTimelineTurningPoint,
        to existing: [ProjectTimelineTurningPoint]
    ) throws -> [ProjectTimelineTurningPoint] {
        try appending([turningPoint], to: existing)
    }

    public static func appending(
        _ turningPoints: [ProjectTimelineTurningPoint],
        to existing: [ProjectTimelineTurningPoint]
    ) throws -> [ProjectTimelineTurningPoint] {
        let existingIDs = existing.map(\.id)
        guard Set(existingIDs).count == existingIDs.count else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning-point collection contains duplicate ids"
            )
        }

        var result = existing
        for turningPoint in turningPoints {
            if let existingPoint = result.first(where: {
                $0.originatingChangeID == turningPoint.originatingChangeID
            }) {
                guard existingPoint == turningPoint else {
                    throw WorkstateStorageError.invalidState(
                        "One project change cannot own multiple timeline turning points: \(turningPoint.originatingChangeID)"
                    )
                }
                continue
            }
            if let index = result.firstIndex(where: { $0.id == turningPoint.id }) {
                guard result[index] == turningPoint else {
                    throw WorkstateStorageError.invalidState(
                        "Timeline turning-point id conflicts with an existing marker: \(turningPoint.id)"
                    )
                }
                continue
            }
            result.append(turningPoint)
        }
        return result
    }
}
