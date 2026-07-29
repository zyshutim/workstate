import CryptoKit
import Foundation
import WorkstateCore

public struct OrchestrationSummary: Sendable {
    public var processed: Int
    public var changed: Int
    public var ignored: Int
    public var agentRuns: Int
    public var failed: Int
    public var routes: [ProcessedSegmentRoute]

    public init(
        processed: Int = 0,
        changed: Int = 0,
        ignored: Int = 0,
        agentRuns: Int = 0,
        failed: Int = 0,
        routes: [ProcessedSegmentRoute] = []
    ) {
        self.processed = processed
        self.changed = changed
        self.ignored = ignored
        self.agentRuns = agentRuns
        self.failed = failed
        self.routes = routes
    }
}

public struct ConversationBatchCommitPlan: Codable, Sendable {
    public var newProjects: [ProjectCreateInput]
    public var changes: [IngestionProjectChange]
    public var semanticBundleMutations: [ConversationSemanticBundleMutation]
    public var successfulRoutes: [ProcessedSegmentRoute]
    public var failedSegmentIDs: [String]
    public var processed: Int
    public var changed: Int
    public var ignored: Int
    public var agentRuns: Int

    public init(
        newProjects: [ProjectCreateInput] = [],
        changes: [IngestionProjectChange],
        semanticBundleMutations: [ConversationSemanticBundleMutation] = [],
        successfulRoutes: [ProcessedSegmentRoute],
        failedSegmentIDs: [String],
        processed: Int,
        changed: Int,
        ignored: Int,
        agentRuns: Int
    ) {
        self.newProjects = newProjects
        self.changes = changes
        self.semanticBundleMutations = semanticBundleMutations
        self.successfulRoutes = successfulRoutes
        self.failedSegmentIDs = failedSegmentIDs
        self.processed = processed
        self.changed = changed
        self.ignored = ignored
        self.agentRuns = agentRuns
    }

    public var summary: OrchestrationSummary {
        OrchestrationSummary(
            processed: processed,
            changed: changed,
            ignored: ignored,
            agentRuns: agentRuns,
            failed: failedSegmentIDs.count,
            routes: successfulRoutes
        )
    }
}

public struct WorkstateOrchestrator: Sendable {
    private static let maximumOpenBundlePointers = 100
    private static let maximumOpenBundleBytes: UInt64 = 768 * 1024
    private static let maximumOwnerEvidencePointers = 150
    private static let maximumOwnerEvidenceBytes: UInt64 = 1024 * 1024

    public let service: WorkstateService
    public let scanner: CodexSessionScanner
    public let runtime: AgentRuntimeClient

    public init(
        service: WorkstateService = .init(),
        scanner: CodexSessionScanner = .init(),
        runtime: AgentRuntimeClient = .init()
    ) {
        self.service = service
        self.scanner = scanner
        self.runtime = runtime
    }

    public func process(_ segments: [SessionSegment]) throws -> OrchestrationSummary {
        let summary = try processBacklog(segments)
        let successful = Set(summary.routes.map(\.segmentID))
        let failed = segments.map(\.id).filter { !successful.contains($0) }
        try scanner.finalizePointerBatch(
            successfulRoutes: summary.routes,
            failedSegmentIDs: failed
        )
        return summary
    }

    public func processProjectBacklog(
        _ segments: [SessionSegment],
        projectID: String,
        beforeApplying: ((ConversationBatchCommitPlan) throws -> Void)? = nil
    ) throws -> OrchestrationSummary {
        guard !segments.isEmpty else { return OrchestrationSummary() }
        guard let project = try service.snapshot().project(id: projectID) else {
            throw WorkstateStorageError.missingProject(projectID)
        }
        let ordered = segments.sorted { $0.timestamp < $1.timestamp }
        let batchResult = try runtime.stewardBatch(
            segments: ordered,
            project: project,
            scanner: scanner
        )
        let changes = try makeIngestionChanges(
            batchResult.changes,
            segments: ordered,
            projectID: projectID
        )
        let routes = ordered.map {
            ProcessedSegmentRoute(
                segmentID: $0.id,
                threadID: $0.threadID,
                turnID: $0.turnID,
                projectID: projectID
            )
        }
        let referenced = Set(batchResult.changes.flatMap(\.evidenceIds))
        let plan = ConversationBatchCommitPlan(
            changes: changes,
            successfulRoutes: routes,
            failedSegmentIDs: [],
            processed: ordered.count,
            changed: changes.count,
            ignored: ordered.count - referenced.count,
            agentRuns: 1
        )
        try beforeApplying?(plan)
        if !changes.isEmpty {
            _ = try service.applyIngestionBatch(changes)
        }
        return plan.summary
    }

    public func processBacklog(
        _ segments: [SessionSegment],
        beforeApplying: ((ConversationBatchCommitPlan) throws -> Void)? = nil,
        resumesPersistedState: Bool = true
    ) throws -> OrchestrationSummary {
        let resumed = resumesPersistedState
            ? try resumePersistedBatches(among: segments)
            : (summary: OrchestrationSummary(), segmentIDs: Set<String>())
        var summary = resumed.summary
        let remaining = segments
            .filter { !resumed.segmentIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
        guard !remaining.isEmpty else { return summary }
        guard Set(remaining.map(\.threadID)).count == 1 else {
            throw WorkstateStorageError.invalidState(
                "One orchestration batch must contain exactly one conversation"
            )
        }

        let records = resumesPersistedState
            ? try scanner.loadState().processingRecords ?? [:]
            : [:]
        let currentWorkspace = try service.snapshot()
        var routeBySegmentID: [String: RouteResult] = [:]
        var failedSegmentIDs = Set<String>()
        for segment in remaining {
            if records[segment.id]?.stage == .failed {
                failedSegmentIDs.insert(segment.id)
            } else if let route = records[segment.id]?.route {
                routeBySegmentID[segment.id] = route
            }
        }

        let routeCandidates = remaining.filter {
            !failedSegmentIDs.contains($0.id) && routeBySegmentID[$0.id] == nil
        }
        if !routeCandidates.isEmpty {
            for threadSegments in Dictionary(grouping: routeCandidates, by: \.threadID).values {
                let ordered = threadSegments.sorted { $0.timestamp < $1.timestamp }
                var routeHints: [String: String] = [:]
                if let first = ordered.first,
                   let binding = try scanner.routeBinding(
                       threadID: first.threadID,
                       before: first.timestamp
                   ),
                   currentWorkspace.project(id: binding.projectID) != nil {
                    routeHints[first.threadID] = binding.projectID
                }
                let decisions = try runtime.routeBatch(
                    segments: ordered,
                    workspace: currentWorkspace,
                    routeHints: routeHints,
                    scanner: scanner
                )
                summary.agentRuns += 1
                for decision in decisions {
                    routeBySegmentID[decision.segmentId] = decision.routeResult
                }
            }
        }

        var successfulRoutes: [ProcessedSegmentRoute] = summary.routes
        for segment in remaining {
            guard !failedSegmentIDs.contains(segment.id),
                  let route = routeBySegmentID[segment.id],
                  route.normalizedDisposition == "ignore" else { continue }
            successfulRoutes.append(
                ProcessedSegmentRoute(
                    segmentID: segment.id,
                    threadID: segment.threadID,
                    turnID: segment.turnID,
                    projectID: nil
                )
            )
            summary.processed += 1
            summary.ignored += 1
        }

        let existingBundles = Dictionary(
            uniqueKeysWithValues: try scanner.indexedSemanticBundles().map { ($0.id, $0) }
        )
        let routedSegments = remaining.filter { segment in
            guard !failedSegmentIDs.contains(segment.id),
                  let route = routeBySegmentID[segment.id] else { return false }
            return route.normalizedDisposition != "ignore"
        }
        let bundleGroups = Dictionary(grouping: routedSegments) {
            routeBySegmentID[$0.id]!.bundleId!
        }
        var semanticBundleMutations: [ConversationSemanticBundleMutation] = []
        var committedSegmentsByProject: [String: [SessionSegment]] = [:]
        var committedCurrentIDsByProject: [String: Set<String>] = [:]
        var committedRoutesByProject: [String: [(SessionSegment, RouteResult)]] = [:]
        var closedBundleIDsByProject: [String: [String]] = [:]
        var committedBytesByProject: [String: UInt64] = [:]
        var committedPointerCountByProject: [String: Int] = [:]

        for bundleID in bundleGroups.keys.sorted() {
            let currentSegments = bundleGroups[bundleID]!
                .sorted { $0.timestamp < $1.timestamp }
            let currentRoutes = currentSegments.compactMap { segment in
                routeBySegmentID[segment.id].map { (segment, $0) }
            }
            let projectIDs = Set(currentRoutes.map { $0.1.projectId })
            guard projectIDs.count == 1,
                  let projectID = projectIDs.first,
                  !projectID.isEmpty,
                  currentRoutes.count == currentSegments.count else {
                failedSegmentIDs.formUnion(currentSegments.map(\.id))
                continue
            }
            let existingBundle = existingBundles[bundleID]
            guard existingBundle?.projectID == nil || existingBundle?.projectID == projectID else {
                failedSegmentIDs.formUnion(currentSegments.map(\.id))
                continue
            }

            if currentRoutes.contains(where: { $0.1.normalizedDisposition == "commit" }) {
                let existingRecords = try scanner.pointerRecords(
                    ids: existingBundle?.pointerIDs ?? []
                )
                let evidenceBytes = boundedSourceBytes(currentSegments)
                    + boundedSourceBytes(existingRecords.map(\.pointer))
                let nextBytes = (committedBytesByProject[projectID] ?? 0) + evidenceBytes
                let nextPointerCount = (committedPointerCountByProject[projectID] ?? 0)
                    + currentSegments.count + existingRecords.count
                guard nextBytes <= Self.maximumOwnerEvidenceBytes,
                      nextPointerCount <= Self.maximumOwnerEvidencePointers else {
                    failedSegmentIDs.formUnion(currentSegments.map(\.id))
                    continue
                }
                committedBytesByProject[projectID] = nextBytes
                committedPointerCountByProject[projectID] = nextPointerCount
                var evidence = currentSegments
                if existingBundle != nil {
                    evidence.append(contentsOf: try scanner.segments(pointerRecords: existingRecords))
                    closedBundleIDsByProject[projectID, default: []].append(bundleID)
                }
                committedSegmentsByProject[projectID, default: []].append(contentsOf: evidence)
                committedCurrentIDsByProject[projectID, default: []]
                    .formUnion(currentSegments.map(\.id))
                committedRoutesByProject[projectID, default: []].append(contentsOf: currentRoutes)
                continue
            }

            guard currentRoutes.allSatisfy({ $0.1.normalizedDisposition == "carry" }),
                  let latest = currentRoutes.last else {
                failedSegmentIDs.formUnion(currentSegments.map(\.id))
                continue
            }
            var seenPointers = Set<ConversationSourcePointerID>()
            let pointerIDs = ((existingBundle?.pointerIDs ?? []) + currentSegments.map {
                ConversationSourcePointerID(
                    provider: "codex",
                    threadID: $0.threadID,
                    turnID: $0.turnID
                )
            }).filter { seenPointers.insert($0).inserted }
            let pointerRecords = try scanner.pointerRecords(ids: pointerIDs)
            guard pointerRecords.count == pointerIDs.count,
                  pointerIDs.count <= Self.maximumOpenBundlePointers,
                  boundedSourceBytes(pointerRecords.map(\.pointer))
                    <= Self.maximumOpenBundleBytes else {
                failedSegmentIDs.formUnion(currentSegments.map(\.id))
                continue
            }
            semanticBundleMutations.append(
                .upsert(
                    ConversationSemanticBundle(
                        id: bundleID,
                        threadID: latest.0.threadID,
                        projectID: projectID,
                        title: latest.1.bundleTitle ?? existingBundle?.title ?? bundleID,
                        summary: latest.1.bundleSummary ?? existingBundle?.summary ?? bundleID,
                        pointerIDs: pointerIDs,
                        updatedAt: latest.0.timestamp
                    )
                )
            )
            let routedProjectID = currentWorkspace.project(id: projectID) == nil
                ? nil
                : projectID
            successfulRoutes.append(contentsOf: currentSegments.map {
                ProcessedSegmentRoute(
                    segmentID: $0.id,
                    threadID: $0.threadID,
                    turnID: $0.turnID,
                    projectID: routedProjectID
                )
            })
            summary.processed += currentSegments.count
        }

        var stagedChanges: [IngestionProjectChange] = []
        var stagedRoutes: [ProcessedSegmentRoute] = []
        var stagedIgnoredCount = 0
        var stagedNewProjects: [ProjectCreateInput] = []

        for projectID in committedSegmentsByProject.keys.sorted() {
            let projectSegments = Array(Dictionary(
                committedSegmentsByProject[projectID]!.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            ).values)
            .sorted { $0.timestamp < $1.timestamp }
            let currentIDs = committedCurrentIDsByProject[projectID] ?? []
            let projectRoutes = committedRoutesByProject[projectID] ?? []
            do {
                let project: ProjectRecord
                if let existing = currentWorkspace.project(id: projectID) {
                    project = existing
                } else if let newRoute = projectRoutes.first(where: {
                    $0.1.action == "new_project" && $0.1.projectId == projectID
                }) {
                    let draft = try projectDraft(
                        route: newRoute.1,
                        segment: newRoute.0,
                        workspace: currentWorkspace,
                        additionalProjectCount: stagedNewProjects.count
                    )
                    project = draft.project
                    stagedNewProjects.append(draft.input)
                } else {
                    throw WorkstateStorageError.invalidState(
                        "Batch Router references an unknown project: \(projectID)"
                    )
                }

                let batchResult = try runtime.stewardBatch(
                    segments: projectSegments,
                    project: project,
                    scanner: scanner
                )
                summary.agentRuns += 1
                stagedChanges.append(contentsOf: try makeIngestionChanges(
                    batchResult.changes,
                    segments: projectSegments,
                    projectID: project.id
                ))
                stagedRoutes.append(contentsOf: projectRoutes.map {
                    ProcessedSegmentRoute(
                        segmentID: $0.0.id,
                        threadID: $0.0.threadID,
                        turnID: $0.0.turnID,
                        projectID: project.id
                    )
                })
                let referenced = Set(batchResult.changes.flatMap(\.evidenceIds))
                stagedIgnoredCount += currentIDs.subtracting(referenced).count
                semanticBundleMutations.append(contentsOf:
                    (closedBundleIDsByProject[projectID] ?? []).map {
                        .close(bundleID: $0)
                    }
                )
            } catch {
                failedSegmentIDs.formUnion(currentIDs)
            }
        }

        successfulRoutes.append(contentsOf: stagedRoutes)
        summary.processed += stagedRoutes.count
        summary.changed += stagedChanges.count
        summary.ignored += stagedIgnoredCount

        let accounted = Set(successfulRoutes.map(\.segmentID)).union(failedSegmentIDs)
        failedSegmentIDs.formUnion(remaining.map(\.id).filter { !accounted.contains($0) })
        let plan = ConversationBatchCommitPlan(
            newProjects: stagedNewProjects,
            changes: stagedChanges,
            semanticBundleMutations: semanticBundleMutations,
            successfulRoutes: successfulRoutes,
            failedSegmentIDs: Array(failedSegmentIDs).sorted(),
            processed: summary.processed,
            changed: summary.changed,
            ignored: summary.ignored,
            agentRuns: summary.agentRuns
        )
        try beforeApplying?(plan)
        if !stagedChanges.isEmpty || !stagedNewProjects.isEmpty {
            _ = try service.applyIngestionBatch(
                stagedChanges,
                newProjects: stagedNewProjects
            )
        }
        return plan.summary
    }

    private func boundedSourceBytes(_ segments: [SessionSegment]) -> UInt64 {
        boundedSourceBytes(segments.map { segment in
            if let spans = segment.sourceSpans, !spans.isEmpty {
                return spans.reduce(into: UInt64(0)) { total, span in
                    total = cappedAdd(total, span.endOffset - span.startOffset)
                }
            }
            return min(
                segment.endOffset - segment.startOffset,
                Self.maximumOwnerEvidenceBytes + 1
            )
        })
    }

    private func boundedSourceBytes(_ pointers: [ConversationSourcePointer]) -> UInt64 {
        boundedSourceBytes(pointers.map { pointer in
            if !pointer.messageSpans.isEmpty {
                return pointer.messageSpans.reduce(into: UInt64(0)) { total, span in
                    total = cappedAdd(total, span.endOffset - span.startOffset)
                }
            }
            return min(
                pointer.endOffset - pointer.startOffset,
                Self.maximumOwnerEvidenceBytes + 1
            )
        })
    }

    private func boundedSourceBytes(_ values: [UInt64]) -> UInt64 {
        values.reduce(into: UInt64(0)) { total, value in
            total = cappedAdd(total, value)
        }
    }

    private func cappedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let cap = Self.maximumOwnerEvidenceBytes + 1
        guard lhs < cap, rhs < cap, lhs <= cap - rhs else { return cap }
        return lhs + rhs
    }

    private func resumePersistedBatches(
        among segments: [SessionSegment]
    ) throws -> (summary: OrchestrationSummary, segmentIDs: Set<String>) {
        let requested = Set(segments.map(\.id))
        var summary = OrchestrationSummary()
        var consumed = Set<String>()
        for batch in try scanner.pendingStewardBatches()
        where !Set(batch.segmentIDs).isDisjoint(with: requested) {
            do {
                let evidence = try scanner.segments(ids: batch.segmentIDs)
                guard evidence.count == batch.segmentIDs.count else {
                    throw WorkstateStorageError.invalidState(
                        "Persisted Steward batch is missing evidence"
                    )
                }
                try applyStewardChanges(
                    batch.result.changes,
                    segments: evidence,
                    projectID: batch.projectID
                )
                let processedRoutes = evidence.map {
                    ProcessedSegmentRoute(
                        segmentID: $0.id,
                        threadID: $0.threadID,
                        turnID: $0.turnID,
                        projectID: batch.projectID
                    )
                }
                try scanner.commitProcessed(processedRoutes)
                summary.routes.append(contentsOf: processedRoutes)
                let referenced = Set(batch.result.changes.flatMap(\.evidenceIds))
                summary.processed += evidence.count
                summary.changed += batch.result.changes.count
                summary.ignored += evidence.count - referenced.count
                consumed.formUnion(batch.segmentIDs)
            } catch {
                try? scanner.failStewardBatch(id: batch.id, error: error.localizedDescription)
                summary.failed += batch.segmentIDs.count
                consumed.formUnion(batch.segmentIDs)
            }
        }
        return (summary, consumed)
    }

    private func applyStewardChanges(
        _ changes: [BatchStewardChange],
        segments: [SessionSegment],
        projectID: String
    ) throws {
        let inputs = try makeIngestionChanges(
            changes,
            segments: segments,
            projectID: projectID
        )
        if !inputs.isEmpty {
            _ = try service.applyIngestionChanges(projectID: projectID, changes: inputs)
        }
    }

    private func makeIngestionChanges(
        _ changes: [BatchStewardChange],
        segments: [SessionSegment],
        projectID: String
    ) throws -> [IngestionProjectChange] {
        guard !changes.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        let ordinaryChanges = changes.filter { $0.result.classification == "ordinary_delta" }
        return try ordinaryChanges.map { change -> IngestionProjectChange in
            let evidence = try change.evidenceIds.map { evidenceID in
                guard let segment = byID[evidenceID] else {
                    throw WorkstateStorageError.invalidState(
                        "Steward change references unknown evidence: \(evidenceID)"
                    )
                }
                return segment
            }
            .sorted { $0.timestamp < $1.timestamp }
            return try ingestionChange(
                from: change.result,
                evidence: evidence,
                projectID: projectID,
                semanticDiscriminator: try semanticDiscriminator(for: change)
            )
        }
    }

    private func ingestionChange(
        from result: StewardResult,
        evidence: [SessionSegment],
        projectID: String,
        semanticDiscriminator: String
    ) throws -> IngestionProjectChange {
        guard result.classification == "ordinary_delta",
              let latest = evidence.last,
              let kind = EventKind(rawValue: result.kind),
              let stage = LoopStage(rawValue: result.stage),
              let delivery = DeliveryStage(rawValue: result.delivery),
              let worklineAction = IngestionWorklineAction(stewardValue: result.worklineAction),
              let closureDisposition = IngestionClosureDisposition(
                  stewardValue: result.closureDisposition ?? "none"
              ) else {
            throw WorkstateStorageError.invalidState("Steward returned an unsupported state")
        }

        let contextPatch: IngestionContextPatch?
        if let patch = result.contextPatch, !patch.isEmpty {
            guard let revisionStatus = EvidenceStatus(rawValue: patch.revisionStatus) else {
                throw WorkstateStorageError.invalidState(
                    "Steward returned an unsupported context authority"
                )
            }
            contextPatch = IngestionContextPatch(
                currentSummary: patch.currentSummary,
                revisionID: stableID(
                    prefix: "context-revision",
                    segments: evidence,
                    discriminator: semanticDiscriminator
                ),
                revisionTitle: patch.revisionTitle,
                revisionSummary: patch.revisionSummary,
                revisionStatus: revisionStatus,
                changes: patch.changes,
                understandingUpserts: try patch.understandingUpserts.map {
                    guard let status = EvidenceStatus(rawValue: $0.status) else {
                        throw WorkstateStorageError.invalidState(
                            "Steward returned an unsupported understanding authority"
                        )
                    }
                    return IngestionUnderstandingMutation(
                        id: $0.id,
                        text: $0.text,
                        status: status
                    )
                },
                supersededUnderstandingIDs: patch.supersededUnderstandingIds,
                decisionUpserts: patch.decisionUpserts.map {
                    IngestionDecisionMutation(
                        id: $0.id,
                        text: $0.text,
                        rationale: $0.rationale
                    )
                },
                supersededDecisionIDs: patch.supersededDecisionIds,
                forbiddenDirectionAdditions: patch.forbiddenDirectionAdditions,
                forbiddenDirectionRemovals: patch.forbiddenDirectionRemovals
            )
        } else {
            contextPatch = nil
        }

        let sourceIDs = evidence.map { evidenceSource($0).id }
        let topicUpserts = try (result.topicUpdates ?? []).map { topic in
            guard let status = ProjectTopicStatus(rawValue: topic.status),
                  let kind = ProjectTopicKind(rawValue: topic.kind),
                  let disposition = ProjectTopicDisposition(rawValue: topic.disposition) else {
                throw WorkstateStorageError.invalidState(
                    "Steward returned an unsupported topic state"
                )
            }
            return IngestionTopicMutation(
                id: topic.id,
                title: topic.title,
                summary: topic.summary,
                status: status,
                kind: kind,
                disposition: disposition,
                currentUnderstanding: topic.currentUnderstanding,
                proposedDirection: topic.proposedDirection,
                deferredReason: topic.deferredReason,
                revisitTrigger: topic.revisitTrigger,
                openQuestions: topic.openQuestions,
                note: ProjectTopicNote(
                    id: "note-\(topic.id)-\(digest(sourceIDs.joined(separator: "\n")))",
                    timestamp: latest.timestamp,
                    kind: .origin,
                    title: "对话原话",
                    detail: "原始对话按需读取",
                    sourceIDs: sourceIDs
                ),
                sourceIDs: sourceIDs
            )
        }

        return IngestionProjectChange(
            id: stableID(
                prefix: "delta",
                segments: evidence,
                discriminator: semanticDiscriminator
            ),
            projectID: projectID,
            timestamp: latest.timestamp,
            sources: evidence.map(evidenceSource),
            title: result.title,
            summary: result.summary,
            kind: kind,
            stage: stage,
            delivery: delivery,
            facts: result.facts,
            operations: OperationalContext(cwd: latest.cwd),
            worklineAction: worklineAction,
            worklineID: result.worklineId,
            worklineTitle: result.worklineTitle,
            worklineObjective: result.worklineObjective,
            branchFromWorklineID: result.branchFromWorklineId,
            isParallel: result.isParallel ?? false,
            nextFocusedWorklineID: result.nextFocusedWorklineId ?? "",
            closureDisposition: closureDisposition,
            carryoverTitle: result.carryoverTitle ?? "",
            carryoverSummary: result.carryoverSummary ?? "",
            carryoverQuestions: result.carryoverQuestions ?? [],
            taskStartEventID: stableID(
                prefix: "task-start",
                segments: evidence,
                discriminator: semanticDiscriminator
            ),
            contextPatch: contextPatch,
            topicUpserts: topicUpserts
        )
    }

    private func semanticDiscriminator(for change: BatchStewardChange) throws -> String {
        let encoded = try WorkstateCoding.makeEncoder(pretty: false).encode(change)
        return digest(String(decoding: encoded, as: UTF8.self))
    }

    private func stewardBatchID(projectID: String, segmentIDs: [String]) -> String {
        "steward-batch-\(projectID)-\(digest(segmentIDs.joined(separator: "\n")))"
    }

    private func stableID(
        prefix: String,
        segments: [SessionSegment],
        discriminator: String
    ) -> String {
        if segments.count == 1, let segment = segments.first {
            return "\(stableID(prefix: prefix, segment: segment))-\(discriminator)"
        }
        let evidenceDigest = digest(segments.map(\.id).joined(separator: "\n"))
        return "\(prefix)-batch-\(evidenceDigest)-\(discriminator)"
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(10)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func projectDraft(
        route: RouteResult,
        segment: SessionSegment,
        workspace: WorkspaceSnapshot,
        additionalProjectCount: Int
    ) throws -> (project: ProjectRecord, input: ProjectCreateInput) {
        guard !route.projectId.isEmpty, !route.projectName.isEmpty, !route.projectSummary.isEmpty else {
            throw WorkstateStorageError.invalidState("Router returned an incomplete new project")
        }
        if let existing = workspace.project(id: route.projectId) {
            throw WorkstateStorageError.invalidState(
                "Router tried to stage an existing project as new: \(existing.id)"
            )
        }
        let index = workspace.projects.count + additionalProjectCount
        let accent = ProjectAccent.allCases[index % ProjectAccent.allCases.count]
        let input = ProjectCreateInput(
            id: route.projectId,
            name: route.projectName,
            summary: route.projectSummary,
            purpose: route.projectSummary,
            accent: accent,
            position: GraphPosition(
                x: 180 + Double(index % 2) * 260,
                y: 180 + Double(index / 2) * 180
            )
        )
        let project = ProjectRecord(
            id: input.id,
            name: input.name,
            summary: input.summary,
            status: input.status,
            accent: input.accent,
            createdAt: segment.timestamp,
            updatedAt: segment.timestamp,
            lastActivityAt: segment.timestamp,
            graphPosition: input.position,
            context: ProjectContext(
                currentSummary: input.summary,
                purpose: input.purpose
            ),
            events: [
                ProjectEvent(
                    id: "project-start-\(input.id)",
                    timestamp: segment.timestamp,
                    title: "项目建立",
                    summary: input.summary,
                    kind: .projectStarted,
                    loopStage: .intake
                )
            ]
        )
        return (project, input)
    }

    private func evidenceSource(_ segment: SessionSegment) -> SourceReference {
        SourceReference(
            id: stableID(prefix: "source", segment: segment),
            kind: "conversation",
            label: "Codex · \(segment.turnID)",
            locator: segment.sourcePath,
            threadID: segment.threadID,
            turnIDs: segment.relatedTurnIDs ?? [segment.turnID],
            contentHash: sourceContentHash(segment),
            provider: "codex",
            startOffset: segment.startOffset,
            endOffset: segment.endOffset,
            messageSpans: segment.sourceSpans
        )
    }

    private func sourceContentHash(_ segment: SessionSegment) -> String {
        let data = Data("\(segment.userText)\u{0}\(segment.assistantText)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func stableID(prefix: String, segment: SessionSegment) -> String {
        "\(prefix)-\(segment.threadID)-\(segment.turnID)"
    }

    private func backlogGroups(
        _ routed: [RoutedBacklogSegment]
    ) -> [[RoutedBacklogSegment]] {
        let ordered = routed.sorted { $0.segment.timestamp < $1.segment.timestamp }
        var groups: [[RoutedBacklogSegment]] = []
        for item in ordered {
            if let last = groups.indices.last,
               let previous = groups[last].last,
               previous.route.projectId == item.route.projectId,
               previous.segment.threadID == item.segment.threadID {
                groups[last].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups
    }

}

private extension IngestionWorklineAction {
    init?(stewardValue: String) {
        switch stewardValue {
        case "none":
            self = .none
        case "continue_existing":
            self = .continueExisting
        case "start_new":
            self = .startNew
        case "complete_existing":
            self = .completeExisting
        default:
            return nil
        }
    }
}

private extension IngestionClosureDisposition {
    init?(stewardValue: String) {
        switch stewardValue {
        case "none":
            self = .none
        case "completed":
            self = .completed
        case "future_decision":
            self = .futureDecision
        case "awaiting_verification":
            self = .awaitingVerification
        default:
            return nil
        }
    }
}

private extension String {
    var nonempty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct RoutedBacklogSegment {
    var segment: SessionSegment
    var route: RouteResult
}

private extension OrchestrationSummary {
    func adding(_ other: OrchestrationSummary) -> OrchestrationSummary {
        OrchestrationSummary(
            processed: processed + other.processed,
            changed: changed + other.changed,
            ignored: ignored + other.ignored,
            agentRuns: agentRuns + other.agentRuns,
            failed: failed + other.failed
        )
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        precondition(maximumCount > 0)
        return stride(from: 0, to: count, by: maximumCount).map { start in
            Array(self[start..<Swift.min(start + maximumCount, count)])
        }
    }
}
