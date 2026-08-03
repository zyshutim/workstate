import CryptoKit
import Foundation
import WorkstateCore

public struct ProjectCognitionProposalMapper: Sendable {
    public init() {}

    public func map(
        _ proposal: StewardCognitionProposal,
        project: ProjectRecord,
        sourceIDs: [String],
        timestamp: Date = Date()
    ) throws -> ProjectCognitionRevision? {
        guard !proposal.isEmpty else { return nil }
        guard let cognition = project.context.cognition,
              cognition.state == .confirmed else {
            throw WorkstateStorageError.invalidState(
                "A cognition proposal requires a confirmed project cognition document"
            )
        }
        guard let operation = ProjectCognitionRevisionOperation(rawValue: proposal.operation) else {
            throw WorkstateStorageError.invalidState("Unsupported cognition proposal operation")
        }

        let beforeIDs = proposal.beforeSectionIDs
        guard Set(beforeIDs).count == beforeIDs.count else {
            throw WorkstateStorageError.invalidState("Cognition proposal repeats a canonical section")
        }
        let canonicalByID = Dictionary(uniqueKeysWithValues: cognition.sections.map { ($0.id, $0) })
        for sectionID in beforeIDs where canonicalByID[sectionID] == nil {
            throw WorkstateStorageError.invalidState(
                "Cognition proposal references unknown section: \(sectionID)"
            )
        }
        let beforeIDSet = Set(beforeIDs)
        let beforeSections = cognition.sections.filter { beforeIDSet.contains($0.id) }

        let inheritedSourceIDs = Set(beforeSections.flatMap(\.sourceIDs))
        let proposedSourceIDs = Set(sourceIDs)
        let afterSections = try proposal.afterSections.map { proposed in
            let coverage = try proposed.coverage.map { rawValue in
                guard let value = ProjectCognitionCoverage(rawValue: rawValue) else {
                    throw WorkstateStorageError.invalidState(
                        "Unsupported cognition coverage: \(rawValue)"
                    )
                }
                return value
            }
            let sectionSources = Set(canonicalByID[proposed.id]?.sourceIDs ?? [])
                .union(inheritedSourceIDs)
                .union(proposedSourceIDs)
            return ProjectCognitionSection(
                id: proposed.id,
                title: proposed.title,
                body: proposed.body,
                purpose: proposed.purpose,
                inclusionRules: proposed.inclusionRules,
                exclusionRules: proposed.exclusionRules,
                updateTriggers: proposed.updateTriggers,
                coverage: coverage,
                sourceIDs: sectionSources.sorted(),
                order: proposed.order
            )
        }

        try validateShape(
            operation: operation,
            beforeSections: beforeSections,
            afterSections: afterSections
        )
        let resultingSections = cognition.sections.filter { !beforeIDSet.contains($0.id) }
            + afterSections
        try validateResultingDocument(resultingSections)

        let identityIDs = beforeIDs.isEmpty ? afterSections.map(\.id) : beforeIDs
        let identitySet = Set(identityIDs)
        let existingPending = cognition.revisions.first(where: { revision in
            let revisionIdentity = revision.beforeSections.isEmpty
                ? revision.afterSections.map(\.id)
                : revision.beforeSections.map(\.id)
            return revision.status == .pending && Set(revisionIdentity) == identitySet
        })
        let revisionID = existingPending?.id
            ?? "cognition-revision-\(project.id)-v\(cognition.version)-\(digest(identityIDs.sorted().joined(separator: "\n")))"
        let createdAt = existingPending?.createdAt ?? timestamp
        return ProjectCognitionRevision(
            id: revisionID,
            operation: operation,
            beforeSections: beforeSections,
            afterSections: afterSections,
            baseVersion: cognition.version,
            rationale: proposal.summary,
            sourceIDs: proposedSourceIDs.sorted(),
            status: .pending,
            createdAt: createdAt
        )
    }

    private func validateShape(
        operation: ProjectCognitionRevisionOperation,
        beforeSections: [ProjectCognitionSection],
        afterSections: [ProjectCognitionSection]
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
            throw WorkstateStorageError.invalidState("Cognition proposal has an invalid operation shape")
        }
    }

    private func validateResultingDocument(_ sections: [ProjectCognitionSection]) throws {
        guard !sections.isEmpty,
              Set(sections.map(\.id)).count == sections.count,
              Set(sections.map(\.order)).count == sections.count,
              sections.allSatisfy({
                  !$0.id.isEmpty
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              Set(sections.flatMap(\.coverage)) == Set(ProjectCognitionCoverage.allCases) else {
            throw WorkstateStorageError.invalidState(
                "Cognition proposal would create an invalid project cognition document"
            )
        }
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(10)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
