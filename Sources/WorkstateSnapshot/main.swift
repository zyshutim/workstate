import AppKit
import SwiftUI
import WorkstateCore
import WorkstateUI

@main
struct WorkstateSnapshot {
    @MainActor
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let mode = arguments.first ?? "event"
        let output = arguments.dropFirst().first ?? "/tmp/workstate-\(mode).png"
        let appearanceName = arguments.dropFirst(2).first ?? "light"
        let sourceName = arguments.dropFirst(3).first ?? "bootstrap"
        let projectID = arguments.dropFirst(4).first ?? "reframe-multicam"
        let focusedProjectID = arguments.dropFirst(5).first
        let selectedTaskID = arguments.dropFirst(6).first
        let selectedEventID = arguments.dropFirst(7).first
        let snapshotTopicID = arguments.dropFirst(8).first
        guard let appearance = SnapshotAppearance(rawValue: appearanceName) else {
            throw SnapshotError.invalidAppearance(appearanceName)
        }
        guard let source = SnapshotSource(rawValue: sourceName) else {
            throw SnapshotError.invalidSource(sourceName)
        }
        NSApplication.shared.appearance = NSAppearance(named: appearance.appKitName)

        let temporaryRoot = source != .live
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("workstate-snapshot-\(UUID().uuidString)", isDirectory: true)
            : nil
        defer {
            if let temporaryRoot {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
        }
        let repository = temporaryRoot.map {
            WorkstateRepository(paths: WorkstatePaths(root: $0))
        } ?? WorkstateRepository()
        if source != .live {
            let fixture = mode == "brief"
                ? dailyBriefFixture(WorkstateBootstrap.makeInitialState())
                : WorkstateBootstrap.makeInitialState()
            let initial: WorkspaceSnapshot
            if source == .onboarding {
                initial = WorkspaceSnapshot()
            } else {
                initial = source == .readme ? try readmeFixture(fixture) : fixture
            }
            try repository.ensureInitialized(initial: initial)
        } else {
            try repository.ensureInitialized()
        }
        if mode == "brief" {
            try seedDailyBriefNarrative(repository: repository)
        }
        if mode == "owner" {
            try ProjectOwnerConversationRepository(root: repository.paths.root).save(
                ProjectOwnerConversation(
                    projectID: projectID,
                    messages: [
                        ProjectOwnerMessage(
                            role: .user,
                            text: "用例过程中发现的后端问题先怎么组织，后面和开发集中讨论会更有效？",
                            timestamp: Date(timeIntervalSince1970: 1_784_258_142)
                        ),
                        ProjectOwnerMessage(
                            role: .owner,
                            text: "先不要急着写解决方案，按四项组织：\n\n- **问题起源**：在哪个用例里出现\n- **用户影响**：阻断还是体验降级\n- **当前机制**：现在实际怎么工作\n- **期望变化**：希望后端承担什么\n\n最后再判断它属于能力缺口，还是交互暴露不足。",
                            timestamp: Date(timeIntervalSince1970: 1_784_258_202)
                        )
                    ]
                )
            )
        }
        if mode == "global-chat" {
            try GlobalConversationRepository(root: repository.paths.root).save(
                GlobalConversation(
                    messages: [
                        GlobalChatMessage(
                            role: .user,
                            text: "素材图谱里这个交互先记成议题，等我有空再继续。",
                            projectID: "reframe-material-graph",
                            projectName: "Reframe · 素材图谱"
                        ),
                        GlobalChatMessage(
                            role: .owner,
                            text: "我会先保留你的原话，并把它放进素材图谱项目的待讨论议题。现在不会把它当成已确认需求。",
                            projectID: "reframe-material-graph",
                            projectName: "Reframe · 素材图谱"
                        )
                    ]
                )
            )
        }
        if mode == "collaboration" {
            try CollaborationProfileRepository(root: repository.paths.root).save(
                CollaborationProfile(
                    entries: [
                        CollaborationProfileEntry(
                            id: "direct-language",
                            kind: .preference,
                            status: .active,
                            title: "简洁、直接、使用现有术语",
                            detail: "先说结论与可见后果，避免无必要复述。",
                            evidence: ["你能不能说简单点，我看不进去"]
                        ),
                        CollaborationProfileEntry(
                            id: "evidence-first",
                            kind: .rule,
                            status: .active,
                            title: "先看真实状态再下结论",
                            detail: "区分已验证事实、推断和待确认内容。"
                        ),
                        CollaborationProfileEntry(
                            id: "possible-pattern",
                            kind: .loop,
                            status: .candidate,
                            title: "候选：短反馈回路",
                            detail: "先做代表性样本，再决定是否扩展。"
                        )
                    ]
                )
            )
        }
        if mode == "cognition" {
            try seedCognitionFixture(repository: repository, projectID: projectID)
        }
        let model = WorkstateViewModel(repository: repository)

        if mode != "graph" && mode != "projects" && mode != "reviews" && mode != "brief" {
            model.selectProject(projectID)
            if (mode == "event" || mode == "detail"),
               projectID == "reframe-multicam" || projectID == "atlas-multicam" {
                model.selectEvent("mc-preview-model")
            }
            if let selectedTaskID, !selectedTaskID.isEmpty {
                model.selectTask(selectedTaskID)
            }
            if let selectedEventID, !selectedEventID.isEmpty {
                model.selectTaskEvent(selectedEventID)
            }
            if mode == "context" {
                model.isContextExpanded = true
            }
        }
        if mode == "reviews" {
            model.isReviewInboxPresented = true
            model.selectedReviewID = model.pendingReviews.first?.id
        }
        if mode == "brief" {
            model.presentDailyBrief()
        }
        if mode == "global-chat" {
            model.presentGlobalChat()
        }
        if mode == "collaboration" {
            model.presentCollaborationProfile()
        }

        let view = WorkstateRootView(model: model)
            .frame(width: model.preferredWidth, height: model.preferredHeight)
            .environment(\.colorScheme, appearance.colorScheme)
            .workstateSnapshotRendering()
            .workstateSnapshotFocusedProject(focusedProjectID)
            .workstateSnapshotWorkspace(
                page: mode == "owner" ? "owner" : (mode == "topics" || mode == "topic" ? "topics" : nil),
                topicID: mode == "topic" ? (snapshotTopicID ?? "website-docs-readability") : nil
            )
            .workstateSnapshotProgressMode(
                mode == "branch-history" ? "branches-history" : (mode == "branch" ? "branches" : nil)
            )
        let renderer = ImageRenderer(content: view)
        if source == .onboarding {
            RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        }
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: model.preferredWidth, height: model.preferredHeight)

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
        print(output)
    }

    private static func seedCognitionFixture(
        repository: WorkstateRepository,
        projectID: String
    ) throws {
        _ = try repository.update(
            mutation: WorkspaceMutation(kind: "snapshot.cognition", summary: "Seed cognition fixture")
        ) { snapshot in
            guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
                throw WorkstateStorageError.missingProject(projectID)
            }
            guard let sourceID = snapshot.projects[projectIndex].sourceIDs.first
                ?? snapshot.sources.first?.id else {
                throw SnapshotError.renderFailed
            }
            let canonical = ProjectCognitionSection(
                id: "product-picture",
                title: "产品全貌",
                body: """
                **已确认**：Reframe 通过素材图谱、故事板和时间线协同组织剪辑事实。

                - Agent 操作业务对象，但不替代事实来源。
                - 素材与时间线继续持有可验证的剪辑事实。
                """,
                purpose: "保持项目的产品模型、设计原则和当前阶段一致",
                inclusionRules: ["项目级模型与稳定设计原则"],
                exclusionRules: ["普通任务进度与临时调试"],
                updateTriggers: ["产品模型或整体阶段发生变化"],
                coverage: ProjectCognitionCoverage.allCases,
                sourceIDs: [sourceID],
                order: 0
            )
            let proposed = ProjectCognitionSection(
                id: canonical.id,
                title: canonical.title,
                body: """
                **Owner 判断**：候选池已经成为连接素材理解与编排决策的关键对象。

                - 素材图谱负责组织可验证事实。
                - 故事板负责表达创作意图。
                - 候选池连接理解与选择，时间线承载最终编排。
                """,
                purpose: canonical.purpose,
                inclusionRules: canonical.inclusionRules,
                exclusionRules: canonical.exclusionRules,
                updateTriggers: canonical.updateTriggers,
                coverage: canonical.coverage,
                sourceIDs: [sourceID],
                order: 0
            )
            snapshot.projects[projectIndex].context.cognition = ProjectCognitionDocument(
                state: .confirmed,
                version: 1,
                sections: [canonical],
                revisions: [
                    ProjectCognitionRevision(
                        id: "snapshot-cognition-revision",
                        operation: .update,
                        beforeSections: [canonical],
                        afterSections: [proposed],
                        baseVersion: 1,
                        rationale: "候选池已经成为稳定产品对象，需要进入项目认知。",
                        sourceIDs: [sourceID]
                    )
                ],
                confirmedAt: Date(),
                updatedAt: Date()
            )
        }
    }

    private static func dailyBriefFixture(_ source: WorkspaceSnapshot) -> WorkspaceSnapshot {
        var snapshot = source
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let dayStart = calendar.startOfDay(for: yesterday)
        let beforeInterval = dayStart.addingTimeInterval(-1)
        let morning = calendar.date(byAdding: .hour, value: 10, to: dayStart) ?? dayStart
        let afternoon = calendar.date(byAdding: .hour, value: 15, to: dayStart) ?? dayStart
        let evening = calendar.date(byAdding: .hour, value: 18, to: dayStart) ?? dayStart

        if let index = snapshot.projects.firstIndex(where: { $0.id == "reframe-multicam" }) {
            let projectStart = snapshot.projects[index].events.first?.id ?? "project-start"
            snapshot.projects[index].tasks = snapshot.projects[index].tasks.map { task in
                var completed = task
                completed.status = .completed
                completed.updatedAt = beforeInterval
                completed.completedAt = beforeInterval
                return completed
            }
            let task = TaskRecord(
                id: "daily-runtime-canary",
                title: "前台验证会话监听",
                objective: "确认空闲内存、文件读取和模型调用次数保持稳定",
                status: .active,
                accent: .green,
                currentStage: .verification,
                startedAt: morning,
                updatedAt: evening,
                branchedFromEventID: projectStart
            )
            snapshot.projects[index].tasks.append(task)
            snapshot.projects[index].events.append(contentsOf: [
                ProjectEvent(
                    id: "daily-event-driven-ingestion",
                    taskID: task.id,
                    timestamp: afternoon,
                    title: "事件驱动监听通过隔离测试",
                    summary: "400 个模拟会话只在首次建立索引，之后仅处理发生变化的文件。",
                    kind: .verification,
                    loopStage: .verification,
                    parentEventIDs: [projectStart],
                    delivery: DeliverySnapshot(stage: .checked)
                ),
                ProjectEvent(
                    id: "daily-no-automatic-retry",
                    timestamp: evening,
                    title: "中断后停止自动重试",
                    summary: "Router 和 Owner 的处理阶段持久化，失败片段需要显式重排。",
                    kind: .decision,
                    loopStage: .confirmation,
                    parentEventIDs: ["daily-event-driven-ingestion"]
                )
            ])
            snapshot.projects[index].topics.append(
                ProjectTopic(
                    id: "daily-foreground-canary",
                    title: "完成真实前台 canary",
                    summary: "恢复后台服务前需要完成真实前台验证。",
                    disposition: .awaitingVerification,
                    currentUnderstanding: "后台保持关闭，等待真实前台验证。",
                    updatedAt: evening
                )
            )
            snapshot.projects[index].updatedAt = evening
            snapshot.projects[index].lastActivityAt = evening
        }

        if let index = snapshot.projects.firstIndex(where: { $0.id == "reframe-material-graph" }) {
            let projectStart = snapshot.projects[index].events.first?.id ?? "project-start"
            snapshot.projects[index].tasks = snapshot.projects[index].tasks.map { task in
                var completed = task
                completed.status = .completed
                completed.updatedAt = beforeInterval
                completed.completedAt = beforeInterval
                return completed
            }
            snapshot.projects[index].events.append(
                ProjectEvent(
                    id: "daily-brief-direction",
                    timestamp: evening,
                    title: "日报结构完成数据建模",
                    summary: "进展、已确立、尚未收束和接手点均保留原始节点定位。",
                    kind: .implementation,
                    loopStage: .implementation,
                    parentEventIDs: [projectStart],
                    delivery: DeliverySnapshot(stage: .changed)
                )
            )
            snapshot.projects[index].updatedAt = evening
            snapshot.projects[index].lastActivityAt = evening
        }
        snapshot.updatedAt = evening
        return snapshot
    }

    private static func seedDailyBriefNarrative(repository: WorkstateRepository) throws {
        let briefs = DailyBriefRepository(root: repository.paths.root)
        guard let latest = try briefs.synchronize(workspace: repository.load()).last else { return }
        let summaries = latest.projects.map { project in
            let summary: String
            switch project.projectID {
            case "reframe-multicam":
                summary = "会话监听已经改成事件驱动，并通过大规模隔离测试。失败片段不再自动重试，后台服务继续保持关闭，等待前台 canary 验证。"
            case "reframe-material-graph":
                summary = "工作摘要的数据结构已经确定，进展、决定、未收束问题和接手点都保留原始节点定位，同时继续沿用多机位已经确认的交互语义。"
            default:
                summary = project.progress.first?.detail ?? project.confirmed.first?.detail ?? "当天项目状态发生了有效变化。"
            }
            return DailyProjectNarrative(projectID: project.projectID, summary: summary)
        }
        let narrative = DailyBriefNarrative(
            sourceRevision: latest.sourceRevision,
            overview: "当天的工作集中在 Workstate 后台可靠性和摘要能力。事件驱动监听通过隔离验证，摘要数据也完成建模；后台服务暂不恢复，先等待真实前台运行确认。",
            projectSummaries: summaries,
            nextStep: "完成 Workstate 前台 canary，确认内存、文件读取和模型调用保持稳定，再决定是否恢复后台监听。"
        )
        _ = try briefs.applyNarrative(narrative, to: latest.dateKey)
    }

    private static func readmeFixture(_ snapshot: WorkspaceSnapshot) throws -> WorkspaceSnapshot {
        let data = try WorkstateCoding.makeEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: data)
        let sanitized = sanitizeReadmeValue(object)
        let sanitizedData = try JSONSerialization.data(withJSONObject: sanitized)
        return try WorkstateCoding.makeDecoder().decode(WorkspaceSnapshot.self, from: sanitizedData)
    }

    private static func sanitizeReadmeValue(_ value: Any) -> Any {
        switch value {
        case let string as String:
            if string.hasPrefix("codex://threads/") {
                return "codex://threads/demo-session"
            }
            return string
                .replacingOccurrences(of: "Reframe", with: "Atlas")
                .replacingOccurrences(of: "reframe", with: "atlas")
                .replacingOccurrences(of: "Claude 会话", with: "协作会话")
                .replacingOccurrences(of: "Claude", with: "协作会话")
        case let array as [Any]:
            return array.map(sanitizeReadmeValue)
        case let dictionary as [String: Any]:
            return dictionary.mapValues(sanitizeReadmeValue)
        default:
            return value
        }
    }
}

private enum SnapshotError: LocalizedError {
    case renderFailed
    case invalidAppearance(String)
    case invalidSource(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            "Could not render Workstate snapshot"
        case let .invalidAppearance(value):
            "Unsupported appearance '\(value)'; expected light or dark"
        case let .invalidSource(value):
            "Unsupported source '\(value)'; expected bootstrap, readme, onboarding, or live"
        }
    }
}

private enum SnapshotSource: String {
    case bootstrap
    case readme
    case onboarding
    case live
}

private enum SnapshotAppearance: String {
    case light
    case dark

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
