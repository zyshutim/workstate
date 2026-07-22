import Foundation
import WorkstateCore

public struct ProjectRebuildApplier: Sendable {
    public let repository: WorkstateRepository

    public init(repository: WorkstateRepository = .init()) {
        self.repository = repository
    }

    @discardableResult
    public func apply(
        _ proposal: ProjectRebuildProposal,
        evidence: [SessionSegment]
    ) throws -> WorkspaceSnapshot {
        let evidenceByID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
        let validated = try validate(proposal, evidenceByID: evidenceByID)
        let mutation = WorkspaceMutation(
            kind: "project.rebuild",
            summary: "Project Steward rebuilt \(proposal.projectId)",
            projectID: proposal.projectId
        )

        return try repository.update(mutation: mutation) { snapshot in
            guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == proposal.projectId }) else {
                throw WorkstateStorageError.missingProject(proposal.projectId)
            }
            let oldProject = snapshot.projects[projectIndex]
            let referencedEvidence = validated.referencedEvidenceIDs.compactMap { evidenceByID[$0] }
            let sourceByEvidenceID = Dictionary(uniqueKeysWithValues: referencedEvidence.map { segment in
                (segment.id, sourceReference(for: segment, projectName: oldProject.name))
            })

            for source in sourceByEvidenceID.values {
                if let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
                    snapshot.sources[index] = source
                } else {
                    snapshot.sources.append(source)
                }
            }

            let sourceIDs: ([String]) -> [String] = { evidenceIDs in
                evidenceIDs.compactMap { sourceByEvidenceID[$0]?.id }
            }
            let latestDate = validated.latestDate
            let projectStartID = "rebuild-project-start-\(proposal.projectId)"
            let projectStart = ProjectEvent(
                id: projectStartID,
                timestamp: oldProject.createdAt,
                title: "项目建立",
                summary: proposal.purpose,
                kind: .projectStarted,
                loopStage: .intake,
                sourceIDs: sourceIDs(validated.referencedEvidenceIDs)
            )

            let completedWorklines = validated.worklines
                .compactMap { item -> (date: Date, mergeID: String)? in
                    guard let completedAt = item.completedAt else { return nil }
                    return (completedAt, mergeEventID(item.value.id))
                }
                .sorted { $0.date < $1.date }

            func branchPoint(for startedAt: Date) -> String {
                completedWorklines.last(where: { $0.date <= startedAt })?.mergeID ?? projectStartID
            }

            var tasks: [TaskRecord] = []
            var events: [ProjectEvent] = [projectStart]
            for item in validated.worklines.sorted(by: { $0.startedAt < $1.startedAt }) {
                let workline = item.value
                let startID = startEventID(workline.id)
                let branchID = branchPoint(for: item.startedAt)
                let taskSourceIDs = sourceIDs(workline.evidenceIds)
                let mergeID = item.completedAt == nil ? nil : mergeEventID(workline.id)
                tasks.append(
                    TaskRecord(
                        id: workline.id,
                        title: workline.title,
                        objective: workline.objective,
                        status: item.status,
                        accent: oldProject.accent,
                        currentStage: item.stage,
                        startedAt: item.startedAt,
                        updatedAt: item.updatedAt,
                        completedAt: item.completedAt,
                        branchedFromEventID: branchID,
                        mergedByEventID: mergeID,
                        tags: workline.tags,
                        sourceIDs: taskSourceIDs
                    )
                )
                events.append(
                    ProjectEvent(
                        id: startID,
                        taskID: workline.id,
                        timestamp: item.startedAt,
                        title: workline.title,
                        summary: workline.objective,
                        kind: .taskStarted,
                        loopStage: .intake,
                        parentEventIDs: [branchID],
                        tags: workline.tags,
                        sourceIDs: taskSourceIDs
                    )
                )

                var parentID = startID
                let worklineDeltas = validated.deltas
                    .filter { $0.value.worklineId == workline.id }
                    .sorted { $0.timestamp < $1.timestamp }
                for deltaItem in worklineDeltas {
                    let delta = deltaItem.value
                    let deltaSourceIDs = sourceIDs(delta.evidenceIds)
                    events.append(
                        ProjectEvent(
                            id: delta.id,
                            taskID: workline.id,
                            timestamp: deltaItem.timestamp,
                            title: delta.title,
                            summary: delta.summary,
                            kind: deltaItem.kind,
                            loopStage: deltaItem.stage,
                            parentEventIDs: [parentID],
                            facts: delta.facts,
                            decisions: delta.decisions.map {
                                DecisionRecord(text: $0, status: .confirmed, sourceIDs: deltaSourceIDs)
                            },
                            delivery: DeliverySnapshot(
                                stage: deltaItem.delivery,
                                verifiedAt: verifiedDate(for: deltaItem.delivery, timestamp: deltaItem.timestamp)
                            ),
                            sourceIDs: deltaSourceIDs
                        )
                    )
                    parentID = delta.id
                }

                if let completedAt = item.completedAt, let mergeID {
                    var parents = [parentID]
                    if branchID != parentID { parents.append(branchID) }
                    events.append(
                        ProjectEvent(
                            id: mergeID,
                            timestamp: completedAt,
                            title: "\(workline.title) 收束",
                            summary: workline.objective,
                            kind: .completed,
                            loopStage: .completed,
                            parentEventIDs: parents,
                            delivery: DeliverySnapshot(stage: .unchanged),
                            tags: workline.tags,
                            sourceIDs: taskSourceIDs
                        )
                    )
                }
            }

            let understanding = proposal.understanding.enumerated().map { index, item in
                ContextStatement(
                    id: "rebuild-understanding-\(proposal.projectId)-\(index)",
                    text: item.text,
                    status: EvidenceStatus(rawValue: item.status) ?? .observed,
                    updatedAt: latestEvidenceDate(item.evidenceIds, evidenceByID: evidenceByID) ?? latestDate,
                    sourceIDs: sourceIDs(item.evidenceIds)
                )
            }
            let acceptedDecisions = proposal.acceptedDecisions.map { item in
                DecisionRecord(
                    text: item.text,
                    status: .confirmed,
                    rationale: item.rationale,
                    sourceIDs: sourceIDs(item.evidenceIds)
                )
            }
            let allSourceIDs = sourceIDs(validated.referencedEvidenceIDs)
            let context = ProjectContext(
                currentSummary: proposal.currentSummary,
                purpose: proposal.purpose,
                inScope: proposal.inScope,
                outOfScope: proposal.outOfScope,
                understanding: understanding,
                revisions: [
                    ContextRevision(
                        id: "rebuild-revision-\(proposal.projectId)",
                        timestamp: latestDate,
                        title: "Project Steward 全量重建",
                        summary: "基于完整 Codex 会话证据重建项目 HEAD、工作线与关键变化。",
                        status: .confirmed,
                        changes: [
                            "重建当前项目理解与对象模型",
                            "按语义工作线重新组织历史",
                            "所有关键变化绑定原始 Codex turn"
                        ],
                        sourceIDs: allSourceIDs
                    )
                ],
                objectModel: proposal.objectModel.map(\.text),
                acceptedDecisions: acceptedDecisions,
                forbiddenDirections: proposal.forbiddenDirections.map(\.text),
                openIssues: proposal.openIssues.map(\.text)
            )

            snapshot.projects[projectIndex] = ProjectRecord(
                id: oldProject.id,
                name: oldProject.name,
                summary: proposal.currentSummary,
                status: validated.projectStatus,
                accent: oldProject.accent,
                createdAt: oldProject.createdAt,
                updatedAt: latestDate,
                lastActivityAt: latestDate,
                graphPosition: oldProject.graphPosition,
                context: context,
                tasks: tasks,
                events: events.sorted { $0.timestamp < $1.timestamp },
                sourceIDs: allSourceIDs
            )
        }
    }

    private func validate(
        _ proposal: ProjectRebuildProposal,
        evidenceByID: [String: SessionSegment]
    ) throws -> ValidatedProposal {
        guard !proposal.currentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState("Rebuild proposal has an empty Project HEAD")
        }
        guard !proposal.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState("Rebuild proposal has an empty purpose")
        }
        guard let projectStatus = ProjectStatus(rawValue: proposal.status) else {
            throw WorkstateStorageError.invalidState("Unsupported rebuilt project status: \(proposal.status)")
        }
        guard !proposal.worklines.isEmpty else {
            throw WorkstateStorageError.invalidState("Rebuild proposal contains no worklines")
        }

        let worklineIDs = Set(proposal.worklines.map(\.id))
        guard worklineIDs.count == proposal.worklines.count else {
            throw WorkstateStorageError.invalidState("Rebuild proposal contains duplicate workline ids")
        }
        let deltaIDs = Set(proposal.deltas.map(\.id))
        guard deltaIDs.count == proposal.deltas.count else {
            throw WorkstateStorageError.invalidState("Rebuild proposal contains duplicate delta ids")
        }

        var allEvidenceIDs = proposal.understanding.flatMap(\.evidenceIds)
        allEvidenceIDs.append(contentsOf: proposal.acceptedDecisions.flatMap(\.evidenceIds))
        allEvidenceIDs.append(contentsOf: proposal.objectModel.flatMap(\.evidenceIds))
        allEvidenceIDs.append(contentsOf: proposal.forbiddenDirections.flatMap(\.evidenceIds))
        allEvidenceIDs.append(contentsOf: proposal.openIssues.flatMap(\.evidenceIds))
        allEvidenceIDs.append(contentsOf: proposal.worklines.flatMap(\.evidenceIds))
        allEvidenceIDs.append(contentsOf: proposal.deltas.flatMap(\.evidenceIds))
        guard !allEvidenceIDs.isEmpty else {
            throw WorkstateStorageError.invalidState("Rebuild proposal contains no evidence references")
        }
        for id in Set(allEvidenceIDs) where evidenceByID[id] == nil {
            throw WorkstateStorageError.invalidState("Rebuild proposal references unknown evidence: \(id)")
        }
        for item in proposal.understanding where item.evidenceIds.isEmpty {
            throw WorkstateStorageError.invalidState("Understanding item has no evidence: \(item.text)")
        }
        for item in proposal.acceptedDecisions where item.evidenceIds.isEmpty {
            throw WorkstateStorageError.invalidState("Decision has no evidence: \(item.text)")
        }
        for item in proposal.objectModel where item.evidenceIds.isEmpty {
            throw WorkstateStorageError.invalidState("Object-model item has no evidence: \(item.text)")
        }
        for item in proposal.forbiddenDirections where item.evidenceIds.isEmpty {
            throw WorkstateStorageError.invalidState("Forbidden direction has no evidence: \(item.text)")
        }
        for item in proposal.openIssues where item.evidenceIds.isEmpty {
            throw WorkstateStorageError.invalidState("Open issue has no evidence: \(item.text)")
        }

        let parsedWorklines = try proposal.worklines.map { value -> ParsedWorkline in
            guard value.id.hasPrefix("\(proposal.projectId)-") else {
                throw WorkstateStorageError.invalidState("Workline id must start with \(proposal.projectId)-: \(value.id)")
            }
            guard !value.evidenceIds.isEmpty else {
                throw WorkstateStorageError.invalidState("Workline has no evidence: \(value.id)")
            }
            guard let status = TaskStatus(rawValue: value.status),
                  let stage = LoopStage(rawValue: value.stage) else {
                throw WorkstateStorageError.invalidState("Unsupported workline state: \(value.id)")
            }
            let startedAt = try parseDate(value.startedAt)
            let updatedAt = try parseDate(value.updatedAt)
            let completedAt = value.completedAt.isEmpty ? nil : try parseDate(value.completedAt)
            if status == .completed && completedAt == nil {
                throw WorkstateStorageError.invalidState("Completed workline has no completedAt: \(value.id)")
            }
            if let completedAt, completedAt < startedAt {
                throw WorkstateStorageError.invalidState("Workline completes before it starts: \(value.id)")
            }
            return ParsedWorkline(
                value: value,
                status: status,
                stage: stage,
                startedAt: startedAt,
                updatedAt: updatedAt,
                completedAt: completedAt
            )
        }

        let parsedDeltas = try proposal.deltas.map { value -> ParsedDelta in
            guard value.id.hasPrefix("\(proposal.projectId)-") else {
                throw WorkstateStorageError.invalidState("Delta id must start with \(proposal.projectId)-: \(value.id)")
            }
            guard worklineIDs.contains(value.worklineId) else {
                throw WorkstateStorageError.invalidState("Delta references unknown workline: \(value.worklineId)")
            }
            guard !value.evidenceIds.isEmpty else {
                throw WorkstateStorageError.invalidState("Delta has no evidence: \(value.id)")
            }
            guard let kind = EventKind(rawValue: value.kind),
                  let stage = LoopStage(rawValue: value.stage),
                  let delivery = DeliveryStage(rawValue: value.delivery) else {
                throw WorkstateStorageError.invalidState("Unsupported delta state: \(value.id)")
            }
            return ParsedDelta(
                value: value,
                kind: kind,
                stage: stage,
                delivery: delivery,
                timestamp: try parseDate(value.timestamp)
            )
        }
        for workline in parsedWorklines {
            let timestamps = parsedDeltas
                .filter { $0.value.worklineId == workline.value.id }
                .map(\.timestamp)
            if let earliest = timestamps.min(), earliest < workline.startedAt {
                throw WorkstateStorageError.invalidState(
                    "Delta predates workline start: \(workline.value.id)"
                )
            }
            if let latest = timestamps.max(), latest > workline.updatedAt {
                throw WorkstateStorageError.invalidState(
                    "Delta exceeds workline updatedAt: \(workline.value.id)"
                )
            }
            if let completedAt = workline.completedAt,
               let latest = timestamps.max(),
               latest > completedAt {
                throw WorkstateStorageError.invalidState(
                    "Delta exceeds workline completion: \(workline.value.id)"
                )
            }
        }
        let latestDate = (parsedDeltas.map(\.timestamp) + parsedWorklines.map(\.updatedAt)).max() ?? Date()
        return ValidatedProposal(
            projectStatus: projectStatus,
            worklines: parsedWorklines,
            deltas: parsedDeltas,
            referencedEvidenceIDs: Array(Set(allEvidenceIDs)).sorted(),
            latestDate: latestDate
        )
    }

    private func parseDate(_ raw: String) throws -> Date {
        let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let fallback = Date.ISO8601FormatStyle()
        if let date = try? precise.parse(raw) { return date }
        if let date = try? fallback.parse(raw) { return date }
        throw WorkstateStorageError.invalidState("Invalid rebuild timestamp: \(raw)")
    }

    private func sourceReference(for segment: SessionSegment, projectName: String) -> SourceReference {
        SourceReference(
            id: sourceID(segment),
            kind: "conversation",
            label: "Codex · \(projectName) · \(segment.turnID.prefix(8))",
            locator: "codex://threads/\(segment.threadID)",
            threadID: segment.threadID,
            turnIDs: [segment.turnID],
            excerpt: [
                ConversationMessage(role: "user", text: segment.userText, timestamp: segment.timestamp),
                ConversationMessage(role: "assistant", text: segment.assistantText, timestamp: segment.timestamp)
            ],
            contentHash: segment.id
        )
    }

    private func sourceID(_ segment: SessionSegment) -> String {
        "source-codex-turn-\(segment.turnID)"
    }

    private func latestEvidenceDate(
        _ ids: [String],
        evidenceByID: [String: SessionSegment]
    ) -> Date? {
        ids.compactMap { evidenceByID[$0]?.timestamp }.max()
    }

    private func startEventID(_ worklineID: String) -> String {
        "rebuild-start-\(worklineID)"
    }

    private func mergeEventID(_ worklineID: String) -> String {
        "rebuild-merge-\(worklineID)"
    }

    private func verifiedDate(for delivery: DeliveryStage, timestamp: Date) -> Date? {
        switch delivery {
        case .checked, .rendered, .userAccepted, .integrated, .published: timestamp
        case .unchanged, .changed: nil
        }
    }
}

private struct ParsedWorkline {
    var value: RebuildWorkline
    var status: TaskStatus
    var stage: LoopStage
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

private struct ParsedDelta {
    var value: RebuildDelta
    var kind: EventKind
    var stage: LoopStage
    var delivery: DeliveryStage
    var timestamp: Date
}

private struct ValidatedProposal {
    var projectStatus: ProjectStatus
    var worklines: [ParsedWorkline]
    var deltas: [ParsedDelta]
    var referencedEvidenceIDs: [String]
    var latestDate: Date
}
