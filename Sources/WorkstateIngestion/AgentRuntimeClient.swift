import Darwin
import Foundation
import WorkstateCore

public struct AgentRuntimeClient: Sendable {
    public let runtimeScript: URL
    public let nodePath: String
    public let runtimeRoot: URL
    private let processRegistry: AgentProcessRegistry
    private let settingsRepository: WorkstateSettingsRepository

    public init(
        runtimeScript: URL? = nil,
        nodePath: String? = nil,
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root
    ) {
        self.runtimeScript = runtimeScript ?? Self.defaultRuntimeScript()
        self.nodePath = nodePath ?? Self.defaultNodePath()
        self.runtimeRoot = runtimeRoot
        processRegistry = AgentProcessRegistry()
        settingsRepository = WorkstateSettingsRepository(root: runtimeRoot)
    }

    public static func defaultRuntimeScript() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["WORKSTATE_AGENT_RUNTIME"] {
            return URL(fileURLWithPath: explicit)
        }
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(
                resources.appendingPathComponent("AgentRuntime/dist/index.js")
            )
        }
        if let executable = CommandLine.arguments.first, !executable.isEmpty {
            let distributionRoot = URL(fileURLWithPath: executable)
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(
                distributionRoot
                    .appendingPathComponent("Workstate.app/Contents/Resources/AgentRuntime/dist/index.js")
            )
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("AgentRuntime/dist/index.js"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Workstate/AgentRuntime/dist/index.js")
        ])
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? candidates[0]
    }

    public static func defaultEvidenceExtractor() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["WORKSTATE_EVIDENCE_EXTRACTOR"] {
            return URL(fileURLWithPath: explicit)
        }
        let runtimeDirectory = defaultRuntimeScript()
            .deletingLastPathComponent()
        return runtimeDirectory.appendingPathComponent("extract-evidence.js")
    }

    public static func defaultNodePath() -> String {
        if let explicit = ProcessInfo.processInfo.environment["WORKSTATE_NODE_PATH"] {
            return explicit
        }
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/node" }
        let candidates = pathCandidates + [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            ?? candidates.last!
    }

    public func cancelActiveProcess() {
        processRegistry.cancelActiveProcess()
    }

    @discardableResult
    public func resetProjectOwnerSession(projectID: String) throws -> String? {
        let normalizedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectID.isEmpty else {
            throw WorkstateStorageError.invalidState(
                "Project Owner session reset requires a project id"
            )
        }
        let request = ResetProjectOwnerSessionRequest(
            mode: "reset_owner_session",
            projectId: normalizedProjectID
        )
        let envelope: RuntimeEnvelope<ResetProjectOwnerSessionResult> = try run(
            request,
            timeout: 30
        )
        guard envelope.mode == request.mode,
              envelope.result.projectId == normalizedProjectID else {
            throw WorkstateStorageError.invalidState(
                "Project Owner session reset returned the wrong project"
            )
        }
        return envelope.result.removedThreadId
    }

    public func route(
        segment: SessionSegment,
        workspace: WorkspaceSnapshot,
        scanner: CodexSessionScanner
    ) throws -> RouteResult {
        let request = RouteRequest(
            mode: "route",
            profile: try runtimeProfile(.route),
            segment: segment,
            projects: workspace.projects.map(RoutingProjectPayload.init),
            priorRoute: try scanner.routeBinding(threadID: segment.threadID).map(RouteBindingPayload.init),
            recentTurns: try scanner.recentSegments(threadID: segment.threadID, before: segment.timestamp),
            openBundles: try scanner.openSemanticBundles().map(OpenSemanticBundlePayload.init)
        )
        let envelope: RuntimeEnvelope<RouteResult> = try run(request, timeout: 300)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(envelope, segmentID: segment.id)
        try validateRouteResult(envelope.result)
        if envelope.result.action == "new_project",
           workspace.project(id: envelope.result.projectId) != nil {
            throw WorkstateStorageError.invalidState(
                "Router tried to recreate an existing project: \(envelope.result.projectId)"
            )
        }
        return envelope.result
    }

    private func validateRouteResult(_ result: RouteResult) throws {
        let supportedActions = ["continue_previous", "select_project", "switch_project", "new_project", "ignore"]
        let supportedDispositions = ["ignore", "carry", "commit"]
        guard supportedActions.contains(result.action),
              supportedDispositions.contains(result.normalizedDisposition) else {
            throw WorkstateStorageError.invalidState("Router returned an unsupported action")
        }
        if result.normalizedDisposition == "ignore" {
            guard result.action == "ignore",
                  result.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (result.bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (result.signals ?? []).isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "An ignored turn cannot route a project or semantic bundle"
                )
            }
            return
        }
        guard result.action != "ignore",
              !result.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(result.bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(result.bundleTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(result.bundleSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState(
                "A carried or committed turn requires a project and semantic bundle"
            )
        }
        if result.normalizedDisposition == "commit", (result.signals ?? []).isEmpty {
            throw WorkstateStorageError.invalidState(
                "A committed semantic bundle requires at least one durable signal"
            )
        }
        if result.action == "new_project" {
            guard !result.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.projectSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "A new project route requires name and summary"
                )
            }
        }
    }

    public func routeBatch(
        segments: [SessionSegment],
        workspace: WorkspaceSnapshot,
        routeHints: [String: String],
        scanner: CodexSessionScanner
    ) throws -> [BatchRouteDecision] {
        guard !segments.isEmpty else { return [] }
        guard let first = segments.first,
              segments.allSatisfy({ $0.threadID == first.threadID }) else {
            throw WorkstateStorageError.invalidState(
                "A Router batch must contain exactly one conversation thread"
            )
        }
        let request = BatchRouteRequest(
            mode: "batch_route",
            profile: try runtimeProfile(.route),
            segments: segments.map(BatchRouteSegmentPayload.init),
            projects: workspace.projects.map(RoutingProjectPayload.init),
            routeHints: routeHints.map {
                BatchRouteHintPayload(threadID: $0.key, projectID: $0.value)
            }
            .sorted { $0.threadID < $1.threadID },
            recentTurns: try scanner.recentSegments(
                threadID: first.threadID,
                before: first.timestamp,
                limit: 3
            ).map(BatchRouteSegmentPayload.init),
            openBundles: try scanner.openSemanticBundles()
                .filter { $0.threadID == first.threadID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(30)
                .map(OpenSemanticBundlePayload.init)
        )
        let envelope: RuntimeEnvelope<BatchRouteResult> = try run(request, timeout: 600)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(
            envelope,
            segmentID: "batch-route:\(segments.first!.id):\(segments.count)"
        )
        guard Set(segments.map(\.turnID)).count == segments.count else {
            throw WorkstateStorageError.invalidState(
                "A Router batch contains duplicate turn ids"
            )
        }
        let segmentIDByPosition = Dictionary(
            uniqueKeysWithValues: segments.enumerated().map { ($0.offset + 1, $0.element.id) }
        )
        var nextPosition = 1
        var decisions: [BatchRouteDecision] = []
        for packet in envelope.result.routes {
            guard packet.startPosition == nextPosition,
                  packet.endPosition >= packet.startPosition,
                  packet.endPosition <= segments.count else {
                throw WorkstateStorageError.invalidState(
                    "Batch Router returned a non-contiguous semantic partition"
                )
            }
            try validateRouteResult(packet.routeResult)
            if packet.action == "new_project",
               workspace.project(id: packet.projectId) != nil {
                throw WorkstateStorageError.invalidState(
                    "Batch Router tried to recreate an existing project: \(packet.projectId)"
                )
            }
            for position in packet.startPosition...packet.endPosition {
                guard let segmentID = segmentIDByPosition[position] else {
                    throw WorkstateStorageError.invalidState(
                        "Batch Router returned an unknown evidence position"
                    )
                }
                decisions.append(
                    BatchRouteDecision(
                        segmentId: segmentID,
                        action: packet.action,
                        projectId: packet.projectId,
                        projectName: packet.projectName,
                        projectSummary: packet.projectSummary,
                        disposition: packet.disposition,
                        bundleId: packet.bundleId,
                        bundleTitle: packet.bundleTitle,
                        bundleSummary: packet.bundleSummary,
                        signals: packet.signals,
                        confidence: packet.confidence,
                        reason: packet.reason
                    )
                )
            }
            nextPosition = packet.endPosition + 1
        }
        guard nextPosition == segments.count + 1 else {
            throw WorkstateStorageError.invalidState(
                "Batch Router did not cover every input segment exactly once"
            )
        }
        return decisions
    }

    public func steward(
        segment: SessionSegment,
        project: ProjectRecord,
        scanner: CodexSessionScanner
    ) throws -> StewardResult {
        let request = StewardRequest(
            mode: "steward",
            profile: try runtimeProfile(.steward),
            segment: segment,
            project: StewardProjectPayload(project: project)
        )
        let envelope: RuntimeEnvelope<StewardResult> = try run(request, timeout: 300)
        try validateStewardResult(envelope.result)
        var activeWorklineIDs = Set(project.tasks.filter { $0.status == .active }.map(\.id))
        var knownWorklineIDs = Set(project.tasks.map(\.id))
        try validateStewardWorklineState(
            envelope.result,
            activeWorklineIDs: &activeWorklineIDs,
            knownWorklineIDs: &knownWorklineIDs
        )
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(envelope, segmentID: segment.id)
        return envelope.result
    }

    public func stewardBatch(
        segments: [SessionSegment],
        project: ProjectRecord,
        scanner: CodexSessionScanner
    ) throws -> BatchStewardResult {
        guard !segments.isEmpty else { return BatchStewardResult(changes: []) }
        let request = BatchStewardRequest(
            mode: "batch_steward",
            profile: try runtimeProfile(.steward),
            segments: segments,
            project: StewardProjectPayload(project: project)
        )
        let envelope: RuntimeEnvelope<BatchStewardResult> = try run(request, timeout: 600)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(
            envelope,
            segmentID: "batch-steward:\(segments.first!.id):\(segments.count)"
        )
        let expected = Set(segments.map(\.id))
        var previousIndex = -1
        var semanticChanges = Set<Data>()
        var activeWorklineIDs = Set(project.tasks.filter { $0.status == .active }.map(\.id))
        var knownWorklineIDs = Set(project.tasks.map(\.id))
        var cognitionProposalCount = 0
        for change in envelope.result.changes {
            try validateStewardResult(change.result)
            try validateStewardWorklineState(
                change.result,
                activeWorklineIDs: &activeWorklineIDs,
                knownWorklineIDs: &knownWorklineIDs
            )
            if let proposal = change.result.cognitionProposal, !proposal.isEmpty {
                cognitionProposalCount += 1
            }
            guard !change.evidenceIds.isEmpty,
                  Set(change.evidenceIds).isSubset(of: expected),
                  change.result.classification == "ordinary_delta" else {
                throw WorkstateStorageError.invalidState(
                    "Batch Steward returned an invalid semantic change"
                )
            }
            let firstIndex = change.evidenceIds.compactMap { evidenceID in
                segments.firstIndex(where: { $0.id == evidenceID })
            }.min() ?? -1
            guard firstIndex >= previousIndex else {
                throw WorkstateStorageError.invalidState(
                    "Batch Steward returned changes out of chronological order"
                )
            }
            let semanticChange = try WorkstateCoding.makeEncoder(pretty: false).encode(change)
            guard semanticChanges.insert(semanticChange).inserted else {
                throw WorkstateStorageError.invalidState(
                    "Batch Steward returned a duplicate semantic change"
                )
            }
            previousIndex = firstIndex
        }
        guard cognitionProposalCount <= 1 else {
            throw WorkstateStorageError.invalidState(
                "A Steward batch may contain at most one cognition proposal"
            )
        }
        return envelope.result
    }

    public func generateProjectCognitionDraft(
        project: ProjectRecord,
        workspace: WorkspaceSnapshot,
        scanner: CodexSessionScanner
    ) throws -> ProjectCognitionDraftGeneration {
        guard workspace.project(id: project.id) != nil else {
            throw WorkstateStorageError.missingProject(project.id)
        }
        let projectSourceIDs = Set(project.sourceIDs)
        let sources = workspace.sources.filter { source in
            projectSourceIDs.contains(source.id)
                && source.kind == "conversation"
                && !source.threadID.isEmpty
                && !source.turnIDs.isEmpty
        }
        var sourceIDByPointer: [ConversationSourcePointerID: String] = [:]
        for source in sources {
            for turnID in source.turnIDs {
                sourceIDByPointer[
                    ConversationSourcePointerID(
                        provider: source.provider ?? "codex",
                        threadID: source.threadID,
                        turnID: turnID
                    )
                ] = source.id
            }
        }
        let records = try scanner.pointerRecords(ids: Array(sourceIDByPointer.keys))
        let materialized = try scanner.segments(pointerRecords: records)
        var evidenceBySegmentID: [String: (segment: SessionSegment, sourceID: String)] = [:]
        for segment in materialized {
            let pointerID = ConversationSourcePointerID(
                provider: "codex",
                threadID: segment.threadID,
                turnID: segment.turnID
            )
            if let sourceID = sourceIDByPointer[pointerID] {
                evidenceBySegmentID[segment.id] = (segment, sourceID)
            }
        }
        for source in sources where !evidenceBySegmentID.values.contains(where: {
            $0.sourceID == source.id
        }) {
            let messages = try scanner.resolveMessages(for: source)
            guard let segment = fallbackCognitionSegment(source: source, messages: messages) else {
                continue
            }
            evidenceBySegmentID[segment.id] = (segment, source.id)
        }
        let bounded = boundedCognitionSegments(evidenceBySegmentID.values.map(\.segment))
        let sourceIDBySegmentID = Dictionary(uniqueKeysWithValues: bounded.compactMap { segment in
            evidenceBySegmentID[segment.id].map { (segment.id, $0.sourceID) }
        })
        guard !bounded.isEmpty else {
            return ProjectCognitionDraftGeneration(
                sections: [],
                missingContext: ["项目没有可用的真实会话证据"],
                isReady: false
            )
        }
        let request = CognitionDraftRequest(
            mode: "cognition_draft",
            profile: try runtimeProfile(.steward),
            project: CognitionDraftProjectPayload(project: project),
            segments: bounded
        )
        let envelope: RuntimeEnvelope<CognitionDraftResult> = try run(request, timeout: 600)
        try writeCognitionDraftAttempt(
            CognitionDraftAttemptRecord(
                projectID: project.id,
                status: "received",
                error: "",
                runtimeThreadID: envelope.runtimeThreadId,
                usage: envelope.usage,
                telemetry: envelope.telemetry,
                result: envelope.result
            )
        )
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(envelope, segmentID: "cognition-draft:\(project.id)")
        do {
            guard envelope.result.isReady == (envelope.result.sections.isEmpty == false),
                  envelope.result.isReady == envelope.result.missingContext.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "Cognition draft readiness and payload are inconsistent"
                )
            }
            let mappedSections = try envelope.result.sections.map { section in
                let sourceIDs = try section.sourceIDs.map { sourceID in
                    guard let mapped = sourceIDBySegmentID[sourceID] else {
                        throw WorkstateStorageError.invalidState(
                            "Cognition draft referenced unknown evidence: \(sourceID)"
                        )
                    }
                    return mapped
                }
                return try decodeCognitionSection(
                    section,
                    sourceIDs: Array(Set(sourceIDs)).sorted()
                )
            }
            try updateCognitionDraftAttempt(
                projectID: project.id,
                status: envelope.result.isReady ? "validated" : "notReady",
                error: ""
            )
            return ProjectCognitionDraftGeneration(
                sections: mappedSections,
                missingContext: envelope.result.missingContext,
                isReady: envelope.result.isReady
            )
        } catch {
            try? updateCognitionDraftAttempt(
                projectID: project.id,
                status: "validationFailed",
                error: error.localizedDescription
            )
            throw error
        }
    }

    public func recordProjectCognitionDraftSaved(projectID: String) throws {
        try updateCognitionDraftAttempt(projectID: projectID, status: "saved", error: "")
    }

    public func recordProjectCognitionDraftSaveFailure(projectID: String, error: Error) throws {
        try updateCognitionDraftAttempt(
            projectID: projectID,
            status: "saveFailed",
            error: error.localizedDescription
        )
    }

    private func validateStewardResult(_ result: StewardResult) throws {
        guard result.classification == "no_change"
                || result.classification == "ordinary_delta" else {
            throw WorkstateStorageError.invalidState(
                "Steward returned an unsupported classification"
            )
        }
        if result.classification == "no_change" {
            guard result.worklineAction == "none",
                  result.contextPatch?.isEmpty != false,
                  result.cognitionProposal?.isEmpty != false,
                  result.turningPoint?.isEmpty != false,
                  (result.topicUpdates ?? []).isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "A no-change Steward result cannot mutate worklines or Project HEAD"
                )
            }
            return
        }
        let closure = result.closureDisposition ?? "none"
        if result.worklineAction == "complete_existing" {
            guard closure != "none" else {
                throw WorkstateStorageError.invalidState(
                    "Completing a workline requires a closure disposition"
                )
            }
        } else {
            guard closure == "none" else {
                throw WorkstateStorageError.invalidState(
                    "Only explicit workline completion may use a closure disposition"
                )
            }
            let nextFocus = result.nextFocusedWorklineId ?? ""
            if result.worklineAction == "none" {
                guard nextFocus.isEmpty else {
                    throw WorkstateStorageError.invalidState(
                        "A project-wide delta cannot change workline focus"
                    )
                }
            } else if !nextFocus.isEmpty, nextFocus != result.worklineId {
                throw WorkstateStorageError.invalidState(
                    "A continuing or new workline may only focus itself"
                )
            }
        }
        guard !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState(
                "A durable Steward result requires a title and summary"
            )
        }
        if let proposal = result.cognitionProposal {
            try validateCognitionProposal(proposal)
        }
        if let turningPoint = result.turningPoint {
            try validateTurningPoint(turningPoint)
        }
    }

    private func validateTurningPoint(_ turningPoint: StewardTurningPoint) throws {
        if turningPoint.isEmpty {
            guard turningPoint.title.isEmpty,
                  turningPoint.beforeMeaning.isEmpty,
                  turningPoint.afterMeaning.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "An empty timeline turning point cannot contain meaning"
                )
            }
            return
        }
        let supportedScopes = Set(ProjectTimelineTurningPointScope.allCases.map(\.rawValue))
        guard supportedScopes.contains(turningPoint.scope),
              !turningPoint.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !turningPoint.beforeMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !turningPoint.afterMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              turningPoint.beforeMeaning != turningPoint.afterMeaning else {
            throw WorkstateStorageError.invalidState(
                "Timeline turning point has an unsupported scope or meaning"
            )
        }
    }

    private func validateCognitionProposal(_ proposal: StewardCognitionProposal) throws {
        if proposal.isEmpty {
            guard proposal.summary.isEmpty,
                  proposal.beforeSectionIDs.isEmpty,
                  proposal.afterSections.isEmpty else {
                throw WorkstateStorageError.invalidState(
                    "An empty cognition proposal cannot contain changes"
                )
            }
            return
        }
        guard !proposal.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkstateStorageError.invalidState("A cognition proposal requires a summary")
        }
        let beforeCount = proposal.beforeSectionIDs.count
        let afterCount = proposal.afterSections.count
        let hasValidShape = switch proposal.operation {
        case "update": beforeCount == 1 && afterCount == 1
        case "insert": beforeCount == 0 && afterCount >= 1
        case "delete": beforeCount >= 1 && afterCount == 0
        case "split": beforeCount == 1 && afterCount >= 2
        case "merge": beforeCount >= 2 && afterCount == 1
        default: false
        }
        guard hasValidShape,
              Set(proposal.beforeSectionIDs).count == beforeCount,
              Set(proposal.afterSections.map(\.id)).count == afterCount,
              proposal.afterSections.allSatisfy({
                  !$0.id.isEmpty
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw WorkstateStorageError.invalidState(
                "A cognition proposal has an invalid structure"
            )
        }
    }

    private func validateStewardWorklineState(
        _ result: StewardResult,
        activeWorklineIDs: inout Set<String>,
        knownWorklineIDs: inout Set<String>
    ) throws {
        let worklineID = result.worklineId
        switch result.worklineAction {
        case "none":
            return
        case "continue_existing":
            guard activeWorklineIDs.contains(worklineID) else {
                throw WorkstateStorageError.invalidState(
                    "Steward tried to continue an inactive workline: \(worklineID)"
                )
            }
        case "complete_existing":
            guard activeWorklineIDs.remove(worklineID) != nil else {
                throw WorkstateStorageError.invalidState(
                    "Steward tried to complete an inactive workline: \(worklineID)"
                )
            }
            let nextFocus = result.nextFocusedWorklineId ?? ""
            guard nextFocus.isEmpty || activeWorklineIDs.contains(nextFocus) else {
                throw WorkstateStorageError.invalidState(
                    "Steward focused an inactive workline after completion: \(nextFocus)"
                )
            }
        case "start_new":
            guard !worklineID.isEmpty,
                  knownWorklineIDs.insert(worklineID).inserted else {
                throw WorkstateStorageError.invalidState(
                    "Steward tried to reuse an existing workline id: \(worklineID)"
                )
            }
            activeWorklineIDs.insert(worklineID)
        default:
            throw WorkstateStorageError.invalidState(
                "Steward returned an unsupported workline action"
            )
        }
    }

    public func rebuild(
        project: ProjectRecord,
        evidencePath: String,
        sourceThreadIDs: [String],
        scanner: CodexSessionScanner
    ) throws -> ProjectRebuildProposal {
        let request = RebuildRequest(
            mode: "rebuild",
            profile: try runtimeProfile(.rebuild),
            project: RebuildProjectPayload(project: project),
            evidencePath: evidencePath,
            sourceThreadIds: sourceThreadIDs
        )
        let envelope: RuntimeEnvelope<ProjectRebuildProposal> = try run(request, timeout: 600)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(envelope, segmentID: "rebuild:\(project.id)")
        return envelope.result
    }

    public func distill(
        project: ProjectRecord,
        segments: [SessionSegment],
        chunkIndex: Int,
        chunkCount: Int,
        scanner: CodexSessionScanner
    ) throws -> RebuildDistilledChunk {
        let request = DistillRequest(
            mode: "distill",
            profile: try runtimeProfile(.distill),
            project: ProjectPayload(project: project),
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            segments: segments
        )
        let envelope: RuntimeEnvelope<DistillationResult> = try run(request, timeout: 300)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        try appendRun(envelope, segmentID: "rebuild-distill:\(project.id):\(chunkIndex)")
        return RebuildDistilledChunk(
            schemaVersion: 3,
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            evidenceIds: segments.map(\.id),
            items: envelope.result.items
        )
    }

    public func ownerChat(
        project: ProjectRecord,
        history: [ProjectOwnerMessage],
        message: String,
        activeTopicID: String? = nil,
        openBundles: [OpenSemanticBundle] = []
    ) throws -> ProjectOwnerChatResponse {
        let request = OwnerChatRequest(
            mode: "owner_chat",
            profile: try runtimeProfile(.ownerChat),
            project: StewardProjectPayload(project: project),
            openBundles: openBundles
                .filter { $0.projectID == project.id }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(30)
                .map(OpenSemanticBundlePayload.init),
            history: history,
            message: message,
            activeTopicId: activeTopicID ?? ""
        )
        let envelope: RuntimeEnvelope<ProjectOwnerChatResult> = try run(request, timeout: 300)
        try validateCognitionProposal(envelope.result.cognitionProposal)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: CodexSessionScanner())
        try appendRun(envelope, segmentID: "owner-chat:\(project.id):\(UUID().uuidString.lowercased())")
        return ProjectOwnerChatResponse(
            reply: envelope.result.reply,
            topicUpdates: envelope.result.topicUpdates,
            cognitionProposal: envelope.result.cognitionProposal,
            runtimeThreadID: envelope.runtimeThreadId
        )
    }

    public func routeGlobalChat(
        message: String,
        recentMessages: [GlobalChatMessage],
        workspace: WorkspaceSnapshot
    ) throws -> GlobalChatRouteResponse {
        let request = GlobalChatRouteRequest(
            mode: "global_chat_route",
            profile: try runtimeProfile(.route),
            message: message,
            recentMessages: recentMessages,
            projects: workspace.projects.map(PortfolioProjectPayload.init)
        )
        let envelope: RuntimeEnvelope<GlobalChatRouteResult> = try run(request, timeout: 300)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: CodexSessionScanner())
        guard workspace.project(id: envelope.result.projectId) != nil else {
            throw WorkstateStorageError.invalidState(
                "Global chat Router returned unknown project \(envelope.result.projectId)"
            )
        }
        let segmentID = "global-chat-route:\(UUID().uuidString.lowercased())"
        try appendRun(envelope, segmentID: segmentID)
        return GlobalChatRouteResponse(
            projectID: envelope.result.projectId,
            reason: envelope.result.reason,
            runtimeThreadID: envelope.runtimeThreadId
        )
    }

    public func collaborationSteward(
        profile: CollaborationProfile,
        history: [CollaborationMessage],
        message: String
    ) throws -> CollaborationStewardResponse {
        let request = CollaborationStewardRequest(
            mode: "collaboration_steward",
            profile: try runtimeProfile(.collaborationSteward),
            collaborationProfile: profile,
            history: history,
            message: message
        )
        let envelope: RuntimeEnvelope<CollaborationStewardResult> = try run(request, timeout: 300)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: CodexSessionScanner())
        let segmentID = "collaboration-steward:\(UUID().uuidString.lowercased())"
        try appendRun(envelope, segmentID: segmentID)
        return CollaborationStewardResponse(
            reply: envelope.result.reply,
            mutations: envelope.result.mutations,
            runtimeThreadID: envelope.runtimeThreadId
        )
    }

    public func composeBrief(
        _ brief: DailyBrief,
        workspace: WorkspaceSnapshot,
        scanner: CodexSessionScanner
    ) throws -> DailyBriefNarrative {
        let request = BriefRequest(
            mode: "brief",
            profile: try runtimeProfile(.brief),
            dateKey: brief.dateKey,
            sourceRevision: brief.sourceRevision,
            projects: try brief.projects.map { projectBrief in
                guard let project = workspace.project(id: projectBrief.projectID) else {
                    throw WorkstateStorageError.missingProject(projectBrief.projectID)
                }
                return BriefProjectPayload(brief: projectBrief, project: project)
            }
        )
        let envelope: RuntimeEnvelope<BriefComposerResult> = try run(request, timeout: 300)
        try excludePersistentRuntimeThread(envelope.runtimeThreadId, scanner: scanner)
        let segmentID = "brief:\(brief.dateKey):\(brief.sourceRevision.prefix(12))"
        try appendRun(envelope, segmentID: segmentID)
        return DailyBriefNarrative(
            sourceRevision: brief.sourceRevision,
            overview: envelope.result.overview,
            projectSummaries: envelope.result.projectSummaries.map {
                DailyProjectNarrative(projectID: $0.projectId, summary: $0.summary)
            },
            nextStep: envelope.result.nextStep
        )
    }

    public func dailyInputTokens(now: Date = Date()) throws -> Int {
        let usageURL = runtimeRoot.appendingPathComponent("agent-usage.jsonl")
        let url = FileManager.default.fileExists(atPath: usageURL.path)
            ? usageURL
            : runtimeRoot.appendingPathComponent("agent-runs.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let start = Calendar.current.startOfDay(for: now)
        let data = try Data(contentsOf: url)
        return data.split(separator: 0x0A).reduce(into: 0) { total, line in
            guard let record = try? WorkstateCoding.makeDecoder().decode(
                AgentUsageJournalRecord.self,
                from: Data(line)
            ),
                  record.timestamp >= start else { return }
            total += record.usage?.inputTokens ?? 0
        }
    }

    private func runtimeProfile(_ role: AgentRole) throws -> RuntimeProfilePayload {
        let repository = WorkstateRepository(paths: WorkstatePaths(root: runtimeRoot))
        let workspaceHasProjects = (try? repository.load().projects.isEmpty == false) ?? false
        let settings = try settingsRepository.load(workspaceHasProjects: workspaceHasProjects)
        return RuntimeProfilePayload(settings.profile(for: role))
    }

    private func boundedCognitionSegments(_ segments: [SessionSegment]) -> [SessionSegment] {
        let maximumBytes = 256 * 1024
        var result: [SessionSegment] = []
        var bytes = 0
        for segment in segments.sorted(by: { $0.timestamp > $1.timestamp }).prefix(80) {
            let size = (try? WorkstateCoding.makeEncoder(pretty: false).encode(segment).count) ?? Int.max
            guard size <= maximumBytes, bytes + size <= maximumBytes else { continue }
            result.append(segment)
            bytes += size
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private func fallbackCognitionSegment(
        source: SourceReference,
        messages: [ConversationMessage]
    ) -> SessionSegment? {
        guard let turnID = source.turnIDs.last, !messages.isEmpty else { return nil }
        let userText = messages
            .filter { $0.role == "user" }
            .map(\.text)
            .joined(separator: "\n\n")
        let assistantText = messages.last(where: { $0.role == "assistant" })?.text ?? ""
        guard !userText.isEmpty || !assistantText.isEmpty else { return nil }
        let timestamp = messages.compactMap(\.timestamp).max() ?? .distantPast
        let startOffset = source.startOffset ?? 0
        return SessionSegment(
            threadID: source.threadID,
            turnID: turnID,
            sourcePath: source.locator,
            startOffset: startOffset,
            endOffset: max(startOffset, source.endOffset ?? startOffset),
            cwd: "",
            userText: userText,
            assistantText: assistantText,
            timestamp: timestamp,
            relatedTurnIDs: source.turnIDs,
            sourceSpans: source.messageSpans
        )
    }

    private func decodeCognitionSection(
        _ section: CognitionDraftSectionPayload,
        sourceIDs: [String]
    ) throws -> ProjectCognitionSection {
        var object = try JSONSerialization.jsonObject(
            with: WorkstateCoding.makeEncoder(pretty: false).encode(section)
        ) as? [String: Any] ?? [:]
        object["sourceIDs"] = sourceIDs
        return try WorkstateCoding.makeDecoder().decode(
            ProjectCognitionSection.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func writeCognitionDraftAttempt(_ record: CognitionDraftAttemptRecord) throws {
        let url = try cognitionDraftAttemptURL(projectID: record.projectID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try WorkstateCoding.makeEncoder().encode(record)
        guard data.count <= 8 * 1024 * 1024 else {
            throw WorkstateStorageError.invalidState(
                "Cognition draft diagnostic exceeded 8 MiB"
            )
        }
        try data.write(to: url, options: .atomic)
    }

    private func updateCognitionDraftAttempt(
        projectID: String,
        status: String,
        error: String
    ) throws {
        let url = try cognitionDraftAttemptURL(projectID: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkstateStorageError.invalidState(
                "Missing cognition draft diagnostic for \(projectID)"
            )
        }
        var record = try WorkstateCoding.makeDecoder().decode(
            CognitionDraftAttemptRecord.self,
            from: Data(contentsOf: url)
        )
        record.status = status
        record.error = error
        record.updatedAt = Date()
        try writeCognitionDraftAttempt(record)
    }

    private func cognitionDraftAttemptURL(projectID: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard let fileName = projectID.addingPercentEncoding(withAllowedCharacters: allowed),
              !fileName.isEmpty else {
            throw WorkstateStorageError.invalidState("Invalid cognition project id")
        }
        return runtimeRoot
            .appendingPathComponent("cognition-attempts", isDirectory: true)
            .appendingPathComponent("\(fileName)-latest.json")
    }

    private func excludePersistentRuntimeThread(
        _ threadID: String,
        scanner: CodexSessionScanner
    ) throws {
        guard !threadID.isEmpty, !threadID.hasPrefix("ephemeral-") else { return }
        try scanner.excludeThread(threadID)
    }

    private func run<Request: Encodable, Result: Decodable>(
        _ request: Request,
        timeout: TimeInterval
    ) throws -> RuntimeEnvelope<Result> {
        guard FileManager.default.isExecutableFile(atPath: nodePath) else {
            throw AgentRuntimeError.missingNode(nodePath)
        }
        guard FileManager.default.fileExists(atPath: runtimeScript.path) else {
            throw AgentRuntimeError.missingRuntime(runtimeScript.path)
        }
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        let workerLock = try AgentWorkerLock(root: runtimeRoot)
        defer { workerLock.unlock() }
        let requestData = try WorkstateCoding.makeEncoder().encode(request)
        guard requestData.count <= 2 * 1024 * 1024 else {
            throw AgentRuntimeError.failed("Agent request exceeded 2 MiB")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [runtimeScript.path]
        process.currentDirectoryURL = runtimeScript.deletingLastPathComponent().deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["WORKSTATE_RUNTIME_ROOT"] = runtimeRoot.path
        environment["WORKSTATE_SOURCE_CODEX_HOME"] = environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true).path
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let outputCapture = PipeCapture(pipe: output, maximumBytes: 8 * 1024 * 1024)
        let errorCapture = PipeCapture(pipe: error, maximumBytes: 2 * 1024 * 1024)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        outputCapture.start()
        errorCapture.start()
        defer {
            outputCapture.cancel()
            errorCapture.cancel()
        }
        try process.run()
        processRegistry.register(process)
        defer { processRegistry.clear(process) }
        do {
            try input.fileHandleForWriting.write(contentsOf: requestData)
            try input.fileHandleForWriting.close()
        } catch {
            processRegistry.terminate(process)
            throw AgentRuntimeError.failed("Could not stream the Agent request: \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            processRegistry.terminate(process)
            throw AgentRuntimeError.timedOut(Int(timeout))
        }

        let outputResult = outputCapture.finish()
        let errorResult = errorCapture.finish()
        guard !outputResult.exceededLimit else {
            throw AgentRuntimeError.failed("Agent runtime output exceeded 8 MiB")
        }
        let errorText = String(
            data: errorResult.data,
            encoding: .utf8
        ) ?? ""
        guard !errorResult.exceededLimit else {
            throw AgentRuntimeError.failed("Agent runtime error output exceeded 2 MiB")
        }
        guard process.terminationStatus == 0 else {
            throw AgentRuntimeError.failed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try JSONDecoder().decode(RuntimeEnvelope<Result>.self, from: outputResult.data)
    }

    private func appendRun<Result: Encodable>(
        _ envelope: RuntimeEnvelope<Result>,
        segmentID: String
    ) throws {
        let url = runtimeRoot.appendingPathComponent("agent-runs.jsonl")
        try rotateRunLogIfNeeded(url)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let record = AgentRunRecord(
            timestamp: Date(),
            mode: envelope.mode,
            segmentID: segmentID,
            runtimeThreadID: envelope.runtimeThreadId,
            usage: envelope.usage,
            telemetry: envelope.telemetry
        )
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func rotateRunLogIfNeeded(_ url: URL, maximumBytes: Int = 2 * 1024 * 1024) throws {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= maximumBytes else { return }
        let previous = url.deletingPathExtension().appendingPathExtension("previous.jsonl")
        if FileManager.default.fileExists(atPath: previous.path) {
            try FileManager.default.removeItem(at: previous)
        }
        try FileManager.default.moveItem(at: url, to: previous)
    }

}

private final class AgentWorkerLock {
    private var descriptor: Int32

    init(root: URL) throws {
        let url = root.appendingPathComponent("agent-worker.lock")
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw AgentRuntimeError.failed("Could not create the Agent worker lock")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            descriptor = -1
            throw AgentRuntimeError.busy
        }
    }

    func unlock() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        unlock()
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let pipe: Pipe
    private let maximumBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var exceededLimit = false

    init(pipe: Pipe, maximumBytes: Int) {
        self.pipe = pipe
        self.maximumBytes = maximumBytes
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.captureAvailableData(from: handle)
        }
    }

    func finish() -> (data: Data, exceededLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        pipe.fileHandleForReading.readabilityHandler = nil
        while true {
            let remaining = (try? pipe.fileHandleForReading.read(upToCount: 1024 * 1024)) ?? nil
            guard let remaining, !remaining.isEmpty else { break }
            append(remaining)
        }
        return (data, exceededLimit)
    }

    func cancel() {
        lock.lock()
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.unlock()
    }

    private func captureAvailableData(from handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        append(chunk)
    }

    private func append(_ chunk: Data) {
        let remainingCapacity = maximumBytes - data.count
        guard remainingCapacity > 0 else {
            exceededLimit = true
            return
        }
        if chunk.count > remainingCapacity {
            data.append(chunk.prefix(remainingCapacity))
            exceededLimit = true
        } else {
            data.append(chunk)
        }
    }
}

private final class AgentProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?

    func register(_ process: Process) {
        lock.lock()
        activeProcess = process
        lock.unlock()
    }

    func clear(_ process: Process) {
        lock.lock()
        if activeProcess?.processIdentifier == process.processIdentifier {
            activeProcess = nil
        }
        lock.unlock()
    }

    func cancelActiveProcess() {
        lock.lock()
        let process = activeProcess
        lock.unlock()
        guard let process else { return }
        terminate(process)
    }

    func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            let descendants = Process()
            descendants.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            descendants.arguments = ["-KILL", "-P", String(process.processIdentifier)]
            try? descendants.run()
            descendants.waitUntilExit()
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

public struct RouteResult: Codable, Equatable, Sendable {
    public var action: String
    public var projectId: String
    public var projectName: String
    public var projectSummary: String
    public var disposition: String?
    public var bundleId: String?
    public var bundleTitle: String?
    public var bundleSummary: String?
    public var signals: [RouteSignal]?
    public var confidence: Double
    public var reason: String

    public init(
        action: String,
        projectId: String,
        projectName: String,
        projectSummary: String,
        disposition: String? = nil,
        bundleId: String? = nil,
        bundleTitle: String? = nil,
        bundleSummary: String? = nil,
        signals: [RouteSignal]? = nil,
        confidence: Double,
        reason: String
    ) {
        self.action = action
        self.projectId = projectId
        self.projectName = projectName
        self.projectSummary = projectSummary
        self.disposition = disposition
        self.bundleId = bundleId
        self.bundleTitle = bundleTitle
        self.bundleSummary = bundleSummary
        self.signals = signals
        self.confidence = confidence
        self.reason = reason
    }

    public var normalizedDisposition: String {
        disposition ?? (action == "ignore" ? "ignore" : "commit")
    }
}

public struct RouteSignal: Codable, Equatable, Sendable {
    public var type: String
    public var authority: String
    public var summary: String

    public init(type: String, authority: String, summary: String) {
        self.type = type
        self.authority = authority
        self.summary = summary
    }
}

public struct BatchRouteDecision: Codable, Equatable, Sendable {
    public var segmentId: String
    public var action: String
    public var projectId: String
    public var projectName: String
    public var projectSummary: String
    public var disposition: String?
    public var bundleId: String?
    public var bundleTitle: String?
    public var bundleSummary: String?
    public var signals: [RouteSignal]?
    public var confidence: Double
    public var reason: String

    public var routeResult: RouteResult {
        RouteResult(
            action: action,
            projectId: projectId,
            projectName: projectName,
            projectSummary: projectSummary,
            disposition: disposition,
            bundleId: bundleId,
            bundleTitle: bundleTitle,
            bundleSummary: bundleSummary,
            signals: signals,
            confidence: confidence,
            reason: reason
        )
    }
}

public struct StewardResult: Codable, Equatable, Sendable {
    public var classification: String
    public var title: String
    public var summary: String
    public var worklineAction: String
    public var worklineId: String
    public var worklineTitle: String
    public var worklineObjective: String
    public var branchFromWorklineId: String
    public var isParallel: Bool?
    public var nextFocusedWorklineId: String?
    public var closureDisposition: String?
    public var carryoverTitle: String?
    public var carryoverSummary: String?
    public var carryoverQuestions: [String]?
    public var kind: String
    public var stage: String
    public var delivery: String
    public var facts: [String]
    public var contextPatch: StewardContextPatch?
    public var cognitionProposal: StewardCognitionProposal?
    public var turningPoint: StewardTurningPoint?
    public var topicUpdates: [StewardTopicUpdate]?

    public init(
        classification: String,
        title: String,
        summary: String,
        worklineAction: String,
        worklineId: String,
        worklineTitle: String,
        worklineObjective: String,
        branchFromWorklineId: String,
        isParallel: Bool? = nil,
        nextFocusedWorklineId: String? = nil,
        closureDisposition: String? = nil,
        carryoverTitle: String? = nil,
        carryoverSummary: String? = nil,
        carryoverQuestions: [String]? = nil,
        kind: String,
        stage: String,
        delivery: String,
        facts: [String],
        contextPatch: StewardContextPatch? = nil,
        cognitionProposal: StewardCognitionProposal? = nil,
        turningPoint: StewardTurningPoint? = nil,
        topicUpdates: [StewardTopicUpdate]? = nil
    ) {
        self.classification = classification
        self.title = title
        self.summary = summary
        self.worklineAction = worklineAction
        self.worklineId = worklineId
        self.worklineTitle = worklineTitle
        self.worklineObjective = worklineObjective
        self.branchFromWorklineId = branchFromWorklineId
        self.isParallel = isParallel
        self.nextFocusedWorklineId = nextFocusedWorklineId
        self.closureDisposition = closureDisposition
        self.carryoverTitle = carryoverTitle
        self.carryoverSummary = carryoverSummary
        self.carryoverQuestions = carryoverQuestions
        self.kind = kind
        self.stage = stage
        self.delivery = delivery
        self.facts = facts
        self.contextPatch = contextPatch
        self.cognitionProposal = cognitionProposal
        self.turningPoint = turningPoint
        self.topicUpdates = topicUpdates
    }
}

public struct StewardCognitionProposal: Codable, Equatable, Sendable {
    public var operation: String
    public var summary: String
    public var beforeSectionIDs: [String]
    public var afterSections: [StewardCognitionSectionProposal]

    public var isEmpty: Bool {
        operation == "none"
    }
}

public struct StewardCognitionSectionProposal: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var purpose: String
    public var inclusionRules: [String]
    public var exclusionRules: [String]
    public var updateTriggers: [String]
    public var coverage: [String]
    public var order: Int
}

public struct StewardTurningPoint: Codable, Equatable, Sendable {
    public var scope: String
    public var title: String
    public var beforeMeaning: String
    public var afterMeaning: String

    public var isEmpty: Bool {
        scope == "none"
    }
}

public struct ProjectCognitionDraftGeneration: Equatable, Sendable {
    public var sections: [ProjectCognitionSection]
    public var missingContext: [String]
    public var isReady: Bool

    public init(
        sections: [ProjectCognitionSection],
        missingContext: [String],
        isReady: Bool
    ) {
        self.sections = sections
        self.missingContext = missingContext
        self.isReady = isReady
    }
}

private struct CognitionDraftResult: Codable {
    var isReady: Bool
    var missingContext: [String]
    var sections: [CognitionDraftSectionPayload]
}

private struct CognitionDraftAttemptRecord: Codable {
    var schemaVersion = 1
    var projectID: String
    var status: String
    var error: String
    var receivedAt = Date()
    var updatedAt = Date()
    var runtimeThreadID: String
    var usage: AgentUsage?
    var telemetry: AgentRunTelemetry?
    var result: CognitionDraftResult
}

private struct CognitionDraftSectionPayload: Codable {
    var id: String
    var title: String
    var body: String
    var purpose: String
    var inclusionRules: [String]
    var exclusionRules: [String]
    var updateTriggers: [String]
    var coverage: [String]
    var order: Int
    var sourceIDs: [String]
}

public struct StewardTopicUpdate: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var status: String
    public var kind: String
    public var disposition: String
    public var currentUnderstanding: String
    public var proposedDirection: String
    public var deferredReason: String
    public var revisitTrigger: String
    public var openQuestions: [String]
}

public struct StewardUnderstandingPatch: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var status: String

    public init(id: String, text: String, status: String) {
        self.id = id
        self.text = text
        self.status = status
    }
}

public struct StewardDecisionPatch: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var rationale: String

    public init(id: String, text: String, rationale: String) {
        self.id = id
        self.text = text
        self.rationale = rationale
    }
}

public struct StewardContextPatch: Codable, Equatable, Sendable {
    public var currentSummary: String
    public var revisionTitle: String
    public var revisionSummary: String
    public var revisionStatus: String
    public var changes: [String]
    public var understandingUpserts: [StewardUnderstandingPatch]
    public var supersededUnderstandingIds: [String]
    public var decisionUpserts: [StewardDecisionPatch]
    public var supersededDecisionIds: [String]
    public var forbiddenDirectionAdditions: [String]
    public var forbiddenDirectionRemovals: [String]

    public init(
        currentSummary: String = "",
        revisionTitle: String = "",
        revisionSummary: String = "",
        revisionStatus: String = "observed",
        changes: [String] = [],
        understandingUpserts: [StewardUnderstandingPatch] = [],
        supersededUnderstandingIds: [String] = [],
        decisionUpserts: [StewardDecisionPatch] = [],
        supersededDecisionIds: [String] = [],
        forbiddenDirectionAdditions: [String] = [],
        forbiddenDirectionRemovals: [String] = []
    ) {
        self.currentSummary = currentSummary
        self.revisionTitle = revisionTitle
        self.revisionSummary = revisionSummary
        self.revisionStatus = revisionStatus
        self.changes = changes
        self.understandingUpserts = understandingUpserts
        self.supersededUnderstandingIds = supersededUnderstandingIds
        self.decisionUpserts = decisionUpserts
        self.supersededDecisionIds = supersededDecisionIds
        self.forbiddenDirectionAdditions = forbiddenDirectionAdditions
        self.forbiddenDirectionRemovals = forbiddenDirectionRemovals
    }

    public var isEmpty: Bool {
        currentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && understandingUpserts.isEmpty
            && supersededUnderstandingIds.isEmpty
            && decisionUpserts.isEmpty
            && supersededDecisionIds.isEmpty
            && forbiddenDirectionAdditions.isEmpty
            && forbiddenDirectionRemovals.isEmpty
    }
}

public struct BatchStewardChange: Codable, Equatable, Sendable {
    public var evidenceIds: [String]
    public var result: StewardResult
}

public struct BatchStewardResult: Codable, Equatable, Sendable {
    public var changes: [BatchStewardChange]

    public init(changes: [BatchStewardChange]) {
        self.changes = changes
    }
}

public struct DistillationResult: Codable, Equatable, Sendable {
    public var items: [DistilledEvidenceItem]
}

public struct ProjectOwnerChatResult: Codable, Equatable, Sendable {
    public var reply: String
    public var topicUpdates: [ProjectOwnerTopicUpdate]
    public var cognitionProposal: StewardCognitionProposal
}

public struct ProjectOwnerChatResponse: Equatable, Sendable {
    public var reply: String
    public var topicUpdates: [ProjectOwnerTopicUpdate]
    public var cognitionProposal: StewardCognitionProposal
    public var runtimeThreadID: String
}

public struct GlobalChatRouteResponse: Equatable, Sendable {
    public var projectID: String
    public var reason: String
    public var runtimeThreadID: String
}

public struct CollaborationStewardResponse: Equatable, Sendable {
    public var reply: String
    public var mutations: [CollaborationProfileMutation]
    public var runtimeThreadID: String
}

private struct CollaborationStewardResult: Codable {
    var reply: String
    var mutations: [CollaborationProfileMutation]
}

private struct GlobalChatRouteResult: Codable {
    var projectId: String
    var reason: String
}

public struct ProjectOwnerTopicUpdate: Codable, Equatable, Sendable {
    public var action: String
    public var topicId: String
    public var title: String
    public var summary: String
    public var status: String
    public var kind: String
    public var disposition: String
    public var currentUnderstanding: String
    public var proposedDirection: String
    public var deferredReason: String
    public var revisitTrigger: String
    public var openQuestions: [String]
    public var noteKind: String
    public var noteTitle: String
    public var noteDetail: String
}

public struct BriefComposerResult: Codable, Equatable, Sendable {
    public var overview: String
    public var projectSummaries: [BriefProjectSummaryResult]
    public var nextStep: String
}

public struct BriefProjectSummaryResult: Codable, Equatable, Sendable {
    public var projectId: String
    public var summary: String
}

public struct DistilledEvidenceItem: Codable, Equatable, Sendable {
    public var category: String
    public var title: String
    public var summary: String
    public var timestamp: String
    public var worklineHint: String
    public var status: String
    public var kind: String
    public var stage: String
    public var delivery: String
    public var facts: [String]
    public var decisions: [String]
    public var evidenceIds: [String]
}

public struct RebuildDistilledChunk: Codable, Equatable, Sendable {
    public var schemaVersion: Int?
    public var chunkIndex: Int
    public var chunkCount: Int
    public var evidenceIds: [String]
    public var items: [DistilledEvidenceItem]

    public init(
        schemaVersion: Int? = 3,
        chunkIndex: Int,
        chunkCount: Int,
        evidenceIds: [String],
        items: [DistilledEvidenceItem]
    ) {
        self.schemaVersion = schemaVersion
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.evidenceIds = evidenceIds
        self.items = items
    }
}

private struct RouteRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segment: SessionSegment
    var projects: [RoutingProjectPayload]
    var priorRoute: RouteBindingPayload?
    var recentTurns: [SessionSegment]
    var openBundles: [OpenSemanticBundlePayload]
}

private struct ResetProjectOwnerSessionRequest: Codable {
    var mode: String
    var projectId: String
}

private struct ResetProjectOwnerSessionResult: Codable {
    var projectId: String
    var removedThreadId: String?
}

private struct OpenSemanticBundlePayload: Codable {
    var id: String
    var threadID: String
    var projectId: String
    var disposition: String
    var title: String
    var summary: String
    var evidenceCount: Int
    var updatedAt: Date

    init(bundle: OpenSemanticBundle) {
        id = bundle.id
        threadID = bundle.threadID
        projectId = bundle.projectID
        disposition = bundle.disposition
        title = boundedText(bundle.title, limit: 300)
        summary = boundedText(bundle.summary, limit: 2_000)
        evidenceCount = bundle.evidenceIDs.count
        updatedAt = bundle.updatedAt
    }
}

private struct BatchRouteRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segments: [BatchRouteSegmentPayload]
    var projects: [RoutingProjectPayload]
    var routeHints: [BatchRouteHintPayload]
    var recentTurns: [BatchRouteSegmentPayload]
    var openBundles: [OpenSemanticBundlePayload]
}

private struct RoutingProjectPayload: Codable {
    var id: String
    var name: String
    var purpose: String
    var status: String

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        purpose = boundedText(project.context.purpose, limit: 2_000)
        status = project.status.rawValue
    }
}

private struct BatchRouteSegmentPayload: Codable {
    var id: String
    var threadID: String
    var turnID: String
    var cwd: String
    var userText: String
    var assistantText: String
    var timestamp: Date

    init(segment: SessionSegment) {
        id = segment.id
        threadID = segment.threadID
        turnID = segment.turnID
        cwd = segment.cwd
        userText = segment.userText
        assistantText = segment.assistantText
        timestamp = segment.timestamp
    }
}

private struct BatchRouteHintPayload: Codable {
    var threadID: String
    var projectID: String
}

private struct BatchRouteResult: Codable {
    var routes: [BatchRoutePacket]
}

private struct BatchRoutePacket: Codable {
    var startPosition: Int
    var endPosition: Int
    var action: String
    var projectId: String
    var projectName: String
    var projectSummary: String
    var disposition: String?
    var bundleId: String?
    var bundleTitle: String?
    var bundleSummary: String?
    var signals: [RouteSignal]?
    var confidence: Double
    var reason: String

    var routeResult: RouteResult {
        RouteResult(
            action: action,
            projectId: projectId,
            projectName: projectName,
            projectSummary: projectSummary,
            disposition: disposition,
            bundleId: bundleId,
            bundleTitle: bundleTitle,
            bundleSummary: bundleSummary,
            signals: signals,
            confidence: confidence,
            reason: reason
        )
    }
}

private struct PortfolioProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = project.context.currentSummary
        purpose = project.context.purpose
        status = project.status.rawValue
    }
}

private struct RouteBindingPayload: Codable {
    var threadID: String
    var turnID: String
    var projectID: String
    var updatedAt: Date

    init(binding: ThreadRouteBinding) {
        threadID = binding.threadID
        turnID = binding.turnID
        projectID = binding.projectID
        updatedAt = binding.updatedAt
    }
}

private struct StewardRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segment: SessionSegment
    var project: StewardProjectPayload
}

private struct BatchStewardRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var segments: [SessionSegment]
    var project: StewardProjectPayload
}

private struct CognitionDraftRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: CognitionDraftProjectPayload
    var segments: [SessionSegment]
}

private struct RebuildRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: RebuildProjectPayload
    var evidencePath: String
    var sourceThreadIds: [String]
}

private struct DistillRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: ProjectPayload
    var chunkIndex: Int
    var chunkCount: Int
    var segments: [SessionSegment]
}

private struct OwnerChatRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var project: StewardProjectPayload
    var openBundles: [OpenSemanticBundlePayload]
    var history: [ProjectOwnerMessage]
    var message: String
    var activeTopicId: String
}

private struct GlobalChatRouteRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var message: String
    var recentMessages: [GlobalChatMessage]
    var projects: [PortfolioProjectPayload]
}

private struct CollaborationStewardRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var collaborationProfile: CollaborationProfile
    var history: [CollaborationMessage]
    var message: String
}

private struct BriefRequest: Codable {
    var mode: String
    var profile: RuntimeProfilePayload
    var dateKey: String
    var sourceRevision: String
    var projects: [BriefProjectPayload]
}

private struct RuntimeProfilePayload: Codable {
    var model: String
    var reasoning: String

    init(_ profile: AgentProfile) {
        model = profile.modelID
        reasoning = profile.effort.rawValue
    }
}

private struct BriefProjectPayload: Codable {
    var projectId: String
    var projectName: String
    var projectStatus: String
    var records: [BriefRecordPayload]

    init(brief: DailyProjectBrief, project: ProjectRecord) {
        projectId = brief.projectID
        projectName = brief.projectName
        projectStatus = project.status.rawValue
        records = (brief.progress + brief.confirmed + brief.unresolved + brief.resumePoints)
            .map(BriefRecordPayload.init)
    }
}

private struct BriefRecordPayload: Codable {
    var id: String
    var kind: String
    var title: String
    var detail: String

    init(item: DailyBriefItem) {
        id = item.id
        kind = item.kind.rawValue
        title = item.title
        detail = item.detail
    }
}

private func boundedText(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    return String(value.prefix(limit))
}

private struct ProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var focusedWorklineId: String
    var activeWorklines: [WorklinePayload]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = boundedText(project.summary, limit: 4_000)
        purpose = boundedText(project.context.purpose, limit: 2_000)
        status = project.status.rawValue
        focusedWorklineId = project.focusedTaskID ?? ""
        activeWorklines = project.tasks
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map(WorklinePayload.init)
    }
}

private struct StewardProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var focusedWorklineId: String
    var activeWorklines: [WorklinePayload]
    var identity: CognitionIdentityPayload
    var cognition: StewardCognitionPayload?
    var recentDeltas: [DeltaPayload]
    var topics: [TopicPayload]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = boundedText(project.summary, limit: 4_000)
        purpose = boundedText(project.context.purpose, limit: 2_000)
        status = project.status.rawValue
        focusedWorklineId = project.focusedTaskID ?? ""
        activeWorklines = project.tasks
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map(WorklinePayload.init)
        identity = CognitionIdentityPayload(project: project)
        cognition = project.context.cognition.map(StewardCognitionPayload.init)
        recentDeltas = project.events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(6)
            .map(DeltaPayload.init)
        topics = project.topics
            .filter { $0.status == .captured || $0.status == .discussing }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(30)
            .map(TopicPayload.init)
    }
}

private struct CognitionIdentityPayload: Codable {
    var id: String
    var name: String
    var purpose: String
    var summary: String

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        purpose = boundedText(project.context.purpose, limit: 2_000)
        summary = boundedText(project.summary, limit: 4_000)
    }
}

private struct CognitionDraftProjectPayload: Codable {
    var identity: CognitionIdentityPayload

    init(project: ProjectRecord) {
        identity = CognitionIdentityPayload(project: project)
    }
}

private struct StewardCognitionPayload: Codable {
    var state: ProjectCognitionState
    var version: Int
    var sections: [ProjectCognitionSection]
    var pendingRevisions: [PendingCognitionRevisionPayload]

    init(document: ProjectCognitionDocument) {
        state = document.state
        version = document.version
        sections = document.sections
        pendingRevisions = document.revisions
            .filter { $0.status == .pending }
            .map(PendingCognitionRevisionPayload.init)
    }
}

private struct PendingCognitionRevisionPayload: Codable {
    var id: String
    var operation: ProjectCognitionRevisionOperation
    var status: ProjectCognitionRevisionStatus
    var baseVersion: Int
    var touchedSectionIDs: [String]
    var rationale: String
    var sourceIDs: [String]

    init(revision: ProjectCognitionRevision) {
        id = revision.id
        operation = revision.operation
        status = revision.status
        baseVersion = revision.baseVersion
        touchedSectionIDs = Array(
            Set(revision.beforeSections.map(\.id) + revision.afterSections.map(\.id))
        ).sorted()
        rationale = boundedText(revision.rationale, limit: 1_000)
        sourceIDs = revision.sourceIDs
    }
}

private struct StewardUnderstandingPayload: Codable {
    var id: String
    var text: String
    var status: String

    init(_ statement: ContextStatement) {
        id = statement.id
        text = boundedText(statement.text, limit: 2_000)
        status = statement.status.rawValue
    }
}

private struct StewardDecisionPayload: Codable {
    var id: String
    var text: String
    var rationale: String

    init(_ decision: DecisionRecord) {
        id = decision.id
        text = boundedText(decision.text, limit: 2_000)
        rationale = boundedText(decision.rationale, limit: 1_000)
    }
}

private struct TopicPayload: Codable {
    var id: String
    var title: String
    var summary: String
    var status: String
    var kind: String
    var disposition: String
    var currentUnderstanding: String
    var proposedDirection: String
    var openQuestions: [String]

    init(topic: ProjectTopic) {
        id = topic.id
        title = boundedText(topic.title, limit: 300)
        summary = boundedText(topic.summary, limit: 2_000)
        status = topic.status.rawValue
        kind = topic.kind.rawValue
        disposition = (topic.disposition ?? .futureDecision).rawValue
        currentUnderstanding = boundedText(topic.currentUnderstanding, limit: 2_000)
        proposedDirection = boundedText(topic.proposedDirection, limit: 2_000)
        openQuestions = topic.openQuestions.prefix(10).map { boundedText($0, limit: 500) }
    }
}

private struct RebuildProjectPayload: Codable {
    var id: String
    var name: String
    var summary: String
    var purpose: String
    var status: String
    var activeWorklines: [WorklinePayload]
    var currentUnderstanding: [StewardUnderstandingPayload]
    var acceptedDecisions: [StewardDecisionPayload]
    var forbiddenDirections: [String]

    init(project: ProjectRecord) {
        id = project.id
        name = project.name
        summary = boundedText(project.context.currentSummary, limit: 4_000)
        purpose = boundedText(project.context.purpose, limit: 2_000)
        status = project.status.rawValue
        activeWorklines = project.activeTasks.prefix(20).map(WorklinePayload.init)
        currentUnderstanding = project.context.understanding.prefix(50).map(StewardUnderstandingPayload.init)
        acceptedDecisions = project.context.acceptedDecisions.prefix(50).map(StewardDecisionPayload.init)
        forbiddenDirections = project.context.forbiddenDirections.prefix(30).map {
            boundedText($0, limit: 1_000)
        }
    }
}

private struct WorklinePayload: Codable {
    var id: String
    var title: String
    var objective: String
    var status: String
    var stage: String

    init(task: TaskRecord) {
        id = task.id
        title = boundedText(task.title, limit: 300)
        objective = boundedText(task.objective, limit: 2_000)
        status = task.status.rawValue
        stage = task.currentStage.rawValue
    }
}

private struct DeltaPayload: Codable {
    var title: String
    var summary: String
    var kind: String
    var timestamp: Date

    init(event: ProjectEvent) {
        title = boundedText(event.title, limit: 300)
        summary = boundedText(event.summary, limit: 2_000)
        kind = event.kind.rawValue
        timestamp = event.timestamp
    }
}

private struct RuntimeEnvelope<Result: Codable>: Codable {
    var mode: String
    var runtimeThreadId: String
    var usage: AgentUsage?
    var telemetry: AgentRunTelemetry?
    var result: Result
}

private struct AgentUsage: Codable, Equatable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
    }
}

private struct AgentRunTelemetry: Codable, Equatable {
    var model: String
    var reasoning: String
    var promptBytes: Int
    var durationMilliseconds: Int
    var codexProcessID: Int32

    enum CodingKeys: String, CodingKey {
        case model
        case reasoning
        case promptBytes = "prompt_bytes"
        case durationMilliseconds = "duration_ms"
        case codexProcessID = "codex_pid"
    }
}

private struct AgentRunRecord: Codable {
    var timestamp: Date
    var mode: String
    var segmentID: String
    var runtimeThreadID: String
    var usage: AgentUsage?
    var telemetry: AgentRunTelemetry?
}

private struct AgentUsageJournalRecord: Codable {
    var timestamp: Date
    var usage: AgentUsage?
}


public enum AgentRuntimeError: LocalizedError {
    case missingNode(String)
    case missingRuntime(String)
    case failed(String)
    case timedOut(Int)
    case busy

    public var errorDescription: String? {
        switch self {
        case .missingNode(let path): "Node.js executable not found at \(path)"
        case .missingRuntime(let path): "Workstate Agent Runtime not found at \(path)"
        case .failed(let message): "Workstate Agent Runtime failed: \(message)"
        case .timedOut(let seconds): "Workstate Agent Runtime timed out after \(seconds) seconds"
        case .busy: "Another Workstate Agent batch is already running"
        }
    }
}
