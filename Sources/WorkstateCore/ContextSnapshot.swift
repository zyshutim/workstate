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
    public var purpose: String
    public var inScope: [String]
    public var outOfScope: [String]
    public var understanding: [String]
    public var acceptedDecisions: [String]
    public var forbiddenDirections: [String]
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
    public var locator: String
    public var threadID: String
    public var turnIDs: [String]
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
    public var openSemanticBundles: [ContextSnapshotSemanticBundle]
    public var collaborationGuidance: [String]
    public var sources: [ContextSourcePointer]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        workspaceUpdatedAt: Date,
        scope: ContextSnapshotScope,
        project: ContextSnapshotProject,
        worklines: [ContextSnapshotWorkline],
        openTopics: [ProjectTopic],
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
            !threadSourceIDs.isDisjoint(with: task.sourceIDs)
                || project.events(for: task.id).contains {
                    !threadSourceIDs.isDisjoint(with: $0.sourceIDs)
                }
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
        var referencedSourceIDs = project.context.understanding.flatMap(\.sourceIDs)
        referencedSourceIDs.append(contentsOf: project.context.acceptedDecisions.flatMap(\.sourceIDs))
        referencedSourceIDs.append(contentsOf: worklines.flatMap { $0.deltas.flatMap(\.sourceIDs) })
        referencedSourceIDs.append(
            contentsOf: openTopics.flatMap { $0.notes.last?.sourceIDs ?? [] }
        )
        let sourceIDs = Set(referencedSourceIDs)
        let sources = workspace.sources
            .filter { sourceIDs.contains($0.id) }
            .map {
                ContextSourcePointer(
                    id: $0.id,
                    label: $0.label,
                    kind: $0.kind,
                    locator: $0.locator,
                    threadID: $0.threadID,
                    turnIDs: $0.turnIDs
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
                summary: project.context.currentSummary.isEmpty
                    ? project.summary
                    : project.context.currentSummary,
                purpose: project.context.purpose,
                inScope: project.context.inScope,
                outOfScope: project.context.outOfScope,
                understanding: unique(
                    project.context.understanding
                    .filter { $0.status == .confirmed || $0.status == .observed }
                    .map(\.text)
                ),
                acceptedDecisions: unique(
                    project.context.acceptedDecisions
                    .filter { $0.status == .confirmed }
                    .map(\.text)
                ),
                forbiddenDirections: unique(project.context.forbiddenDirections)
            ),
            worklines: worklines,
            openTopics: openTopics,
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

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func isCurrentWorkline(_ task: TaskRecord) -> Bool {
        task.status == .active
    }
}

public struct ContextSnapshotMarkdownRenderer: Sendable {
    public init() {}

    public func render(_ snapshot: ContextSnapshot) -> String {
        var lines = [
            "# \(snapshot.project.name)",
            "",
            snapshot.project.summary
        ]
        appendSection("目标", values: [snapshot.project.purpose], to: &lines)
        appendSection("已确认的理解", values: snapshot.project.understanding, to: &lines)
        appendSection("已确认的决定", values: snapshot.project.acceptedDecisions, to: &lines)
        appendSection("禁止方向", values: snapshot.project.forbiddenDirections, to: &lines)

        if !snapshot.worklines.isEmpty {
            lines.append(contentsOf: ["", "## 当前工作"])
            for workline in snapshot.worklines {
                lines.append("")
                lines.append("### \(workline.title)")
                lines.append("- 状态：\(workline.status.rawValue) / \(workline.currentStage.rawValue)")
                if !workline.objective.isEmpty {
                    lines.append("- 目标：\(workline.objective)")
                }
                for delta in workline.deltas {
                    lines.append("- \(delta.title)：\(delta.summary)")
                }
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
            lines.append(contentsOf: ["", "## 来源"])
            lines.append(contentsOf: snapshot.sources.map { source in
                let thread = source.threadID.isEmpty ? "" : " · codex://threads/\(source.threadID)"
                return "- \(source.label)：\(source.locator)\(thread)"
            })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendSection(_ title: String, values: [String], to lines: inout [String]) {
        let nonempty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonempty.isEmpty else { return }
        lines.append(contentsOf: ["", "## \(title)"])
        lines.append(contentsOf: nonempty.map { "- \($0)" })
    }
}
