import Foundation
import WorkstateCore

public struct RelationSourceReplacement: Equatable, Sendable {
    public var relationID: String
    public var sourceIDs: [String]

    public init(relationID: String, sourceIDs: [String]) {
        self.relationID = relationID
        self.sourceIDs = sourceIDs
    }
}

public struct WorkspaceReconcileResult: Equatable, Sendable {
    public var snapshot: WorkspaceSnapshot
    public var removedSourceCount: Int
}

public struct WorkspaceReconciler: Sendable {
    public let repository: WorkstateRepository

    public init(repository: WorkstateRepository = .init()) {
        self.repository = repository
    }

    public func reconcile(
        relationSources: [RelationSourceReplacement],
        pruneUnusedSources: Bool = true
    ) throws -> WorkspaceReconcileResult {
        var removedSourceCount = 0
        let snapshot = try repository.update(
            mutation: WorkspaceMutation(
                kind: "workspace.reconcile",
                summary: "Reconciled relation evidence and source registry"
            )
        ) { snapshot in
            let knownSourceIDs = Set(snapshot.sources.map(\.id))
            for replacement in relationSources {
                guard let relationIndex = snapshot.relations.firstIndex(where: { $0.id == replacement.relationID }) else {
                    throw WorkstateStorageError.invalidState("Unknown relation: \(replacement.relationID)")
                }
                for sourceID in replacement.sourceIDs where !knownSourceIDs.contains(sourceID) {
                    throw WorkstateStorageError.invalidState("Unknown relation source: \(sourceID)")
                }
                snapshot.relations[relationIndex].sourceIDs = replacement.sourceIDs
            }

            guard pruneUnusedSources else { return }
            let used = referencedSourceIDs(in: snapshot)
            let previousCount = snapshot.sources.count
            snapshot.sources.removeAll { !used.contains($0.id) }
            removedSourceCount = previousCount - snapshot.sources.count
        }
        return WorkspaceReconcileResult(snapshot: snapshot, removedSourceCount: removedSourceCount)
    }

    private func referencedSourceIDs(in snapshot: WorkspaceSnapshot) -> Set<String> {
        var used = Set<String>()
        for project in snapshot.projects {
            used.formUnion(project.sourceIDs)
            for statement in project.context.understanding { used.formUnion(statement.sourceIDs) }
            for revision in project.context.revisions { used.formUnion(revision.sourceIDs) }
            for decision in project.context.acceptedDecisions { used.formUnion(decision.sourceIDs) }
            if let cognition = project.context.cognition {
                for section in cognition.sections { used.formUnion(section.sourceIDs) }
                for revision in cognition.revisions {
                    used.formUnion(revision.sourceIDs)
                    for section in revision.beforeSections { used.formUnion(section.sourceIDs) }
                    for section in revision.afterSections { used.formUnion(section.sourceIDs) }
                }
            }
            for task in project.tasks { used.formUnion(task.sourceIDs) }
            for event in project.events {
                used.formUnion(event.sourceIDs)
                for decision in event.decisions { used.formUnion(decision.sourceIDs) }
            }
        }
        for relation in snapshot.relations { used.formUnion(relation.sourceIDs) }
        for review in snapshot.reviewInbox { used.formUnion(review.sourceIDs) }
        return used
    }
}
