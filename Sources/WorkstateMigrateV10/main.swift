import Foundation
import WorkstateCore
import WorkstateIngestion

@main
struct WorkstateMigrateV10 {
    private static let threadID = "019f17a2-16de-7e70-90df-ee721bc186f6"
    private static let targetProjectID = "jianying-agent-research"
    private static let turnIDs = [
        "019fa195-74d3-7db0-8aa0-b3e92565118f",
        "019fa1a2-708d-72f1-87b1-e36027a8f857",
        "019fa1af-ec77-7d50-be87-c4a965c8793a",
        "019fa229-1439-7fd3-93ee-6db0e8f3f5a7",
        "019fa22b-69b5-73d0-bbf8-00fd59af1acc",
        "019fa24f-23ea-77d3-b907-a0c63e54698d",
        "019fa25c-1b1b-73d2-8828-a8bcc1e6061e",
        "019fa27e-46ad-7f20-b0d4-0966e448fd96",
        "019fa285-dea8-7bd3-b6b0-629f336669c3",
        "019fa287-3908-76c1-ae0f-a8d2f7ad1207",
        "019fa291-46f4-7ed2-a001-c0114ee45e04",
        "019fa293-b3bc-7042-8b31-51b4e06d2b11",
        "019fa2a4-4186-7af0-898a-2e70c8b78e5a",
        "019fa2a6-70c9-7ee3-a2cc-c00935c9f074"
    ]
    private static let movedDecisionIDs = [
        "reframe-beta-decision-original-sound-anchor-test"
    ]
    private static let movedRevisionIDs = [
        "context-revision-batch-6d22b9e7a2d5cb63690f-83c0456a31e7f29aa6a0"
    ]
    private static let movedUnderstandingIDs = [
        "rebuild-understanding-reframe-beta-7",
        "rebuild-understanding-reframe-beta-8"
    ]
    private static let movedEventIDs = [
        "delta-batch-6d22b9e7a2d5cb63690f-83c0456a31e7f29aa6a0"
    ]

    static func main() throws {
        let repository = WorkstateRepository()
        try repository.ensureInitialized()
        let service = WorkstateService(repository: repository)
        if try service.snapshot().project(id: targetProjectID) == nil {
            _ = try service.createProject(
                ProjectCreateInput(
                    id: targetProjectID,
                    name: "剪映 Agent · 产品调研",
                    summary: "通过真实剪辑用例评估剪映 Agent 的能力边界与使用路径。",
                    purpose: "评估剪映 Agent 在不同素材量、开放式指令、文稿驱动、多机位与 180 分钟素材限制下的剪辑能力，并沉淀测试结论。",
                    accent: .green,
                    position: GraphPosition(x: 880, y: 520)
                )
            )
        }

        let sourceIDs = Set(turnIDs.map { "source-\(threadID)-\($0)" })
        var movedArtifactCount = 0
        _ = try repository.update(
            mutation: WorkspaceMutation(
                kind: "workspace.v10-jianying-project-split",
                summary: "Moved Jianying Agent research evidence out of Reframe Beta",
                projectID: targetProjectID
            )
        ) { snapshot in
            guard let betaIndex = snapshot.projects.firstIndex(where: { $0.id == "reframe-beta" }) else {
                throw WorkstateStorageError.missingProject("reframe-beta")
            }
            guard let researchIndex = snapshot.projects.firstIndex(where: { $0.id == targetProjectID }) else {
                throw WorkstateStorageError.missingProject(targetProjectID)
            }

            var beta = snapshot.projects[betaIndex]
            var research = snapshot.projects[researchIndex]
            let phaseStartedAt = Date(timeIntervalSince1970: 1_785_122_354.387)
            let decisionIDs = Set(movedDecisionIDs)
            let revisionIDs = Set(movedRevisionIDs)
            let understandingIDs = Set(movedUnderstandingIDs)
            let eventIDs = Set(movedEventIDs)
            let movedDecisions = beta.context.acceptedDecisions.filter { decisionIDs.contains($0.id) }
            let movedRevisions = beta.context.revisions.filter { revisionIDs.contains($0.id) }
            let movedUnderstanding = beta.context.understanding.filter { understandingIDs.contains($0.id) }
            var movedEvents = beta.events.filter { eventIDs.contains($0.id) }
            movedArtifactCount = movedDecisions.count + movedRevisions.count
                + movedUnderstanding.count + movedEvents.count

            beta.context.acceptedDecisions.removeAll { decisionIDs.contains($0.id) }
            beta.context.revisions.removeAll { revisionIDs.contains($0.id) }
            beta.context.understanding.removeAll { understandingIDs.contains($0.id) }
            beta.events.removeAll { eventIDs.contains($0.id) }
            beta.sourceIDs.removeAll(where: sourceIDs.contains)
            for taskIndex in beta.tasks.indices {
                beta.tasks[taskIndex].sourceIDs.removeAll(where: sourceIDs.contains)
            }
            beta.summary = "Beta 已转为以 RC 前端为基线的 Figma 交互母版；A1、A2 与 B 采用左右布局，Storyboard 树和 SubBeat 素材分段交互已按最终规则收束并通过静态检查，尚待真实客户端完整验收与生产实现。"
            beta.context.currentSummary = beta.summary
            let betaActivity = beta.events.map(\.timestamp)
                + beta.topics.map(\.updatedAt)
                + [beta.createdAt]
            beta.lastActivityAt = betaActivity.max() ?? beta.createdAt
            beta.updatedAt = beta.lastActivityAt

            for decision in movedDecisions
                where research.context.acceptedDecisions.allSatisfy({ $0.id != decision.id }) {
                research.context.acceptedDecisions.append(decision)
            }
            for revision in movedRevisions
                where research.context.revisions.allSatisfy({ $0.id != revision.id }) {
                research.context.revisions.append(revision)
            }
            for statement in movedUnderstanding
                where research.context.understanding.allSatisfy({ $0.id != statement.id }) {
                research.context.understanding.append(statement)
            }
            for index in movedEvents.indices {
                movedEvents[index].taskID = nil
                movedEvents[index].parentEventIDs = []
            }
            for event in movedEvents where research.events.allSatisfy({ $0.id != event.id }) {
                research.events.append(event)
            }
            if let projectStartIndex = research.events.firstIndex(where: {
                $0.kind == .projectStarted
            }) {
                research.events[projectStartIndex].timestamp = phaseStartedAt
                research.createdAt = phaseStartedAt
            }
            let knownSourceIDs = Set(snapshot.sources.map(\.id)).intersection(sourceIDs)
            research.sourceIDs = Array(Set(research.sourceIDs).union(knownSourceIDs)).sorted()
            if movedArtifactCount > 0 {
                research.summary = "已确定剪映原声剪辑的首组真实用例与锚点式测试方法，正在继续验证长素材、多机位、文稿驱动和开放式指令下的能力边界。"
                research.context.currentSummary = research.summary
            }
            let researchActivity = research.events.map(\.timestamp)
                + research.topics.map(\.updatedAt)
                + [research.createdAt]
            research.lastActivityAt = researchActivity.max() ?? research.createdAt
            research.updatedAt = research.lastActivityAt

            snapshot.projects[betaIndex] = beta
            snapshot.projects[researchIndex] = research
        }

        let index = try ConversationSourceIndex(
            databaseURL: repository.paths.root.appendingPathComponent(
                "conversation-source-index.sqlite"
            )
        )
        let pointerIDs = turnIDs.map {
            ConversationSourcePointerID(provider: "codex", threadID: threadID, turnID: $0)
        }
        let reassigned = try index.reassignCompletedPointers(pointerIDs, to: targetProjectID)
        let scanner = CodexSessionScanner(runtimeRoot: repository.paths.root)
        try scanner.recordRoute(
            threadID: threadID,
            turnID: turnIDs.first!,
            projectID: targetProjectID
        )
        try scanner.recordRoute(
            threadID: threadID,
            turnID: turnIDs.last!,
            projectID: targetProjectID
        )
        let settingsRepository = WorkstateSettingsRepository(root: repository.paths.root)
        var settings = try settingsRepository.load(workspaceHasProjects: true)
        if !settings.liveMonitoringEnabled, settings.liveMonitoringStartedAt != nil {
            settings.liveMonitoringStartedAt = nil
            try settingsRepository.save(settings)
        }

        let output = MigrationOutput(
            projectID: targetProjectID,
            reassignedPointers: reassigned,
            movedArtifacts: movedArtifactCount
        )
        FileHandle.standardOutput.write(try WorkstateCoding.makeEncoder().encode(output))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private struct MigrationOutput: Codable {
    var projectID: String
    var reassignedPointers: Int
    var movedArtifacts: Int
}
