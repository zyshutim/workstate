import Foundation
import WorkstateCore

public enum ProjectCognitionChecks {
    public static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-project-cognition-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceA = SourceReference(
            id: "cognition-check-source-a",
            kind: "conversation",
            label: "A",
            locator: "/tmp/cognition-a.jsonl"
        )
        let sourceB = SourceReference(
            id: "cognition-check-source-b",
            kind: "conversation",
            label: "B",
            locator: "/tmp/cognition-b.jsonl"
        )
        let sourceC = SourceReference(
            id: "cognition-check-source-c",
            kind: "conversation",
            label: "C",
            locator: "/tmp/cognition-c.jsonl"
        )
        let purpose = ProjectCognitionSection(
            id: "purpose",
            title: "Purpose",
            body: "The project picture",
            purpose: "Explain why the project exists",
            coverage: [.projectPurpose, .currentUnderstanding],
            sourceIDs: [sourceA.id],
            order: 0
        )
        let principles = ProjectCognitionSection(
            id: "principles",
            title: "Principles",
            body: "Confirmed principles and current state",
            purpose: "Record the current governing picture",
            coverage: [.decisionPrinciples, .currentState],
            sourceIDs: [sourceA.id],
            order: 1
        )
        let project = ProjectRecord(
            id: "cognition-check-project",
            name: "Cognition check",
            summary: "A project",
            events: [
                ProjectEvent(
                    id: "cognition-check-start",
                    title: "Started",
                    summary: "Started",
                    kind: .projectStarted,
                    loopStage: .intake
                )
            ]
        )
        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(
            initial: WorkspaceSnapshot(
                projects: [project],
                sources: [sourceA, sourceB, sourceC]
            )
        )
        let service = WorkstateService(repository: repository)
        _ = try service.saveProjectCognitionDraft(projectID: project.id, sections: [purpose, principles])
        _ = try service.confirmProjectCognitionDraft(projectID: project.id)

        let purposeAfter = ProjectCognitionSection(
            id: purpose.id,
            title: purpose.title,
            body: "Edited by the user",
            purpose: purpose.purpose,
            coverage: purpose.coverage,
            sourceIDs: [sourceA.id, sourceB.id],
            order: purpose.order
        )
        let principlesAfter = ProjectCognitionSection(
            id: principles.id,
            title: principles.title,
            body: "A separate proposal",
            purpose: principles.purpose,
            coverage: principles.coverage,
            sourceIDs: [sourceA.id, sourceC.id],
            order: principles.order
        )
        let purposeProposal = ProjectCognitionRevision(
            id: "purpose-proposal",
            operation: .update,
            beforeSections: [purpose],
            afterSections: [purposeAfter],
            baseVersion: 1,
            rationale: "The user corrected the project picture",
            sourceIDs: [sourceB.id]
        )
        let principlesProposal = ProjectCognitionRevision(
            id: "principles-proposal",
            operation: .update,
            beforeSections: [principles],
            afterSections: [principlesAfter],
            baseVersion: 1,
            rationale: "A separate confirmed correction",
            sourceIDs: [sourceC.id]
        )
        _ = try service.upsertProjectCognitionRevision(projectID: project.id, revision: purposeProposal)
        _ = try service.upsertProjectCognitionRevision(projectID: project.id, revision: principlesProposal)

        let edited = ProjectCognitionSection(
            id: purpose.id,
            title: purpose.title,
            body: "Accepted edited picture",
            purpose: purpose.purpose,
            coverage: purpose.coverage,
            sourceIDs: [sourceA.id, sourceB.id],
            order: purpose.order
        )
        _ = try service.resolveProjectCognitionRevision(
            projectID: project.id,
            revisionID: purposeProposal.id,
            resolution: .accepted,
            editedAfterSections: [edited],
            comment: "Accepted after checking the source"
        )
        var cognition = try service.snapshot().project(id: project.id)?.context.cognition
        try require(cognition?.version == 2, "acceptance creates the next canonical version")
        try require(cognition?.sections.first?.body == edited.body, "accepted edits become canonical")
        try require(
            cognition?.revisions.first(where: { $0.id == purposeProposal.id })?.afterSections.first?.body
                == purposeAfter.body,
            "the original proposal remains reviewable"
        )
        try require(
            cognition?.revisions.first(where: { $0.id == purposeProposal.id })?.resolvedAfterSections?.first?.body
                == edited.body,
            "accepted edits are retained separately from the proposal"
        )
        try require(
            cognition?.revisions.first(where: { $0.id == purposeProposal.id })?.resolutionComment
                == "Accepted after checking the source",
            "resolution comments remain reviewable"
        )
        try require(
            cognition?.revisions.first(where: { $0.id == principlesProposal.id })?.baseVersion == 2,
            "an independent pending proposal rebases"
        )

        _ = try service.resolveProjectCognitionRevision(
            projectID: project.id,
            revisionID: principlesProposal.id,
            resolution: .rejected,
            comment: "Rejected because the source does not change the picture"
        )
        cognition = try service.snapshot().project(id: project.id)?.context.cognition
        try require(cognition?.version == 2, "rejection does not create a canonical version")
        try require(cognition?.sections.last?.body == principles.body, "rejection does not mutate canonical content")
        try require(
            cognition?.revisions.first(where: { $0.id == principlesProposal.id })?.resolutionComment
                == "Rejected because the source does not change the picture",
            "rejection comments remain reviewable"
        )

        let invalidCoverage = ProjectCognitionRevision(
            id: "invalid-coverage",
            operation: .update,
            beforeSections: [edited],
            afterSections: [
                ProjectCognitionSection(
                    id: purpose.id,
                    title: purpose.title,
                    body: "Missing coverage",
                    purpose: purpose.purpose,
                    coverage: [],
                    sourceIDs: [sourceA.id],
                    order: purpose.order
                )
            ],
            baseVersion: 2,
            rationale: "Invalid proposal",
            sourceIDs: [sourceB.id]
        )
        try expectFailure {
            _ = try service.upsertProjectCognitionRevision(projectID: project.id, revision: invalidCoverage)
        }

        var legacyObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: repository.paths.state)
        ) as! [String: Any]
        var projects = legacyObject["projects"] as! [[String: Any]]
        var context = projects[0]["context"] as! [String: Any]
        var document = context["cognition"] as! [String: Any]
        var revisions = document["revisions"] as! [[String: Any]]
        for index in revisions.indices {
            revisions[index].removeValue(forKey: "resolutionComment")
            revisions[index].removeValue(forKey: "resolvedAfterSections")
        }
        document["revisions"] = revisions
        context["cognition"] = document
        projects[0]["context"] = context
        legacyObject["projects"] = projects
        try JSONSerialization.data(withJSONObject: legacyObject).write(to: repository.paths.state, options: .atomic)
        _ = try repository.load()
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw WorkstateStorageError.invalidState(message) }
    }

    private static func expectFailure(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch WorkstateStorageError.invalidState {
            return
        }
        throw WorkstateStorageError.invalidState("Expected cognition check failure")
    }
}
