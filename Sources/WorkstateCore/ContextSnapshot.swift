import Foundation

public enum ContextSnapshotScopeKind: String, Codable, Sendable {
    case project
    case task
    case thread
}

public struct ContextSnapshotScope: Codable, Equatable, Sendable {
    public var kind: ContextSnapshotScopeKind
    public var id: String
    public var resolvedProjectID: String
    public var resolvedTaskID: String?

    public init(
        kind: ContextSnapshotScopeKind,
        id: String,
        resolvedProjectID: String,
        resolvedTaskID: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.resolvedProjectID = resolvedProjectID
        self.resolvedTaskID = resolvedTaskID
    }
}

public struct ContextSnapshotProject: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var status: ProjectStatus
    public var summary: String
    public var cognitionState: ProjectCognitionState
    public var cognition: ContextSnapshotCognition?
}

public struct ContextSnapshotCognition: Codable, Equatable, Sendable {
    public var version: Int
    public var sections: [ProjectCognitionSection]
    public var pendingRevisions: [ProjectCognitionRevision]
    public var confirmedAt: Date
    public var updatedAt: Date
}

public struct ContextSnapshotDelta: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Date
    public var title: String
    public var summary: String
    public var kind: EventKind
    public var stage: LoopStage
    public var delivery: DeliveryStage
    public var facts: [String]
    public var decisions: [String]
    public var sourceIDs: [String]
}

public struct ContextSnapshotWorkline: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var objective: String
    public var status: TaskStatus
    public var isFocused: Bool
    public var currentStage: LoopStage
    public var startedAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var deltas: [ContextSnapshotDelta]
}

public struct ContextSourcePointer: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var kind: String
    public var provider: String
    public var locator: String
    public var threadID: String
    public var turnIDs: [String]
    public var startOffset: UInt64?
    public var endOffset: UInt64?
    public var messageSpans: [ConversationSourceSpan]
}

public struct ContextSnapshotSemanticBundle: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var threadID: String
    public var turnIDs: [String]
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        summary: String,
        threadID: String,
        turnIDs: [String],
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.threadID = threadID
        self.turnIDs = turnIDs
        self.updatedAt = updatedAt
    }
}

public struct ContextSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var workspaceUpdatedAt: Date
    public var scope: ContextSnapshotScope
    public var project: ContextSnapshotProject
    public var worklines: [ContextSnapshotWorkline]
    public var openTopics: [ProjectTopic]
    public var turningPoints: [ProjectTimelineTurningPoint]
    public var openSemanticBundles: [ContextSnapshotSemanticBundle]
    public var collaborationGuidance: [String]
    public var sources: [ContextSourcePointer]

    public init(
        schemaVersion: Int = 3,
        generatedAt: Date = Date(),
        workspaceUpdatedAt: Date,
        scope: ContextSnapshotScope,
        project: ContextSnapshotProject,
        worklines: [ContextSnapshotWorkline],
        openTopics: [ProjectTopic],
        turningPoints: [ProjectTimelineTurningPoint] = [],
        openSemanticBundles: [ContextSnapshotSemanticBundle] = [],
        collaborationGuidance: [String] = [],
        sources: [ContextSourcePointer]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.workspaceUpdatedAt = workspaceUpdatedAt
        self.scope = scope
        self.project = project
        self.worklines = worklines
        self.openTopics = openTopics
        self.turningPoints = turningPoints
        self.openSemanticBundles = openSemanticBundles
        self.collaborationGuidance = collaborationGuidance
        self.sources = sources
    }
}

public struct ContextSnapshotBuilder: Sendable {
    public init() {}

    public func project(
        _ projectID: String,
        from workspace: WorkspaceSnapshot,
        generatedAt: Date = Date(),
        collaborationGuidance: [String] = []
    ) throws -> ContextSnapshot {
        guard let project = workspace.project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }
        return build(
            scope: ContextSnapshotScope(
                kind: .project,
                id: projectID,
                resolvedProjectID: projectID
            ),
            project: project,
            selectedTasks: project.tasks.filter(Self.isCurrentWorkline),
            workspace: workspace,
            generatedAt: generatedAt,
            collaborationGuidance: collaborationGuidance
        )
    }

    public func task(
        _ taskID: String,
        from workspace: WorkspaceSnapshot,
        generatedAt: Date = Date(),
        collaborationGuidance: [String] = []
    ) throws -> ContextSnapshot {
        guard let project = workspace.projects.first(where: { $0.task(id: taskID) != nil }),
              let task = project.task(id: taskID) else {
            throw WorkstateStorageError.missingTask(taskID)
        }
        return build(
            scope: ContextSnapshotScope(
                kind: .task,
                id: taskID,
                resolvedProjectID: project.id,
                resolvedTaskID: taskID
            ),
            project: project,
            selectedTasks: [task],
            workspace: workspace,
            generatedAt: generatedAt,
            collaborationGuidance: collaborationGuidance
        )
    }

    public func thread(
        _ threadID: String,
        projectID: String,
        from workspace: WorkspaceSnapshot,
        generatedAt: Date = Date(),
        collaborationGuidance: [String] = []
    ) throws -> ContextSnapshot {
        guard let project = workspace.project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }
        let threadSourceIDs = Set(
            workspace.sources
                .filter { $0.threadID == threadID }
                .map(\.id)
        )
        let matchingTasks = project.tasks.filter { task in
            Self.isCurrentWorkline(task)
                && (
                    !threadSourceIDs.isDisjoint(with: task.sourceIDs)
                        || project.events(for: task.id).contains {
                            !threadSourceIDs.isDisjoint(with: $0.sourceIDs)
                        }
                )
        }
        let selectedTasks = matchingTasks.isEmpty
            ? project.tasks.filter(Self.isCurrentWorkline)
            : matchingTasks
        return build(
            scope: ContextSnapshotScope(
                kind: .thread,
                id: threadID,
                resolvedProjectID: projectID,
                resolvedTaskID: matchingTasks.count == 1 ? matchingTasks[0].id : nil
            ),
            project: project,
            selectedTasks: selectedTasks,
            workspace: workspace,
            generatedAt: generatedAt,
            collaborationGuidance: collaborationGuidance
        )
    }

    private func build(
        scope: ContextSnapshotScope,
        project: ProjectRecord,
        selectedTasks: [TaskRecord],
        workspace: WorkspaceSnapshot,
        generatedAt: Date,
        collaborationGuidance: [String]
    ) -> ContextSnapshot {
        let worklines = selectedTasks
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { task in
                ContextSnapshotWorkline(
                    id: task.id,
                    title: task.title,
                    objective: task.objective,
                    status: task.status,
                    isFocused: project.focusedTaskID == task.id,
                    currentStage: task.currentStage,
                    startedAt: task.startedAt,
                    updatedAt: task.updatedAt,
                    tags: task.tags,
                    deltas: meaningfulDeltas(
                        project.events(for: task.id),
                        limit: scope.kind == .task ? 8 : 4
                    )
                )
            }
        let openTopics = project.topics
            .filter { $0.status == .captured || $0.status == .discussing }
            .sorted { $0.updatedAt > $1.updatedAt }
        let cognition = handoffCognition(project.context.cognition)
        let turningPoints = relevantTurningPoints(
            project.turningPoints ?? [],
            scope: scope,
            selectedTasks: selectedTasks
        )
        var referencedSourceIDs: [String] = []
        if let cognition {
            referencedSourceIDs.append(contentsOf: cognition.sections.flatMap(\.sourceIDs))
            referencedSourceIDs.append(contentsOf: cognition.pendingRevisions.flatMap { revision in
                revision.sourceIDs
                    + revision.beforeSections.flatMap(\.sourceIDs)
                    + revision.afterSections.flatMap(\.sourceIDs)
            })
        }
        referencedSourceIDs.append(contentsOf: worklines.flatMap { $0.deltas.flatMap(\.sourceIDs) })
        referencedSourceIDs.append(
            contentsOf: openTopics.flatMap { $0.notes.last?.sourceIDs ?? [] }
        )
        referencedSourceIDs.append(contentsOf: turningPoints.flatMap(\.sourceIDs))
        let sourceIDs = Set(referencedSourceIDs)
        let sources = workspace.sources
            .filter { sourceIDs.contains($0.id) }
            .map {
                ContextSourcePointer(
                    id: $0.id,
                    label: $0.label,
                    kind: $0.kind,
                    provider: $0.provider ?? ($0.threadID.isEmpty ? "workstate" : "codex"),
                    locator: $0.locator,
                    threadID: $0.threadID,
                    turnIDs: $0.turnIDs,
                    startOffset: $0.startOffset,
                    endOffset: $0.endOffset,
                    messageSpans: $0.messageSpans ?? []
                )
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return ContextSnapshot(
            generatedAt: generatedAt,
            workspaceUpdatedAt: workspace.updatedAt,
            scope: scope,
            project: ContextSnapshotProject(
                id: project.id,
                name: project.name,
                status: project.status,
                summary: project.summary,
                cognitionState: project.context.cognition?.state ?? .uninitialized,
                cognition: cognition
            ),
            worklines: worklines,
            openTopics: openTopics,
            turningPoints: turningPoints,
            collaborationGuidance: collaborationGuidance,
            sources: sources
        )
    }

    private func meaningfulDeltas(_ events: [ProjectEvent], limit: Int) -> [ContextSnapshotDelta] {
        guard !events.isEmpty else { return [] }
        let chronological = events.sorted { $0.timestamp < $1.timestamp }
        var selected = chronological.filter { event in
            !event.decisions.isEmpty
                || !event.facts.isEmpty
                || event.delivery.stage != .unchanged
                || [.decision, .implementation, .verification, .accepted, .integrated, .completed]
                    .contains(event.kind)
        }
        if let last = chronological.last, !selected.contains(where: { $0.id == last.id }) {
            selected.append(last)
        }
        return selected.suffix(limit).map {
            ContextSnapshotDelta(
                id: $0.id,
                timestamp: $0.timestamp,
                title: $0.title,
                summary: $0.summary,
                kind: $0.kind,
                stage: $0.loopStage,
                delivery: $0.delivery.stage,
                facts: $0.facts,
                decisions: $0.decisions
                    .filter { $0.status == .confirmed }
                    .map(\.text),
                sourceIDs: $0.sourceIDs
            )
        }
    }

    private func handoffCognition(
        _ cognition: ProjectCognitionDocument?
    ) -> ContextSnapshotCognition? {
        guard let cognition,
              cognition.state == .confirmed,
              let confirmedAt = cognition.confirmedAt else { return nil }
        return ContextSnapshotCognition(
            version: cognition.version,
            sections: cognition.sections,
            pendingRevisions: cognition.revisions.filter { $0.status == .pending },
            confirmedAt: confirmedAt,
            updatedAt: cognition.updatedAt
        )
    }

    private func relevantTurningPoints(
        _ turningPoints: [ProjectTimelineTurningPoint],
        scope: ContextSnapshotScope,
        selectedTasks: [TaskRecord]
    ) -> [ProjectTimelineTurningPoint] {
        let selectedTaskIDs = Set(selectedTasks.map(\.id))
        let relevant = turningPoints.filter { point in
            guard scope.kind != .project else { return true }
            guard let worklineID = point.worklineID else { return true }
            return selectedTaskIDs.contains(worklineID)
        }
        return Array(relevant.sorted { $0.timestamp > $1.timestamp }.prefix(12))
    }

    private static func isCurrentWorkline(_ task: TaskRecord) -> Bool {
        task.status == .active || task.status == .waiting
    }
}

public struct ContextSnapshotMarkdownRenderer: Sendable {
    public init() {}

    public func render(
        _ snapshot: ContextSnapshot,
        sourceIndexPath: String? = nil
    ) -> String {
        var lines = [
            "# \(snapshot.project.name)",
            "",
            "## 交接信息",
            "- Contract：Workstate Context Contract v\(snapshot.schemaVersion)",
            "- 范围：\(snapshot.scope.kind.rawValue) / \(snapshot.scope.id)",
            "- 生成时间：\(snapshot.generatedAt.ISO8601Format())",
            "- 数据更新时间：\(snapshot.workspaceUpdatedAt.ISO8601Format())",
            "- 项目状态：\(snapshot.project.status.rawValue)",
            "",
            "正式项目认知是本文件中的最高权威；待确认内容只能作为后续讨论线索。"
        ]
        if let cognition = snapshot.project.cognition {
            lines.append(contentsOf: ["", "## 项目认知 v\(cognition.version)"])
            for section in cognition.sections.sorted(by: { $0.order < $1.order }) {
                lines.append(contentsOf: ["", "### \(section.title)", section.body])
                appendEvidence(section.sourceIDs, to: &lines, indentation: "")
            }
            if !cognition.pendingRevisions.isEmpty {
                lines.append(contentsOf: ["", "## 待确认的认知修改"])
                for revision in cognition.pendingRevisions {
                    lines.append("- \(revision.rationale)")
                    for section in revision.afterSections {
                        lines.append("  - 提议：\(section.title)：\(section.body)")
                    }
                    appendEvidence(revision.sourceIDs, to: &lines, indentation: "  ")
                }
            }
        } else {
            let notice = snapshot.project.cognitionState == .draft
                ? "项目认知草稿尚未确认；以下旧摘要仅用于识别项目，不能视为完整事实。"
                : "项目认知尚未建立；以下旧摘要仅用于识别项目，不能视为完整事实。"
            lines.append(contentsOf: ["", notice])
            appendSection("旧项目摘要", values: [snapshot.project.summary], to: &lines)
        }

        if !snapshot.worklines.isEmpty {
            lines.append(contentsOf: ["", "## 当前工作"])
            for workline in snapshot.worklines {
                lines.append("")
                lines.append("### \(workline.title)")
                lines.append("- 状态：\(workline.status.rawValue) / \(workline.currentStage.rawValue)")
                lines.append("- 当前焦点：\(workline.isFocused ? "是" : "否")")
                lines.append("- 最近更新：\(workline.updatedAt.ISO8601Format())")
                if !workline.objective.isEmpty {
                    lines.append("- 目标：\(workline.objective)")
                }
                for delta in workline.deltas {
                    lines.append("- [\(delta.timestamp.ISO8601Format())] \(delta.title)：\(delta.summary)")
                    appendEvidence(delta.sourceIDs, to: &lines, indentation: "  ")
                }
            }
        }

        if !snapshot.turningPoints.isEmpty {
            lines.append(contentsOf: ["", "## 关键转折"])
            for point in snapshot.turningPoints {
                lines.append("")
                lines.append("### [\(turningPointScopeLabel(point.scope))] \(point.title)")
                lines.append("- 时间：\(point.timestamp.ISO8601Format())")
                lines.append("- 之前：\(point.beforeMeaning)")
                lines.append("- 现在：\(point.afterMeaning)")
                if let worklineID = point.worklineID {
                    lines.append("- 工作线：\(worklineID)")
                }
                lines.append("- 变化节点：\(point.originatingChangeID)")
                appendEvidence(point.sourceIDs, to: &lines, indentation: "")
            }
        }

        if !snapshot.openTopics.isEmpty {
            lines.append(contentsOf: ["", "## 待讨论议题"])
            lines.append(contentsOf: snapshot.openTopics.map {
                let disposition = ($0.disposition ?? .futureDecision) == .awaitingVerification
                    ? "待验证"
                    : "待决策"
                return "- [\(disposition)] \($0.title)：\($0.currentUnderstanding)"
            })
        }
        if !snapshot.openSemanticBundles.isEmpty {
            lines.append(contentsOf: ["", "## 尚未定性的对话"])
            lines.append(contentsOf: snapshot.openSemanticBundles.map { bundle in
                let turns = bundle.turnIDs.isEmpty
                    ? ""
                    : " · \(bundle.turnIDs.joined(separator: ", "))"
                return "- \(bundle.title)：\(bundle.summary) · codex://threads/\(bundle.threadID)\(turns)"
            })
        }
        appendSection("协作方式", values: snapshot.collaborationGuidance, to: &lines)

        if !snapshot.sources.isEmpty {
            lines.append(contentsOf: ["", "## 精确来源"])
            if let sourceIndexPath {
                lines.append("- 索引文件：\(sourceIndexPath)")
                lines.append("- 来源数量：\(snapshot.sources.count)")
                lines.append("- 仅在核对具体事实时读取索引，并按 source ID 定位原始证据。")
            } else {
                for source in snapshot.sources {
                    lines.append("")
                    lines.append("- [\(source.id)] \(source.label)")
                    lines.append("  - 类型：\(source.kind)")
                    lines.append("  - Provider：\(source.provider)")
                    if !source.threadID.isEmpty {
                        lines.append("  - 会话：codex://threads/\(source.threadID)")
                    }
                    if !source.turnIDs.isEmpty {
                        lines.append("  - Turns：\(source.turnIDs.joined(separator: ", "))")
                    }
                    if !source.locator.isEmpty {
                        lines.append("  - 文件：\(source.locator)")
                    }
                    if let startOffset = source.startOffset, let endOffset = source.endOffset {
                        lines.append("  - 字节范围：\(startOffset)..<\(endOffset)")
                    }
                    if !source.messageSpans.isEmpty {
                        let spans = source.messageSpans.map {
                            "\($0.kind.rawValue) \($0.startOffset)..<\($0.endOffset)"
                        }
                        lines.append("  - 消息范围：\(spans.joined(separator: "; "))")
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func turningPointScopeLabel(_ scope: ProjectTimelineTurningPointScope) -> String {
        switch scope {
        case .project: "项目"
        case .module: "模块"
        case .interaction: "交互"
        case .informationArchitecture: "信息架构"
        case .workline: "工作线"
        case .productModel: "产品模型"
        }
    }

    private func appendEvidence(
        _ sourceIDs: [String],
        to lines: inout [String],
        indentation: String
    ) {
        let ids = Array(Set(sourceIDs)).sorted()
        guard !ids.isEmpty else { return }
        lines.append("\(indentation)- 证据：\(ids.joined(separator: ", "))")
    }

    private func appendSection(_ title: String, values: [String], to lines: inout [String]) {
        let nonempty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonempty.isEmpty else { return }
        lines.append(contentsOf: ["", "## \(title)"])
        lines.append(contentsOf: nonempty.map { "- \($0)" })
    }
}
