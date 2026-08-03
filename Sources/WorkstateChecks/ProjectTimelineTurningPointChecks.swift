import Foundation
import WorkstateCore
import WorkstateIngestion

public enum ProjectTimelineTurningPointChecks {
    public static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "workstate-turning-point-check-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let source = SourceReference(
            id: "turning-source",
            kind: "conversation",
            label: "Turning-point evidence",
            locator: "/tmp/turning-point.jsonl"
        )
        let project = ProjectRecord(
            id: "turning-project",
            name: "Turning project",
            summary: "A project",
            events: [
                ProjectEvent(
                    id: "turning-project-start",
                    title: "Started",
                    summary: "Started",
                    kind: .projectStarted,
                    loopStage: .intake
                )
            ],
            sourceIDs: [source.id]
        )
        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(
            initial: WorkspaceSnapshot(projects: [project], sources: [source])
        )
        let service = WorkstateService(repository: repository)
        let changeID = "turning-change"
        let timestamp = Date(timeIntervalSince1970: 1_785_000_000)
        let proposal = ProjectTimelineTurningPointProposal(
            id: "turning-marker",
            projectID: project.id,
            title: "Layout model changed",
            beforeMeaning: "The workspace uses a vertical split",
            afterMeaning: "The workspace uses a horizontal split",
            scope: .interaction,
            timestamp: timestamp,
            sourceIDs: [source.id],
            originatingChangeID: changeID
        )
        let marker = try ProjectTimelineTurningPointMapper().map(
            proposal,
            in: ProjectTimelineTurningPointValidationContext(
                projectID: project.id,
                worklineIDs: [],
                changeIDs: [changeID],
                sourceIDs: [source.id]
            )
        )
        try require(marker != nil, "a semantic change maps to a turning point")

        let change = IngestionProjectChange(
            id: changeID,
            projectID: project.id,
            timestamp: timestamp,
            sources: [source],
            title: "Layout changed",
            summary: "The confirmed split direction changed.",
            kind: .decision,
            stage: .confirmation,
            delivery: .unchanged,
            facts: [],
            operations: .init(),
            worklineAction: .none,
            worklineID: "",
            worklineTitle: "",
            worklineObjective: "",
            branchFromWorklineID: "",
            isParallel: false,
            nextFocusedWorklineID: "",
            closureDisposition: .none,
            carryoverTitle: "",
            carryoverSummary: "",
            carryoverQuestions: [],
            taskStartEventID: "unused-task-start",
            contextPatch: nil,
            turningPoint: marker
        )
        _ = try service.applyIngestionChanges(projectID: project.id, changes: [change])
        _ = try service.applyIngestionChanges(projectID: project.id, changes: [change])
        var loaded = try service.snapshot()
        try require(
            loaded.project(id: project.id)?.turningPoints?.count == 1,
            "replaying one ingestion change does not duplicate its turning point"
        )

        let conflicting = ProjectTimelineTurningPoint(
            id: proposal.id,
            projectID: project.id,
            title: "Conflicting marker",
            beforeMeaning: proposal.beforeMeaning,
            afterMeaning: proposal.afterMeaning,
            scope: proposal.scope,
            timestamp: timestamp,
            sourceIDs: proposal.sourceIDs,
            originatingChangeID: changeID
        )
        try expectFailure {
            _ = try ProjectTimelineTurningPointApplication.appending(
                conflicting,
                to: [marker!]
            )
        }

        var legacyObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: repository.paths.state)
        ) as! [String: Any]
        var projects = legacyObject["projects"] as! [[String: Any]]
        projects[0].removeValue(forKey: "turningPoints")
        legacyObject["projects"] = projects
        try JSONSerialization.data(withJSONObject: legacyObject)
            .write(to: repository.paths.state, options: .atomic)
        loaded = try repository.load()
        try require(
            loaded.project(id: project.id)?.turningPoints == nil,
            "legacy project JSON without turning points still decodes"
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw WorkstateStorageError.invalidState(message)
        }
    }

    private static func expectFailure(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch WorkstateStorageError.invalidState {
            return
        }
        throw WorkstateStorageError.invalidState("Expected turning-point check failure")
    }
}
