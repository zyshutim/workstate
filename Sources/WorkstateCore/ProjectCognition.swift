import Foundation

public enum ProjectCognitionState: String, Codable, CaseIterable, Sendable {
    case uninitialized
    case draft
    case confirmed
}

public enum ProjectCognitionCoverage: String, Codable, CaseIterable, Sendable {
    case projectPurpose
    case currentUnderstanding
    case decisionPrinciples
    case currentState
}

public enum ProjectCognitionRevisionOperation: String, Codable, CaseIterable, Sendable {
    case update
    case insert
    case delete
    case split
    case merge
}

public enum ProjectCognitionRevisionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
}

public enum ProjectCognitionRevisionResolution: String, Codable, CaseIterable, Sendable {
    case accepted
    case rejected
}

public struct ProjectCognitionSection: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var purpose: String
    public var inclusionRules: [String]
    public var exclusionRules: [String]
    public var updateTriggers: [String]
    public var coverage: [ProjectCognitionCoverage]
    public var sourceIDs: [String]
    public var order: Int

    public init(
        id: String,
        title: String,
        body: String,
        purpose: String,
        inclusionRules: [String] = [],
        exclusionRules: [String] = [],
        updateTriggers: [String] = [],
        coverage: [ProjectCognitionCoverage] = [],
        sourceIDs: [String] = [],
        order: Int
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.purpose = purpose
        self.inclusionRules = inclusionRules
        self.exclusionRules = exclusionRules
        self.updateTriggers = updateTriggers
        self.coverage = coverage
        self.sourceIDs = sourceIDs
        self.order = order
    }
}

public struct ProjectCognitionRevision: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var operation: ProjectCognitionRevisionOperation
    public var beforeSections: [ProjectCognitionSection]
    public var afterSections: [ProjectCognitionSection]
    public var baseVersion: Int
    public var rationale: String
    public var sourceIDs: [String]
    public var status: ProjectCognitionRevisionStatus
    public var createdAt: Date
    public var resolvedAt: Date?
    public var resolutionComment: String?
    public var resolvedAfterSections: [ProjectCognitionSection]?

    public init(
        id: String = UUID().uuidString.lowercased(),
        operation: ProjectCognitionRevisionOperation,
        beforeSections: [ProjectCognitionSection] = [],
        afterSections: [ProjectCognitionSection] = [],
        baseVersion: Int,
        rationale: String,
        sourceIDs: [String] = [],
        status: ProjectCognitionRevisionStatus = .pending,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolutionComment: String? = nil,
        resolvedAfterSections: [ProjectCognitionSection]? = nil
    ) {
        self.id = id
        self.operation = operation
        self.beforeSections = beforeSections
        self.afterSections = afterSections
        self.baseVersion = baseVersion
        self.rationale = rationale
        self.sourceIDs = sourceIDs
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolutionComment = resolutionComment
        self.resolvedAfterSections = resolvedAfterSections
    }
}

public struct ProjectCognitionDocument: Codable, Equatable, Sendable {
    public var state: ProjectCognitionState
    public var version: Int
    public var sections: [ProjectCognitionSection]
    public var revisions: [ProjectCognitionRevision]
    public var generatedAt: Date
    public var confirmedAt: Date?
    public var updatedAt: Date

    public init(
        state: ProjectCognitionState = .uninitialized,
        version: Int = 0,
        sections: [ProjectCognitionSection] = [],
        revisions: [ProjectCognitionRevision] = [],
        generatedAt: Date = Date(),
        confirmedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.version = version
        self.sections = sections
        self.revisions = revisions
        self.generatedAt = generatedAt
        self.confirmedAt = confirmedAt
        self.updatedAt = updatedAt
    }
}

internal enum ProjectCognitionValidation {
    static func validate(
        _ document: ProjectCognitionDocument?,
        knownSourceIDs: Set<String>,
        projectID: String
    ) throws {
        guard let document else { return }
        guard document.version >= 0 else {
            throw WorkstateStorageError.invalidState("Project \(projectID) cognition has a negative version")
        }

        try validateSections(
            document.sections,
            knownSourceIDs: knownSourceIDs,
            owner: "project \(projectID) cognition",
            requireContent: document.state != .uninitialized
        )

        let revisionIDs = Set(document.revisions.map(\.id))
        guard revisionIDs.count == document.revisions.count else {
            throw WorkstateStorageError.invalidState("Duplicate cognition revision id in \(projectID)")
        }

        var pendingSectionIDs = Set<String>()
        for revision in document.revisions {
            try validateRevision(revision, knownSourceIDs: knownSourceIDs, owner: "cognition revision \(revision.id)")
            if revision.status == .pending {
                guard document.state == .confirmed else {
                    throw WorkstateStorageError.invalidState("Pending cognition revision requires a confirmed document")
                }
                guard revision.baseVersion == document.version else {
                    throw WorkstateStorageError.invalidState("Pending cognition revision \(revision.id) has a stale base version")
                }
                let touchedIDs = touchedSectionIDs(revision)
                guard pendingSectionIDs.isDisjoint(with: touchedIDs) else {
                    throw WorkstateStorageError.invalidState("Overlapping pending cognition revisions in \(projectID)")
                }
                pendingSectionIDs.formUnion(touchedIDs)
            } else {
                guard revision.resolvedAt != nil else {
                    throw WorkstateStorageError.invalidState("Resolved cognition revision \(revision.id) has no resolvedAt")
                }
                guard revision.baseVersion <= document.version else {
                    throw WorkstateStorageError.invalidState("Resolved cognition revision \(revision.id) has an invalid base version")
                }
            }
        }

        switch document.state {
        case .uninitialized:
            guard document.version == 0, document.confirmedAt == nil, document.sections.isEmpty else {
                throw WorkstateStorageError.invalidState("Uninitialized cognition document has content")
            }
            guard document.revisions.isEmpty else {
                throw WorkstateStorageError.invalidState("Uninitialized cognition document has revisions")
            }
        case .draft:
            guard document.version == 0, document.confirmedAt == nil else {
                throw WorkstateStorageError.invalidState("Draft cognition document has an invalid version")
            }
            guard document.revisions.isEmpty else {
                throw WorkstateStorageError.invalidState("Draft cognition document cannot have revisions")
            }
            try validateCoverage(document.sections, projectID: projectID)
        case .confirmed:
            guard document.version > 0, document.confirmedAt != nil else {
                throw WorkstateStorageError.invalidState("Confirmed cognition document has no confirmation")
            }
            try validateCoverage(document.sections, projectID: projectID)
        }
    }

    static func validateSections(
        _ sections: [ProjectCognitionSection],
        knownSourceIDs: Set<String>,
        owner: String,
        requireContent: Bool
    ) throws {
        let ids = Set(sections.map(\.id))
        guard ids.count == sections.count else {
            throw WorkstateStorageError.invalidState("Duplicate cognition section id in \(owner)")
        }
        let orders = Set(sections.map(\.order))
        guard orders.count == sections.count else {
            throw WorkstateStorageError.invalidState("Duplicate cognition section order in \(owner)")
        }
        for section in sections {
            guard !section.id.isEmpty else {
                throw WorkstateStorageError.invalidState("Empty cognition section id in \(owner)")
            }
            guard section.order >= 0 else {
                throw WorkstateStorageError.invalidState("Negative cognition section order in \(owner)")
            }
            if requireContent {
                guard !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !section.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !section.sourceIDs.isEmpty else {
                    throw WorkstateStorageError.invalidState("Empty required cognition section field in \(owner)")
                }
            }
            try validateSourceIDs(section.sourceIDs, known: knownSourceIDs, owner: "section \(section.id)")
        }
    }

    static func validateRevision(
        _ revision: ProjectCognitionRevision,
        knownSourceIDs: Set<String>,
        owner: String
    ) throws {
        guard !revision.id.isEmpty, revision.baseVersion >= 1 else {
            throw WorkstateStorageError.invalidState("Invalid \(owner) identity or base version")
        }
        guard !revision.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !revision.sourceIDs.isEmpty else {
            throw WorkstateStorageError.invalidState("Cognition revision requires rationale and evidence")
        }
        switch revision.status {
        case .pending:
            guard revision.resolvedAt == nil,
                  revision.resolutionComment == nil,
                  revision.resolvedAfterSections == nil else {
                throw WorkstateStorageError.invalidState("Pending \(owner) has resolution data")
            }
        case .accepted, .rejected:
            guard revision.resolvedAt != nil else {
                throw WorkstateStorageError.invalidState("Resolved \(owner) has no resolvedAt")
            }
            if let comment = revision.resolutionComment {
                guard !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw WorkstateStorageError.invalidState("Resolved \(owner) has an empty comment")
                }
            }
            if revision.status == .rejected {
                guard revision.resolvedAfterSections == nil else {
                    throw WorkstateStorageError.invalidState("Rejected \(owner) has edited sections")
                }
            }
        }
        try validateSections(revision.beforeSections, knownSourceIDs: knownSourceIDs, owner: "\(owner) before", requireContent: true)
        try validateSections(revision.afterSections, knownSourceIDs: knownSourceIDs, owner: "\(owner) after", requireContent: true)
        try validateSourceIDs(revision.sourceIDs, known: knownSourceIDs, owner: owner)

        if let resolvedAfterSections = revision.resolvedAfterSections {
            try validateSections(
                resolvedAfterSections,
                knownSourceIDs: knownSourceIDs,
                owner: "\(owner) resolved after",
                requireContent: true
            )
        }

        switch revision.operation {
        case .update:
            guard revision.beforeSections.count == 1,
                  revision.afterSections.count == 1,
                  revision.beforeSections[0].id == revision.afterSections[0].id else {
                throw WorkstateStorageError.invalidState("Update cognition revision must replace one section")
            }
        case .insert:
            guard revision.beforeSections.isEmpty, !revision.afterSections.isEmpty else {
                throw WorkstateStorageError.invalidState("Insert cognition revision has an invalid shape")
            }
        case .delete:
            guard !revision.beforeSections.isEmpty, revision.afterSections.isEmpty else {
                throw WorkstateStorageError.invalidState("Delete cognition revision has an invalid shape")
            }
        case .split:
            guard revision.beforeSections.count == 1, revision.afterSections.count >= 2 else {
                throw WorkstateStorageError.invalidState("Split cognition revision has an invalid shape")
            }
        case .merge:
            guard revision.beforeSections.count >= 2, revision.afterSections.count == 1 else {
                throw WorkstateStorageError.invalidState("Merge cognition revision has an invalid shape")
            }
        }

        if let resolvedAfterSections = revision.resolvedAfterSections {
            try validateOperationShape(
                operation: revision.operation,
                beforeSections: revision.beforeSections,
                afterSections: resolvedAfterSections,
                owner: owner
            )
        }
    }

    private static func validateOperationShape(
        operation: ProjectCognitionRevisionOperation,
        beforeSections: [ProjectCognitionSection],
        afterSections: [ProjectCognitionSection],
        owner: String
    ) throws {
        let valid = switch operation {
        case .update:
            beforeSections.count == 1
                && afterSections.count == 1
                && beforeSections[0].id == afterSections[0].id
        case .insert:
            beforeSections.isEmpty && !afterSections.isEmpty
        case .delete:
            !beforeSections.isEmpty && afterSections.isEmpty
        case .split:
            beforeSections.count == 1 && afterSections.count >= 2
        case .merge:
            beforeSections.count >= 2 && afterSections.count == 1
        }
        guard valid else {
            throw WorkstateStorageError.invalidState("\(owner) has invalid resolved operation shape")
        }
    }

    static func validateCoverage(_ sections: [ProjectCognitionSection], projectID: String) throws {
        let covered = Set(sections.flatMap(\.coverage))
        let required = Set(ProjectCognitionCoverage.allCases)
        guard covered == required else {
            let missing = required.subtracting(covered).map(\.rawValue).sorted().joined(separator: ", ")
            throw WorkstateStorageError.invalidState("Project \(projectID) cognition is missing coverage: \(missing)")
        }
    }

    static func validateSourceIDs(_ ids: [String], known: Set<String>, owner: String) throws {
        for id in ids where !known.contains(id) {
            throw WorkstateStorageError.invalidState("\(owner) references unknown source \(id)")
        }
    }

    static func touchedSectionIDs(_ revision: ProjectCognitionRevision) -> Set<String> {
        Set(revision.beforeSections.map(\.id) + revision.afterSections.map(\.id))
    }
}

internal enum ProjectCognitionMutation {
    static func upsertPendingRevision(
        _ revision: ProjectCognitionRevision,
        projectID: String,
        knownSourceIDs: Set<String>,
        timestamp: Date,
        cognition: inout ProjectCognitionDocument
    ) throws {
        guard cognition.state == .confirmed else {
            throw WorkstateStorageError.invalidState(
                "Cognition proposals require a confirmed document for \(projectID)"
            )
        }
        guard revision.status == .pending, revision.resolvedAt == nil else {
            throw WorkstateStorageError.invalidState("Cognition proposal must be pending")
        }
        guard revision.baseVersion == cognition.version else {
            throw WorkstateStorageError.invalidState("Cognition proposal has a stale base version")
        }
        var proposed = revision
        try ProjectCognitionValidation.validateRevision(
            proposed,
            knownSourceIDs: knownSourceIDs,
            owner: "cognition revision \(proposed.id)"
        )
        let canonicalIDs = Set(cognition.sections.map(\.id))
        let beforeIDs = Set(proposed.beforeSections.map(\.id))
        guard canonicalIDs.isSuperset(of: beforeIDs) else {
            throw WorkstateStorageError.invalidState(
                "Cognition proposal references unknown canonical sections"
            )
        }
        guard (proposed.beforeSections == cognition.sections.filter {
            ProjectCognitionValidation.touchedSectionIDs(proposed).contains($0.id)
        }) || proposed.operation == .insert else {
            throw WorkstateStorageError.invalidState(
                "Cognition proposal is based on stale section content"
            )
        }
        let afterIDs = Set(proposed.afterSections.map(\.id))
        guard canonicalIDs.subtracting(beforeIDs).isDisjoint(with: afterIDs) else {
            throw WorkstateStorageError.invalidState(
                "Cognition proposal creates duplicate section ids"
            )
        }
        let resultingSections = cognition.sections.filter { !beforeIDs.contains($0.id) } + proposed.afterSections
        try ProjectCognitionValidation.validateSections(
            resultingSections,
            knownSourceIDs: knownSourceIDs,
            owner: "project \(projectID) cognition proposal",
            requireContent: true
        )
        try ProjectCognitionValidation.validateCoverage(resultingSections, projectID: projectID)
        let touchedIDs = ProjectCognitionValidation.touchedSectionIDs(proposed)
        for existing in cognition.revisions
        where existing.status == .pending && existing.id != proposed.id {
            guard ProjectCognitionValidation.touchedSectionIDs(existing)
                .isDisjoint(with: touchedIDs) else {
                throw WorkstateStorageError.invalidState(
                    "Cognition proposal overlaps another pending revision"
                )
            }
        }
        if let existingIndex = cognition.revisions.firstIndex(where: { $0.id == proposed.id }) {
            guard cognition.revisions[existingIndex].status == .pending else {
                throw WorkstateStorageError.invalidState(
                    "Resolved cognition revision cannot be replaced"
                )
            }
            proposed.createdAt = cognition.revisions[existingIndex].createdAt
            cognition.revisions[existingIndex] = proposed
        } else {
            cognition.revisions.append(proposed)
        }
        cognition.updatedAt = timestamp
    }
}

public extension WorkstateService {
    @discardableResult
    func saveProjectCognitionDraft(
        projectID: String,
        sections: [ProjectCognitionSection],
        generatedAt: Date = Date()
    ) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "projectCognition.draft.save",
            summary: "Saved project cognition draft",
            projectID: projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
                throw WorkstateStorageError.missingProject(projectID)
            }
            if let existing = snapshot.projects[projectIndex].context.cognition,
               existing.state == .confirmed {
                throw WorkstateStorageError.invalidState("Cannot replace confirmed cognition for \(projectID)")
            }
            let sourceIDs = Set(snapshot.sources.map(\.id))
            try ProjectCognitionValidation.validateSections(
                sections,
                knownSourceIDs: sourceIDs,
                owner: "project \(projectID) cognition draft",
                requireContent: true
            )
            try ProjectCognitionValidation.validateCoverage(sections, projectID: projectID)
            snapshot.projects[projectIndex].context.cognition = ProjectCognitionDocument(
                state: .draft,
                version: 0,
                sections: sections,
                generatedAt: generatedAt,
                updatedAt: mutation.timestamp
            )
        }
    }

    @discardableResult
    func confirmProjectCognitionDraft(projectID: String) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "projectCognition.draft.confirm",
            summary: "Confirmed project cognition v1",
            projectID: projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
                throw WorkstateStorageError.missingProject(projectID)
            }
            guard var cognition = snapshot.projects[projectIndex].context.cognition else {
                throw WorkstateStorageError.invalidState("Project \(projectID) has no cognition draft")
            }
            guard cognition.state == .draft else {
                throw WorkstateStorageError.invalidState("Project \(projectID) cognition is not a draft")
            }
            let sourceIDs = Set(snapshot.sources.map(\.id))
            try ProjectCognitionValidation.validateSections(
                cognition.sections,
                knownSourceIDs: sourceIDs,
                owner: "project \(projectID) cognition draft",
                requireContent: true
            )
            try ProjectCognitionValidation.validateCoverage(cognition.sections, projectID: projectID)
            cognition.state = .confirmed
            cognition.version = 1
            cognition.confirmedAt = mutation.timestamp
            cognition.updatedAt = mutation.timestamp
            snapshot.projects[projectIndex].context.cognition = cognition
            appendCognitionEvent(
                to: &snapshot.projects[projectIndex],
                title: "Project cognition confirmed",
                summary: "Confirmed project cognition v1",
                sourceIDs: cognition.sections.flatMap(\.sourceIDs),
                timestamp: mutation.timestamp
            )
        }
    }

    @discardableResult
    func upsertProjectCognitionRevision(
        projectID: String,
        revision: ProjectCognitionRevision
    ) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "projectCognition.revision.upsert",
            summary: revision.rationale,
            projectID: projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
                throw WorkstateStorageError.missingProject(projectID)
            }
            guard var cognition = snapshot.projects[projectIndex].context.cognition else {
                throw WorkstateStorageError.invalidState(
                    "Cognition proposals require a confirmed document"
                )
            }
            try ProjectCognitionMutation.upsertPendingRevision(
                revision,
                projectID: projectID,
                knownSourceIDs: Set(snapshot.sources.map(\.id)),
                timestamp: mutation.timestamp,
                cognition: &cognition
            )
            snapshot.projects[projectIndex].context.cognition = cognition
        }
    }

    @discardableResult
    func resolveProjectCognitionRevision(
        projectID: String,
        revisionID: String,
        resolution: ProjectCognitionRevisionResolution,
        editedAfterSections: [ProjectCognitionSection]? = nil,
        comment: String? = nil
    ) throws -> WorkspaceSnapshot {
        let mutation = WorkspaceMutation(
            kind: "projectCognition.revision.resolve",
            summary: "Resolved project cognition revision",
            projectID: projectID
        )
        return try repository.update(mutation: mutation) { snapshot in
            guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
                throw WorkstateStorageError.missingProject(projectID)
            }
            guard var cognition = snapshot.projects[projectIndex].context.cognition,
                  cognition.state == .confirmed else {
                throw WorkstateStorageError.invalidState("Cognition revisions require a confirmed document")
            }
            guard let revisionIndex = cognition.revisions.firstIndex(where: { $0.id == revisionID }) else {
                throw WorkstateStorageError.invalidState("Cognition revision not found: \(revisionID)")
            }
            let revision = cognition.revisions[revisionIndex]
            guard revision.status == .pending, revision.resolvedAt == nil else {
                throw WorkstateStorageError.invalidState("Cognition revision is already resolved: \(revisionID)")
            }
            guard revision.baseVersion == cognition.version else {
                throw WorkstateStorageError.invalidState("Cognition revision has a stale base version")
            }
            guard resolution == .accepted || editedAfterSections == nil else {
                throw WorkstateStorageError.invalidState("Rejected cognition revision cannot include edited sections")
            }
            let normalizedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedComment?.isEmpty != true else {
                throw WorkstateStorageError.invalidState("Cognition resolution comment cannot be empty")
            }

            let sourceIDs = Set(snapshot.sources.map(\.id))
            let afterSections = editedAfterSections ?? revision.afterSections
            try ProjectCognitionValidation.validateSections(
                afterSections,
                knownSourceIDs: sourceIDs,
                owner: "cognition revision \(revisionID) after",
                requireContent: true
            )
            var resolvedRevision = revision
            resolvedRevision.status = resolution == .accepted ? .accepted : .rejected
            resolvedRevision.resolvedAt = mutation.timestamp
            resolvedRevision.resolutionComment = normalizedComment
            resolvedRevision.resolvedAfterSections = resolution == .accepted
                ? editedAfterSections
                : nil
            try ProjectCognitionValidation.validateRevision(
                resolvedRevision,
                knownSourceIDs: sourceIDs,
                owner: "cognition revision \(revisionID)"
            )

            cognition.revisions[revisionIndex] = resolvedRevision
            cognition.updatedAt = mutation.timestamp

            if resolution == .accepted {
                guard (revision.beforeSections == cognition.sections.filter {
                    ProjectCognitionValidation.touchedSectionIDs(revision).contains($0.id)
                }) || revision.operation == .insert else {
                    throw WorkstateStorageError.invalidState("Cognition revision is based on stale section content")
                }
                let beforeIDs = Set(revision.beforeSections.map(\.id))
                let existingIDs = Set(cognition.sections.map(\.id)).subtracting(beforeIDs)
                let afterIDs = Set(afterSections.map(\.id))
                guard existingIDs.isDisjoint(with: afterIDs) else {
                    throw WorkstateStorageError.invalidState("Accepted cognition revision creates duplicate section ids")
                }
                cognition.sections = (cognition.sections.filter { !beforeIDs.contains($0.id) } + afterSections)
                    .sorted { $0.order < $1.order }
                try ProjectCognitionValidation.validateSections(
                    cognition.sections,
                    knownSourceIDs: sourceIDs,
                    owner: "project \(projectID) cognition",
                    requireContent: true
                )
                try ProjectCognitionValidation.validateCoverage(cognition.sections, projectID: projectID)
                cognition.version += 1
                for index in cognition.revisions.indices
                where cognition.revisions[index].status == .pending {
                    cognition.revisions[index].baseVersion = cognition.version
                }
                appendCognitionEvent(
                    to: &snapshot.projects[projectIndex],
                    title: "Project cognition updated",
                    summary: resolvedRevision.rationale,
                    sourceIDs: resolvedRevision.sourceIDs + afterSections.flatMap(\.sourceIDs),
                    timestamp: mutation.timestamp
                )
            }
            snapshot.projects[projectIndex].context.cognition = cognition
        }
    }
}

private func appendCognitionEvent(
    to project: inout ProjectRecord,
    title: String,
    summary: String,
    sourceIDs: [String],
    timestamp: Date
) {
    project.events.append(
        ProjectEvent(
            timestamp: timestamp,
            title: title,
            summary: summary.isEmpty ? title : summary,
            kind: .contextUpdate,
            loopStage: .acceptance,
            parentEventIDs: project.latestEvent.map { [$0.id] } ?? [],
            sourceIDs: Array(Set(sourceIDs)).sorted()
        )
    )
    project.updatedAt = max(project.updatedAt, timestamp)
    project.lastActivityAt = max(project.lastActivityAt, timestamp)
}
