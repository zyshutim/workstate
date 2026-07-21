import Foundation
import WorkstateCore

public struct ColdStartProjectSeed: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var purpose: String

    public init(id: String = UUID().uuidString.lowercased(), name: String, purpose: String) {
        self.id = id
        self.name = name
        self.purpose = purpose
    }
}

public struct ColdStartConfiguration: Codable, Equatable, Sendable {
    public var selectedThreadIDs: Set<String>
    public var startDate: Date
    public var endDate: Date
    public var projectSeeds: [ColdStartProjectSeed]
    public var sessionProjectHints: [String: String]
    public var settings: WorkstateSettings

    public init(
        selectedThreadIDs: Set<String>,
        startDate: Date,
        endDate: Date,
        projectSeeds: [ColdStartProjectSeed],
        sessionProjectHints: [String: String] = [:],
        settings: WorkstateSettings
    ) {
        self.selectedThreadIDs = selectedThreadIDs
        self.startDate = startDate
        self.endDate = endDate
        self.projectSeeds = projectSeeds
        self.sessionProjectHints = sessionProjectHints
        self.settings = settings
    }
}

public enum ColdStartPhase: String, Codable, Sendable {
    case preparing
    case importing
    case routing
    case distilling
    case rebuilding
    case completed
}

public struct ColdStartProgress: Sendable {
    public var phase: ColdStartPhase
    public var completed: Int
    public var total: Int
    public var detail: String

    public init(phase: ColdStartPhase, completed: Int, total: Int, detail: String) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.detail = detail
    }
}

public struct ColdStartSummary: Sendable {
    public var importedTurns: Int
    public var projectCount: Int

    public init(importedTurns: Int, projectCount: Int) {
        self.importedTurns = importedTurns
        self.projectCount = projectCount
    }
}

public struct ColdStartConfigurationRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("cold-start-configuration.json")
    }

    public func load() throws -> ColdStartConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try WorkstateCoding.makeDecoder().decode(
            ColdStartConfiguration.self,
            from: Data(contentsOf: url)
        )
    }

    public func save(_ configuration: ColdStartConfiguration) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder().encode(configuration).write(to: url, options: .atomic)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

public struct ColdStartService: Sendable {
    public let repository: WorkstateRepository
    public let scanner: CodexSessionScanner
    public let runtime: AgentRuntimeClient
    public let settingsRepository: WorkstateSettingsRepository
    public let configurationRepository: ColdStartConfigurationRepository
    private let cancellation: ColdStartCancellation

    public init(repository: WorkstateRepository = .init()) {
        self.repository = repository
        scanner = CodexSessionScanner(runtimeRoot: repository.paths.root)
        runtime = AgentRuntimeClient(runtimeRoot: repository.paths.root)
        settingsRepository = WorkstateSettingsRepository(root: repository.paths.root)
        configurationRepository = ColdStartConfigurationRepository(root: repository.paths.root)
        cancellation = ColdStartCancellation()
    }

    public func cancel() {
        cancellation.cancel()
        runtime.cancelActiveProcess()
    }

    public func run(
        _ configuration: ColdStartConfiguration,
        progress: @escaping @Sendable (ColdStartProgress) -> Void
    ) throws -> ColdStartSummary {
        try validate(configuration)
        cancellation.reset()
        let savedConfiguration = try configurationRepository.load()
        if let savedConfiguration,
           !sameColdStartScope(savedConfiguration, configuration) {
            throw WorkstateStorageError.invalidState(
                "An interrupted cold start must resume with its original tasks, dates, and project boundaries"
            )
        }
        let isResuming = savedConfiguration != nil
        // Agent settings may be corrected after a failed call without invalidating
        // already persisted route, distillation, or rebuild artifacts.
        try configurationRepository.save(configuration)
        try cancellation.check()
        progress(.init(phase: .preparing, completed: 0, total: 1, detail: "正在建立初始项目"))

        var runtimeSettings = configuration.settings
        let shouldEnableMonitoring = runtimeSettings.liveMonitoringEnabled
        runtimeSettings.setupCompleted = false
        runtimeSettings.liveMonitoringEnabled = false
        runtimeSettings.liveMonitoringStartedAt = nil
        try settingsRepository.save(runtimeSettings)

        let service = WorkstateService(repository: repository)
        try createSeedProjects(
            configuration.projectSeeds,
            service: service,
            allowsExistingDerivedProjects: isResuming
        )
        for (threadID, projectID) in configuration.sessionProjectHints {
            try scanner.recordRoute(
                threadID: threadID,
                turnID: "cold-start-hint",
                projectID: projectID
            )
        }

        progress(.init(phase: .importing, completed: 0, total: 1, detail: "正在读取选定时间范围"))
        try cancellation.check()
        let segments = try scanner.importHistory(
            threadIDs: configuration.selectedThreadIDs,
            interval: DateInterval(start: configuration.startDate, end: configuration.endDate)
        )
        guard !segments.isEmpty else {
            throw WorkstateStorageError.invalidState("The selected tasks contain no completed turns in this range")
        }

        let importedSegmentIDs = Set(segments.map(\.id))
        let failedIDs = try scanner.loadState().processingRecords?
            .values
            .filter { $0.stage == .failed && importedSegmentIDs.contains($0.segmentID) }
            .map(\.segmentID) ?? []
        try scanner.requeue(segmentIDs: failedIDs)

        var grouped: [String: [SessionSegment]] = [:]
        let routingChunks = try makeEvidenceChunks(segments, maximumEncodedBytes: 70_000)
        for (chunkIndex, chunk) in routingChunks.enumerated() {
            try cancellation.check()
            progress(.init(
                phase: .routing,
                completed: chunkIndex,
                total: routingChunks.count,
                detail: "正在判断第 \(chunkIndex + 1) / \(routingChunks.count) 组记录的项目归属"
            ))
            let unresolved = try chunk.filter {
                try scanner.processingRecord(segmentID: $0.id).route == nil
            }
            if !unresolved.isEmpty {
                for segment in unresolved {
                    try scanner.beginProcessing(segmentID: segment.id, stage: .routing)
                }
                do {
                    let decisions = try runtime.routeBatch(
                        segments: unresolved,
                        workspace: try service.snapshot(),
                        routeHints: configuration.sessionProjectHints,
                        scanner: scanner
                    )
                    for decision in decisions {
                        try scanner.recordRouteResult(
                            segmentID: decision.segmentId,
                            route: decision.routeResult
                        )
                    }
                } catch {
                    for segment in unresolved {
                        try? scanner.failProcessing(
                            segmentID: segment.id,
                            failedStage: .routing,
                            error: error.localizedDescription
                        )
                    }
                    throw error
                }
            }

            for segment in chunk {
                let record = try scanner.processingRecord(segmentID: segment.id)
                guard let route = record.route else {
                    throw WorkstateStorageError.invalidState(
                        "Cold-start route is missing for \(segment.id)"
                    )
                }

                if route.action == "ignore" {
                    try scanner.completeProcessing(segmentID: segment.id)
                    try scanner.markProcessed(segmentIDs: [segment.id])
                    continue
                }

                let project = try resolveProject(
                    route: route,
                    segment: segment,
                    service: service
                )
                grouped[project.id, default: []].append(segment)
                try scanner.recordRoute(
                    threadID: segment.threadID,
                    turnID: segment.turnID,
                    projectID: project.id
                )
            }
        }

        let orderedProjectIDs = grouped.keys.sorted()
        for (projectIndex, projectID) in orderedProjectIDs.enumerated() {
            try cancellation.check()
            guard let project = try service.snapshot().project(id: projectID),
                  let projectSegments = grouped[projectID] else {
                throw WorkstateStorageError.missingProject(projectID)
            }
            let chunks = try makeEvidenceChunks(projectSegments)
            let rebuildRoot = repository.paths.root.appendingPathComponent(
                "cold-start",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: rebuildRoot, withIntermediateDirectories: true)
            let fingerprint = evidenceFingerprint(projectSegments)
            let distillationURL = rebuildRoot.appendingPathComponent(
                "\(projectID)-\(fingerprint)-distilled.jsonl"
            )
            let proposalURL = rebuildRoot.appendingPathComponent(
                "\(projectID)-\(fingerprint)-proposal.json"
            )
            let existingDistillations: [RebuildDistilledChunk] = try readJSONLines(
                RebuildDistilledChunk.self,
                from: distillationURL
            )
            var distilledByIndex: [Int: RebuildDistilledChunk] = [:]
            for item in existingDistillations
                where item.schemaVersion == 2
                    && item.chunkCount == chunks.count
                    && item.chunkIndex < chunks.count
                    && item.evidenceIds == chunks[item.chunkIndex].map(\.id) {
                distilledByIndex[item.chunkIndex] = item
            }
            for (chunkIndex, chunk) in chunks.enumerated() {
                try cancellation.check()
                if distilledByIndex[chunkIndex] != nil { continue }
                progress(.init(
                    phase: .distilling,
                    completed: chunkIndex,
                    total: chunks.count,
                    detail: "正在整理「\(project.name)」历史 \(chunkIndex + 1) / \(chunks.count)"
                ))
                let distilled = try runtime.distill(
                    project: project,
                    segments: chunk,
                    chunkIndex: chunkIndex,
                    chunkCount: chunks.count,
                    scanner: scanner
                )
                guard distilled.evidenceIds == chunk.map(\.id) else {
                    throw WorkstateStorageError.invalidState(
                        "Historical distillation does not cover its complete input"
                    )
                }
                distilledByIndex[chunkIndex] = distilled
                try writeJSONLines(
                    distilledByIndex.values.sorted { $0.chunkIndex < $1.chunkIndex },
                    to: distillationURL
                )
            }
            let distillations = distilledByIndex.values.sorted { $0.chunkIndex < $1.chunkIndex }
            guard distillations.flatMap(\.evidenceIds) == projectSegments.map(\.id) else {
                throw WorkstateStorageError.invalidState(
                    "Historical distillation does not cover the complete project evidence"
                )
            }
            try writeJSONLines(distillations, to: distillationURL)

            progress(.init(
                phase: .rebuilding,
                completed: projectIndex,
                total: orderedProjectIDs.count,
                detail: "正在建立「\(project.name)」当前状态"
            ))
            let proposal: ProjectRebuildProposal
            try cancellation.check()
            if FileManager.default.fileExists(atPath: proposalURL.path) {
                proposal = try WorkstateCoding.makeDecoder().decode(
                    ProjectRebuildProposal.self,
                    from: Data(contentsOf: proposalURL)
                )
                guard proposal.projectId == projectID else {
                    throw WorkstateStorageError.invalidState(
                        "Stored cold-start proposal belongs to another project"
                    )
                }
            } else {
                proposal = try runtime.rebuild(
                    project: project,
                    evidencePath: distillationURL.path,
                    sourceThreadIDs: Array(Set(projectSegments.map(\.threadID))).sorted(),
                    scanner: scanner
                )
                try WorkstateCoding.makeEncoder().encode(proposal).write(
                    to: proposalURL,
                    options: .atomic
                )
            }
            _ = try ProjectRebuildApplier(repository: repository).apply(
                proposal,
                evidence: projectSegments
            )
            for segment in projectSegments {
                try scanner.completeProcessing(segmentID: segment.id)
            }
            try scanner.markProcessed(segmentIDs: projectSegments.map(\.id))
        }

        try cancellation.check()
        var completedSettings = configuration.settings
        completedSettings.setupCompleted = true
        completedSettings.liveMonitoringEnabled = shouldEnableMonitoring
        completedSettings.liveMonitoringStartedAt = shouldEnableMonitoring ? Date() : nil
        try settingsRepository.save(completedSettings)
        try configurationRepository.remove()

        let snapshot = try service.snapshot()
        progress(.init(
            phase: .completed,
            completed: segments.count,
            total: segments.count,
            detail: "工作区已建立"
        ))
        return ColdStartSummary(importedTurns: segments.count, projectCount: snapshot.projects.count)
    }

    private func validate(_ configuration: ColdStartConfiguration) throws {
        guard !configuration.selectedThreadIDs.isEmpty else {
            throw WorkstateStorageError.invalidState("Select at least one Codex task")
        }
        guard configuration.startDate < configuration.endDate else {
            throw WorkstateStorageError.invalidState("History range must have a start before its end")
        }
        let seeds = configuration.projectSeeds.map {
            ColdStartProjectSeed(
                id: $0.id,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                purpose: $0.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !seeds.isEmpty,
              seeds.allSatisfy({ !$0.name.isEmpty && !$0.purpose.isEmpty }) else {
            throw WorkstateStorageError.invalidState("Every initial project needs a name and purpose")
        }
        guard Set(seeds.map(\.id)).count == seeds.count,
              Set(seeds.map(\.name)).count == seeds.count else {
            throw WorkstateStorageError.invalidState("Initial project names and ids must be unique")
        }
        let projectIDs = Set(seeds.map(\.id))
        guard configuration.sessionProjectHints.values.allSatisfy(projectIDs.contains) else {
            throw WorkstateStorageError.invalidState("A session hint points to an unknown project")
        }
    }

    private func sameColdStartScope(
        _ lhs: ColdStartConfiguration,
        _ rhs: ColdStartConfiguration
    ) -> Bool {
        lhs.selectedThreadIDs == rhs.selectedThreadIDs
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.projectSeeds == rhs.projectSeeds
            && lhs.sessionProjectHints == rhs.sessionProjectHints
    }

    private func createSeedProjects(
        _ seeds: [ColdStartProjectSeed],
        service: WorkstateService,
        allowsExistingDerivedProjects: Bool
    ) throws {
        let existing = try service.snapshot()
        let unexpected = Set(existing.projects.map(\.id)).subtracting(seeds.map(\.id))
        guard unexpected.isEmpty || allowsExistingDerivedProjects else {
            throw WorkstateStorageError.invalidState(
                "Cold start cannot overwrite an existing Workstate workspace"
            )
        }
        for (index, seed) in seeds.enumerated() where existing.project(id: seed.id) == nil {
            let angle = (Double(index) / Double(max(seeds.count, 1))) * Double.pi * 2
            _ = try service.createProject(
                ProjectCreateInput(
                    id: seed.id,
                    name: seed.name,
                    summary: seed.purpose,
                    purpose: seed.purpose,
                    accent: ProjectAccent.allCases[index % ProjectAccent.allCases.count],
                    position: GraphPosition(
                        x: cos(angle) * 150,
                        y: sin(angle) * 150
                    )
                )
            )
        }
    }

    private func resolveProject(
        route: RouteResult,
        segment: SessionSegment,
        service: WorkstateService
    ) throws -> ProjectRecord {
        let workspace = try service.snapshot()
        switch route.action {
        case "continue_previous":
            guard try scanner.routeBinding(threadID: segment.threadID)?.projectID == route.projectId else {
                throw WorkstateStorageError.invalidState(
                    "Router continued a project without a matching session hint or prior route"
                )
            }
            fallthrough
        case "switch_project":
            guard let project = workspace.project(id: route.projectId) else {
                throw WorkstateStorageError.missingProject(route.projectId)
            }
            return project
        case "new_project":
            if let existing = workspace.project(id: route.projectId) {
                return existing
            }
            guard !route.projectId.isEmpty,
                  !route.projectName.isEmpty,
                  !route.projectSummary.isEmpty else {
                throw WorkstateStorageError.invalidState("Router returned an incomplete new project")
            }
            let index = workspace.projects.count
            _ = try service.createProject(
                ProjectCreateInput(
                    id: route.projectId,
                    name: route.projectName,
                    summary: route.projectSummary,
                    purpose: route.projectSummary,
                    accent: ProjectAccent.allCases[index % ProjectAccent.allCases.count],
                    position: GraphPosition(
                        x: Double((index % 3) - 1) * 170,
                        y: Double(index / 3) * 150
                    )
                )
            )
            guard let project = try service.snapshot().project(id: route.projectId) else {
                throw WorkstateStorageError.missingProject(route.projectId)
            }
            return project
        default:
            throw WorkstateStorageError.invalidState("Unsupported cold-start route: \(route.action)")
        }
    }

    private func makeEvidenceChunks(
        _ evidence: [SessionSegment],
        maximumEncodedBytes: Int = 90_000
    ) throws -> [[SessionSegment]] {
        let encoder = WorkstateCoding.makeEncoder(pretty: false)
        var chunks: [[SessionSegment]] = []
        var current: [SessionSegment] = []
        var currentBytes = 0
        for segment in evidence {
            let encodedBytes = try encoder.encode(segment).count + 1
            if !current.isEmpty && currentBytes + encodedBytes > maximumEncodedBytes {
                chunks.append(current)
                current = []
                currentBytes = 0
            }
            current.append(segment)
            currentBytes += encodedBytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func writeJSONLines<Value: Encodable>(_ values: [Value], to url: URL) throws {
        let encoder = WorkstateCoding.makeEncoder(pretty: false)
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private func readJSONLines<Value: Decodable>(
        _ type: Value.Type,
        from url: URL
    ) throws -> [Value] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 0x0A).map {
            try WorkstateCoding.makeDecoder().decode(type, from: Data($0))
        }
    }

    private func evidenceFingerprint(_ segments: [SessionSegment]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for segment in segments {
            for byte in segment.id.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return String(hash, radix: 16)
    }
}

private final class ColdStartCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func reset() {
        lock.lock()
        isCancelled = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let value = isCancelled
        lock.unlock()
        if value {
            throw WorkstateStorageError.invalidState("Cold start was stopped")
        }
    }
}
