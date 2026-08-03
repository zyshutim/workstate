import Foundation
import WorkstateCore

public enum ContextHandoffContractChecks {
    public static func run() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let workspaceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_900)
        let sourceSpans = [
            ConversationSourceSpan(kind: .userMessage, startOffset: 121, endOffset: 150),
            ConversationSourceSpan(kind: .assistantCompletion, startOffset: 160, endOffset: 220)
        ]
        let source = SourceReference(
            id: "handoff-source",
            kind: "conversation",
            label: "Context handoff source",
            locator: "/tmp/context-handoff.jsonl",
            threadID: "thread-1",
            turnIDs: ["turn-7"],
            contentHash: "hash-1",
            provider: "codex",
            startOffset: 120,
            endOffset: 240,
            messageSpans: sourceSpans
        )
        let activeTask = TaskRecord(
            id: "active-workline",
            title: "active 工作线",
            objective: "Keep the current project moving",
            status: .active,
            currentStage: .implementation,
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
            branchedFromEventID: "start"
        )
        let waitingTask = TaskRecord(
            id: "waiting-workline",
            title: "waiting 工作线",
            objective: "Wait for confirmation",
            status: .waiting,
            currentStage: .audit,
            startedAt: Date(timeIntervalSince1970: 1_700_000_050),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            branchedFromEventID: "start"
        )
        let parkedTask = TaskRecord(
            id: "parked-workline",
            title: "parked 工作线",
            objective: "This workline is parked",
            status: .parked,
            currentStage: .intake,
            startedAt: Date(timeIntervalSince1970: 1_700_000_020),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            branchedFromEventID: "start"
        )
        let completedTask = TaskRecord(
            id: "completed-workline",
            title: "completed 工作线",
            objective: "This workline is done",
            status: .completed,
            currentStage: .completed,
            startedAt: Date(timeIntervalSince1970: 1_700_000_010),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            completedAt: Date(timeIntervalSince1970: 1_700_000_500),
            branchedFromEventID: "start"
        )
        let activeEvent = ProjectEvent(
            id: "active-delta",
            taskID: activeTask.id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_350),
            title: "Active delta",
            summary: "The active workline changed.",
            kind: .implementation,
            loopStage: .implementation,
            facts: ["Active scope changed"],
            sourceIDs: [source.id]
        )
        let waitingEvent = ProjectEvent(
            id: "waiting-delta",
            taskID: waitingTask.id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_250),
            title: "Waiting delta",
            summary: "The waiting workline needs another check.",
            kind: .contextUpdate,
            loopStage: .audit,
            sourceIDs: [source.id]
        )
        let turningPoints = [
            ProjectTimelineTurningPoint(
                id: "project-turning",
                projectID: "contract-project",
                title: "Project direction shifted",
                beforeMeaning: "The project had an older contract shape.",
                afterMeaning: "The project now uses the contract v3 shape.",
                scope: .project,
                timestamp: Date(timeIntervalSince1970: 1_700_000_500),
                sourceIDs: [source.id],
                originatingChangeID: "change-project"
            ),
            ProjectTimelineTurningPoint(
                id: "waiting-turning",
                projectID: "contract-project",
                worklineID: waitingTask.id,
                title: "Waiting workline clarified",
                beforeMeaning: "The waiting workline was too open ended.",
                afterMeaning: "The waiting workline now has a concrete stop point.",
                scope: .workline,
                timestamp: Date(timeIntervalSince1970: 1_700_000_400),
                sourceIDs: [source.id],
                originatingChangeID: "change-waiting"
            ),
            ProjectTimelineTurningPoint(
                id: "active-turning",
                projectID: "contract-project",
                worklineID: activeTask.id,
                title: "Active workline narrowed",
                beforeMeaning: "The active workline was broad.",
                afterMeaning: "The active workline is now focused.",
                scope: .workline,
                timestamp: Date(timeIntervalSince1970: 1_700_000_300),
                sourceIDs: [source.id],
                originatingChangeID: "change-active"
            ),
            ProjectTimelineTurningPoint(
                id: "parked-turning",
                projectID: "contract-project",
                worklineID: parkedTask.id,
                title: "Parked workline parked",
                beforeMeaning: "The parked workline still looked active.",
                afterMeaning: "The parked workline is no longer relevant.",
                scope: .workline,
                timestamp: Date(timeIntervalSince1970: 1_700_000_200),
                sourceIDs: [source.id],
                originatingChangeID: "change-parked"
            ),
            ProjectTimelineTurningPoint(
                id: "completed-turning",
                projectID: "contract-project",
                worklineID: completedTask.id,
                title: "Completed workline finished",
                beforeMeaning: "The completed workline was still treated as open.",
                afterMeaning: "The completed workline is closed out.",
                scope: .workline,
                timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                sourceIDs: [source.id],
                originatingChangeID: "change-completed"
            )
        ]
        let cognitionSection = ProjectCognitionSection(
            id: "project-picture",
            title: "Project picture",
            body: "The canonical v3 project picture.",
            purpose: "Provide the durable project model.",
            coverage: ProjectCognitionCoverage.allCases,
            sourceIDs: [source.id],
            order: 0
        )
        let resolvedRevision = ProjectCognitionRevision(
            id: "resolved-cognition",
            operation: .update,
            beforeSections: [cognitionSection],
            afterSections: [cognitionSection],
            baseVersion: 1,
            rationale: "Resolved cognition history must stay out of handoff.",
            sourceIDs: [source.id],
            status: .accepted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            resolvedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let pendingRevision = ProjectCognitionRevision(
            id: "pending-cognition",
            operation: .update,
            beforeSections: [cognitionSection],
            afterSections: [cognitionSection],
            baseVersion: 2,
            rationale: "Pending cognition remains explicitly unconfirmed.",
            sourceIDs: [source.id]
        )
        let project = ProjectRecord(
            id: "contract-project",
            name: "Contract project",
            summary: "Minimal contract fixture",
            status: .active,
            updatedAt: workspaceUpdatedAt,
            lastActivityAt: workspaceUpdatedAt,
            context: ProjectContext(
                cognition: ProjectCognitionDocument(
                    state: .confirmed,
                    version: 2,
                    sections: [cognitionSection],
                    revisions: [resolvedRevision, pendingRevision],
                    generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    confirmedAt: Date(timeIntervalSince1970: 1_700_000_050),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
                ),
                purpose: "Exercise the handoff contract.",
                inScope: ["Check the v3 context handoff contract"],
                outOfScope: ["Completed worklines"],
                understanding: [
                    ContextStatement(
                        text: "The current contract should stay precise.",
                        status: .confirmed,
                        sourceIDs: [source.id]
                    )
                ],
                acceptedDecisions: [
                    DecisionRecord(
                        text: "Use the v3 context handoff shape.",
                        status: .confirmed,
                        sourceIDs: [source.id]
                    )
                ],
                forbiddenDirections: ["Do not leak completed work into the handoff"]
            ),
            tasks: [activeTask, waitingTask, parkedTask, completedTask],
            events: [activeEvent, waitingEvent],
            turningPoints: turningPoints,
            sourceIDs: [source.id]
        )
        let workspace = WorkspaceSnapshot(
            updatedAt: workspaceUpdatedAt,
            projects: [project],
            sources: [source]
        )

        let snapshot = try ContextSnapshotBuilder().project(
            project.id,
            from: workspace,
            generatedAt: generatedAt
        )

        try require(snapshot.schemaVersion == 3, "schema version defaults to three")
        try require(
            snapshot.worklines.map(\.id) == [activeTask.id, waitingTask.id],
            "project snapshot keeps active and waiting worklines only"
        )
        try require(
            snapshot.worklines.contains(where: { $0.id == waitingTask.id && $0.status == .waiting }),
            "waiting workline is included"
        )
        try require(
            !snapshot.worklines.contains(where: { $0.id == parkedTask.id || $0.id == completedTask.id }),
            "parked and completed worklines are excluded"
        )
        try require(
            snapshot.turningPoints.map(\.id) == turningPoints.map(\.id),
            "project snapshot keeps recent project turning points across completed worklines"
        )
        try require(
            snapshot.project.cognition?.pendingRevisions.map(\.id) == [pendingRevision.id],
            "handoff cognition excludes resolved revision history"
        )
        try require(snapshot.sources.count == 1, "snapshot keeps one precise source")
        let capturedSource = try requireElement(snapshot.sources.first, "source pointer")
        try require(capturedSource.provider == source.provider, "source provider is retained")
        try require(capturedSource.startOffset == source.startOffset, "source start offset is retained")
        try require(capturedSource.endOffset == source.endOffset, "source end offset is retained")
        try require(capturedSource.messageSpans == sourceSpans, "source message spans are retained")

        let markdown = ContextSnapshotMarkdownRenderer().render(snapshot)
        try require(markdown.contains("Context Contract v3"), "markdown names the v3 contract")
        try require(markdown.contains("范围：project"), "markdown includes scope")
        try require(markdown.contains("生成时间"), "markdown includes generation time")
        try require(markdown.contains("数据更新时间"), "markdown includes workspace update time")
        try require(markdown.contains("关键转折"), "markdown includes turning points")
        try require(markdown.contains(cognitionSection.body), "markdown includes canonical cognition")
        try require(markdown.contains(pendingRevision.rationale), "markdown labels pending cognition")
        try require(!markdown.contains(resolvedRevision.rationale), "markdown omits resolved cognition history")
        try require(markdown.contains("waiting 工作线"), "markdown includes waiting workline")
        try require(markdown.contains("Provider：codex"), "markdown includes source provider")
        try require(markdown.contains("字节范围：120..<240"), "markdown includes source offsets")
        try require(
            markdown.contains("消息范围：userMessage 121..<150; assistantCompletion 160..<220"),
            "markdown includes source spans"
        )
        try require(!markdown.contains(completedTask.title), "markdown omits completed worklines")

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-context-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }
        let projectHandoff = try ContextHandoffExporter(root: exportRoot).export(snapshot)
        try require(
            projectHandoff.url.lastPathComponent == "contract-project.md",
            "project handoff keeps the stable project filename"
        )
        try require(
            projectHandoff.sourceIndexURL.lastPathComponent == "contract-project.sources.json",
            "project handoff writes a separate source index"
        )
        let exportedMarkdown = try String(contentsOf: projectHandoff.url, encoding: .utf8)
        try require(
            exportedMarkdown.contains(projectHandoff.sourceIndexURL.path),
            "compact handoff points to its exact source index"
        )
        try require(
            !exportedMarkdown.contains(source.locator),
            "compact handoff does not inline repeated source paths"
        )
        let sourceIndex = try WorkstateCoding.makeDecoder().decode(
            ContextHandoffSourceIndex.self,
            from: Data(contentsOf: projectHandoff.sourceIndexURL)
        )
        try require(sourceIndex.sources == snapshot.sources, "source sidecar preserves exact pointers")

        let taskSnapshot = try ContextSnapshotBuilder().task(
            activeTask.id,
            from: workspace,
            generatedAt: generatedAt
        )
        let taskHandoff = try ContextHandoffExporter(root: exportRoot).export(taskSnapshot)
        try require(
            taskHandoff.url.lastPathComponent
                == "contract-project--task--active-workline.md",
            "task handoff cannot overwrite the project handoff"
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

    private static func requireElement<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw WorkstateStorageError.invalidState(message)
        }
        return value
    }
}
