import Foundation
import WorkstateCore
import WorkstateIngestion

@main
struct WorkstateMigrateV4 {
    static func main() throws {
        let repository = WorkstateRepository()
        try repository.ensureInitialized()
        let service = WorkstateService(repository: repository)
        let badSourceID = "source-019f458c-7bab-79a2-87ba-30393c47d385-019f6ef4-8282-7062-9c07-d3f5a448d262"
        if try service.snapshot().source(id: badSourceID) != nil {
            _ = try service.removeSourceArtifacts(sourceIDs: [badSourceID])
        }

        _ = try repository.update(
            mutation: WorkspaceMutation(
                kind: "workspace.v4-reconcile",
                summary: "Persisted topics and removed the known Workstate-to-Beta misroute"
            )
        ) { snapshot in
            guard let betaIndex = snapshot.projects.firstIndex(where: { $0.id == "reframe-beta" }) else {
                throw WorkstateStorageError.missingProject("reframe-beta")
            }
            let topics = betaTopics()
            for topic in topics where snapshot.projects[betaIndex].topic(id: topic.id) == nil {
                snapshot.projects[betaIndex].topics.append(topic)
            }
            for index in snapshot.projects.indices {
                let activityDates = snapshot.projects[index].events.map(\.timestamp)
                    + snapshot.projects[index].topics.map(\.updatedAt)
                    + [snapshot.projects[index].createdAt]
                if let latest = activityDates.max() {
                    snapshot.projects[index].updatedAt = latest
                    snapshot.projects[index].lastActivityAt = latest
                }
            }
        }

        try backfillRouteBindings(repository: repository)
        _ = try DaemonStatusRepository(root: repository.paths.root).saveIfChanged(
            DaemonSnapshot(activity: .stopped, detail: "后台服务已停止")
        )
        let snapshot = try repository.load()
        let beta = snapshot.project(id: "reframe-beta")
        print("schema=\(snapshot.schemaVersion) betaTopics=\(beta?.topics.count ?? 0) betaEvents=\(beta?.events.count ?? 0)")
    }

    private static func betaTopics() -> [ProjectTopic] {
        let ownerOrigin = date("2026-07-17T07:16:06.909Z")
        let ownerCorrection = date("2026-07-17T07:23:45.318Z")
        let capturedAt = date("2026-07-17T03:38:07.325Z")
        return [
            ProjectTopic(
                id: "beta-backend-batch",
                title: "Beta 后端问题集中讨论",
                summary: "把用例过程中发现的后端能力缺口组织起来，之后与开发集中讨论。",
                status: .captured,
                kind: .backend,
                currentUnderstanding: "零散反馈不足以支持后端判断，需要保留问题起源、用户影响、当前机制和期望变化。",
                proposedDirection: "按真实用例整理证据，并在讨论前压缩成可以直接交接的议题包。",
                deferredReason: "当前优先完成用例，不在内容工作中途切换到后端方案讨论。",
                revisitTrigger: "Beta 后端进入下一轮集中规划时。",
                openQuestions: ["哪些问题属于能力缺口，哪些只是当前交互暴露不足？"],
                notes: [
                    ProjectTopicNote(
                        id: "beta-backend-note-1",
                        timestamp: capturedAt,
                        kind: .origin,
                        title: "议题起源",
                        detail: "在连续编写 Reframe 用例时，出现了多项值得后续与开发集中讨论的后端问题。"
                    )
                ],
                createdAt: capturedAt,
                updatedAt: capturedAt
            ),
            ProjectTopic(
                id: "beta-interaction-later",
                title: "用例中暴露的交互优化",
                summary: "先保存前端体验问题，等内容工作结束后再按完整路径统一优化。",
                status: .captured,
                kind: .frontend,
                currentUnderstanding: "这些问题单独看很小，但可能共同说明某条工作流的状态反馈不清楚。",
                proposedDirection: "保留触发场景和前后操作路径，未来以完整工作流进行走查。",
                deferredReason: "当前没有时间进入实现和视觉调试。",
                revisitTrigger: "用例交付完成并进入下一轮 Beta 前端收束时。",
                openQuestions: ["这些问题是否可以归并为同一条交互原则？"],
                createdAt: capturedAt,
                updatedAt: capturedAt
            ),
            ProjectTopic(
                id: "beta-multitrack-content-grouping",
                title: "多轨、多机位与素材编排方向",
                summary: "讨论粗剪多轨、前置多机位/retake 聚合，以及 Agent 的素材编排顺序。",
                status: .discussing,
                kind: .product,
                currentUnderstanding: "这些内容是待讨论的产品设想，不是已确认方向。它们共同指向素材身份建模、声音约束和粗剪编排能力。",
                proposedDirection: "先厘清多轨承担范围、one take 与 retake 的数据关系，再讨论 Agent 是否采用主线优先和高覆盖后淘汰的编排策略。",
                deferredReason: "当前仍在 Reframe 用例工作中，尚未完成产品与后端可行性讨论。",
                revisitTrigger: "进入 Beta 下一轮产品和后端规划时。",
                openQuestions: [
                    "粗剪多轨应承载到什么程度？",
                    "同一 take 的多机位与 retake 应如何分组、展示和选择？",
                    "声音匹配和主线优先应如何进入 Agent 编排契约？",
                    "素材选择应先高覆盖再淘汰，还是直接追求最少片段？"
                ],
                notes: [
                    ProjectTopicNote(
                        id: "beta-multitrack-owner-origin",
                        timestamp: ownerOrigin,
                        kind: .origin,
                        title: "提出产品设想",
                        detail: "用户提出粗剪多轨、多机位提前绑定、one take/retake 区分、声音匹配和 Agent 编排顺序等待讨论方向。",
                        ownerMessageIDs: ["abf6e260-db31-4951-9695-ca591d0cfe94"]
                    ),
                    ProjectTopicNote(
                        id: "beta-multitrack-owner-correction",
                        timestamp: ownerCorrection,
                        kind: .userCorrection,
                        title: "纠正状态判断",
                        detail: "这些是需要继续讨论的议题，不是已经确认的产品内容。",
                        ownerMessageIDs: [
                            "6aaef807-2a1e-4ddb-b3b5-727bd875b20e",
                            "83fcc3d2-f7fb-4e2a-b586-210209cb2e97"
                        ]
                    )
                ],
                createdAt: ownerOrigin,
                updatedAt: ownerCorrection
            )
        ]
    }

    private static func backfillRouteBindings(repository: WorkstateRepository) throws {
        let snapshot = try repository.load()
        let sources = Dictionary(uniqueKeysWithValues: snapshot.sources.map { ($0.id, $0) })
        var latest: [String: (timestamp: Date, turnID: String, projectID: String)] = [:]
        for project in snapshot.projects {
            for event in project.events {
                for sourceID in event.sourceIDs {
                    guard let source = sources[sourceID], !source.threadID.isEmpty else { continue }
                    let turnID = source.turnIDs.last ?? event.id
                    if (latest[source.threadID]?.timestamp ?? .distantPast) < event.timestamp {
                        latest[source.threadID] = (event.timestamp, turnID, project.id)
                    }
                }
            }
        }
        let scanner = CodexSessionScanner(runtimeRoot: repository.paths.root)
        for (threadID, binding) in latest {
            try scanner.recordRoute(
                threadID: threadID,
                turnID: binding.turnID,
                projectID: binding.projectID
            )
        }
    }

    private static func date(_ value: String) -> Date {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? style.parse(value)) ?? Date(timeIntervalSince1970: 0)
    }
}
