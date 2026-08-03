import Darwin
import Foundation
import WorkstateCore

public struct ConversationBatchRunResult: Sendable {
    public var trigger: ConversationBatchTrigger
    public var batchID: String
    public var threadID: String
    public var pointerCount: Int
    public var summary: OrchestrationSummary
    public var failedPointerCount: Int

    public init(
        trigger: ConversationBatchTrigger,
        batchID: String,
        threadID: String,
        pointerCount: Int,
        summary: OrchestrationSummary,
        failedPointerCount: Int
    ) {
        self.trigger = trigger
        self.batchID = batchID
        self.threadID = threadID
        self.pointerCount = pointerCount
        self.summary = summary
        self.failedPointerCount = failedPointerCount
    }
}

public struct PendingThreadConversationActivity: Equatable, Sendable {
    public var provider: String
    public var threadID: String
    public var firstSequence: Int64
    public var activity: PendingConversationActivity

    public init(
        provider: String,
        threadID: String,
        firstSequence: Int64,
        activity: PendingConversationActivity
    ) {
        self.provider = provider
        self.threadID = threadID
        self.firstSequence = firstSequence
        self.activity = activity
    }
}

public struct ConversationBatchCoordinator: Sendable {
    public let scanner: CodexSessionScanner
    public let orchestrator: WorkstateOrchestrator
    public var policy: ConversationBatchPolicy
    public let maximumPointersPerBatch: Int

    public init(
        scanner: CodexSessionScanner = .init(retainsLegacyPendingState: false),
        orchestrator: WorkstateOrchestrator? = nil,
        policy: ConversationBatchPolicy = .init(),
        maximumPointersPerBatch: Int = 20
    ) {
        precondition(maximumPointersPerBatch > 0, "Batch pointer limit must be positive")
        self.scanner = scanner
        self.orchestrator = orchestrator ?? WorkstateOrchestrator(scanner: scanner)
        self.policy = policy
        self.maximumPointersPerBatch = maximumPointersPerBatch
    }

    public func scanAll(minimumTimestamp: Date? = nil) throws -> PendingConversationActivity {
        _ = try scanner.scan(minimumTimestamp: minimumTimestamp)
        return try pendingActivity()
    }

    public func scanChanged(
        paths: [String],
        minimumTimestamp: Date? = nil
    ) throws -> PendingConversationActivity {
        _ = try scanner.scanChangedFiles(paths, minimumTimestamp: minimumTimestamp)
        return try pendingActivity()
    }

    public func pendingActivity() throws -> PendingConversationActivity {
        let index = try sourceIndex()
        let stats = try index.pendingStats()
        let records = try index.pendingPointers(limit: maximumPointersPerBatch)
        return PendingConversationActivity(
            pointerCount: stats.count,
            oldestCompletedAt: stats.oldestInsertedAt,
            latestCompletedAt: stats.latestInsertedAt,
            estimatedSourceBytes: records.reduce(into: 0) { total, record in
                total += estimatedRelevantBytes(record.pointer)
            }
        )
    }

    public func pendingThreadActivities() throws -> [PendingThreadConversationActivity] {
        let index = try sourceIndex()
        return try index.pendingThreadStats().map { stats in
            let records = try index.pendingPointers(
                provider: stats.provider,
                threadIDs: [stats.threadID],
                limit: maximumPointersPerBatch
            )
            let estimatedBytes: UInt64
            if records.count < stats.pointerCount {
                estimatedBytes = policy.maximumEstimatedSourceBytes + 1
            } else {
                estimatedBytes = records.reduce(into: 0) { total, record in
                    total += estimatedRelevantBytes(record.pointer)
                }
            }
            let latestCompletedAt = max(
                stats.latestTimestamp,
                try scanner.latestActivityAt(threadID: stats.threadID) ?? .distantPast
            )
            return PendingThreadConversationActivity(
                provider: stats.provider,
                threadID: stats.threadID,
                firstSequence: stats.firstSequence,
                activity: PendingConversationActivity(
                    pointerCount: stats.pointerCount,
                    oldestCompletedAt: records.map(\.pointer.timestamp).min(),
                    latestCompletedAt: latestCompletedAt,
                    estimatedSourceBytes: estimatedBytes
                )
            )
        }
    }

    public func nextAutomaticDelay(
        now: Date = Date(),
        notBeforeByThread: [String: Date] = [:]
    ) throws -> TimeInterval? {
        let activities = try pendingThreadActivities()
        guard !activities.isEmpty else { return nil }
        return activities.map { item in
            let policyDelay: TimeInterval
            if let latest = item.activity.latestCompletedAt {
                policyDelay = max(0, policy.quietInterval - now.timeIntervalSince(latest))
            } else {
                policyDelay = policy.quietInterval
            }
            let cooldownDelay = notBeforeByThread[item.threadID]
                .map { max(0, $0.timeIntervalSince(now)) }
                ?? 0
            return max(policyDelay, cooldownDelay)
        }.min()
    }

    public func processAutomaticallyIfDue(
        now: Date = Date()
    ) throws -> ConversationBatchRunResult? {
        for item in try pendingThreadActivities() {
            if let trigger = policy.automaticTrigger(for: item.activity, now: now) {
                return try process(trigger: trigger, threadID: item.threadID)
            }
        }
        return nil
    }

    @discardableResult
    public func recoverInterruptedBatches() throws -> Int {
        let executionLock = try ConversationBatchExecutionLock(root: scanner.runtimeRoot)
        defer { executionLock.unlock() }
        let index = try sourceIndex()
        let outcomes = ConversationBatchOutcomeRepository(runtimeRoot: scanner.runtimeRoot)
        let batches = try index.processingBatches()
        for batch in batches {
            if let outcome = try outcomes.load(batchID: batch.id) {
                do {
                    _ = try orchestrator.service.applyIngestionBatch(
                        outcome.plan.changes,
                        newProjects: outcome.plan.newProjects
                    )
                } catch {
                    guard try planAppearsApplied(outcome.plan) else {
                        try failInterruptedBatch(
                            batch,
                            reason: "Commit plan could not be applied: \(error.localizedDescription)",
                            index: index
                        )
                        try? outcomes.remove(batchID: batch.id)
                        continue
                    }
                }
                try scanner.finalizePointerBatch(
                    successfulRoutes: outcome.plan.successfulRoutes,
                    failedSegmentIDs: outcome.plan.failedSegmentIDs
                )
                try finalizeIndexBatch(batch, plan: outcome.plan, index: index)
                try? outcomes.remove(batchID: batch.id)
            } else {
                try failInterruptedBatch(
                    batch,
                    reason: "Processing was interrupted before a commit plan was produced",
                    index: index
                )
            }
        }
        try outcomes.prune(retaining: Set(try index.processingBatches().map(\.id)))
        return batches.count
    }

    public func process(
        trigger: ConversationBatchTrigger,
        projectID: String? = nil,
        threadID: String? = nil
    ) throws -> ConversationBatchRunResult? {
        let executionLock = try ConversationBatchExecutionLock(root: scanner.runtimeRoot)
        defer { executionLock.unlock() }
        let index = try sourceIndex()
        guard let highWaterMark = try index.captureHighWaterMark() else {
            return nil
        }
        let eligibleThreadIDs = if let projectID {
            try scanner.routedThreadIDs(projectID: projectID)
        } else {
            Set(try index.pendingThreadStats().map(\.threadID))
        }
        let selectedThreadID: String
        if let threadID {
            guard projectID == nil || eligibleThreadIDs.contains(threadID) else {
                return nil
            }
            selectedThreadID = threadID
        } else {
            let ordered = try index.pendingThreadStats()
                .filter { eligibleThreadIDs.contains($0.threadID) }
            guard let first = ordered.first else { return nil }
            selectedThreadID = first.threadID
        }
        let candidates = try index.pendingPointers(
            provider: "codex",
            threadIDs: [selectedThreadID],
            through: highWaterMark,
            limit: maximumPointersPerBatch
        )
        let selectedLimit = boundedPointerCount(candidates)
        guard selectedLimit > 0 else {
            return nil
        }
        let selected = Array(candidates.prefix(selectedLimit))
        var materializedSegments: [SessionSegment] = []
        var unreadableSegmentIDs: [String] = []
        for record in selected {
            do {
                materializedSegments.append(try scanner.segment(pointerRecord: record))
            } catch {
                unreadableSegmentIDs.append(segmentID(for: record.pointer.id))
            }
        }
        let batch = try index.createBatch(pointerIDs: selected.map(\.pointer.id))
        guard let batch else { return nil }
        let outcomes = ConversationBatchOutcomeRepository(runtimeRoot: scanner.runtimeRoot)

        do {
            var segments = materializedSegments
            segments.sort { $0.timestamp < $1.timestamp }
            let modelInputBytes = segments.reduce(into: 0) { total, segment in
                total += segment.userText.utf8.count + segment.assistantText.utf8.count
            }
            guard modelInputBytes <= policy.maximumEstimatedSourceBytes else {
                throw WorkstateStorageError.invalidState(
                    "Conversation batch model input exceeds \(policy.maximumEstimatedSourceBytes) bytes"
                )
            }
            if segments.isEmpty {
                let plan = ConversationBatchCommitPlan(
                    changes: [],
                    successfulRoutes: [],
                    failedSegmentIDs: unreadableSegmentIDs,
                    processed: 0,
                    changed: 0,
                    ignored: 0,
                    agentRuns: 0
                )
                try outcomes.save(batchID: batch.id, plan: plan)
            } else {
                _ = try orchestrator.processBacklog(
                    segments,
                    beforeApplying: { plan in
                        var combined = plan
                        combined.failedSegmentIDs = Array(
                            Set(plan.failedSegmentIDs).union(unreadableSegmentIDs)
                        ).sorted()
                        try outcomes.save(batchID: batch.id, plan: combined)
                    },
                    resumesPersistedState: false
                )
            }
            guard let outcome = try outcomes.load(batchID: batch.id) else {
                throw WorkstateStorageError.invalidState(
                    "Conversation batch finished without a commit plan"
                )
            }
            try scanner.finalizePointerBatch(
                successfulRoutes: outcome.plan.successfulRoutes,
                failedSegmentIDs: outcome.plan.failedSegmentIDs
            )
            try finalizeIndexBatch(batch, plan: outcome.plan, index: index)
            try? outcomes.remove(batchID: batch.id)
            return ConversationBatchRunResult(
                trigger: trigger,
                batchID: batch.id,
                threadID: selectedThreadID,
                pointerCount: batch.pointers.count,
                summary: outcome.plan.summary,
                failedPointerCount: outcome.plan.failedSegmentIDs.count
            )
        } catch {
            if let outcome = try? outcomes.load(batchID: batch.id),
               (try? planAppearsApplied(outcome.plan)) == true {
                try scanner.finalizePointerBatch(
                    successfulRoutes: outcome.plan.successfulRoutes,
                    failedSegmentIDs: outcome.plan.failedSegmentIDs
                )
                try finalizeIndexBatch(batch, plan: outcome.plan, index: index)
                try? outcomes.remove(batchID: batch.id)
                return ConversationBatchRunResult(
                    trigger: trigger,
                    batchID: batch.id,
                    threadID: selectedThreadID,
                    pointerCount: batch.pointers.count,
                    summary: outcome.plan.summary,
                    failedPointerCount: outcome.plan.failedSegmentIDs.count
                )
            }
            try? outcomes.remove(batchID: batch.id)
            try? failInterruptedBatch(
                batch,
                reason: error.localizedDescription,
                index: index
            )
            throw error
        }
    }

    private func sourceIndex() throws -> ConversationSourceIndex {
        try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
    }

    private func finalizeIndexBatch(
        _ batch: ConversationProcessingBatch,
        plan: ConversationBatchCommitPlan,
        index: ConversationSourceIndex
    ) throws {
        var routeByID: [String: ProcessedSegmentRoute] = [:]
        for route in plan.successfulRoutes {
            guard routeByID.updateValue(route, forKey: route.segmentID) == nil else {
                throw WorkstateStorageError.invalidState(
                    "Conversation batch commit plan has duplicate routes"
                )
            }
        }
        let failedSegmentIDs = Set(plan.failedSegmentIDs)
        let completed = batch.pointers.filter {
            routeByID[segmentID(for: $0.pointer.id)] != nil
        }
        let failed = batch.pointers.filter {
            failedSegmentIDs.contains(segmentID(for: $0.pointer.id))
        }
        guard completed.count + failed.count == batch.pointers.count else {
            throw WorkstateStorageError.invalidState(
                "Conversation batch commit plan does not account for every pointer"
            )
        }
        let assignments = completed.compactMap { record -> ConversationPointerProjectAssignment? in
            guard let projectID = routeByID[segmentID(for: record.pointer.id)]?.projectID else {
                return nil
            }
            return ConversationPointerProjectAssignment(
                pointerID: record.pointer.id,
                projectID: projectID
            )
        }
        _ = try index.finalizeBatch(
            batch.id,
            completedPointerIDs: completed.map(\.pointer.id),
            projectAssignments: assignments,
            failedPointerIDs: failed.map(\.pointer.id),
            semanticBundleMutations: plan.semanticBundleMutations,
            errorMessage: failed.isEmpty
                ? nil
                : "\(failed.count) conversation pointers failed; automatic retry is disabled"
        )
    }

    private func planAppearsApplied(_ plan: ConversationBatchCommitPlan) throws -> Bool {
        let workspace = try orchestrator.service.snapshot()
        for project in plan.newProjects where workspace.project(id: project.id) == nil {
            return false
        }
        for change in plan.changes {
            guard workspace.project(id: change.projectID)?.event(id: change.id) != nil else {
                return false
            }
        }
        return true
    }

    private func failInterruptedBatch(
        _ batch: ConversationProcessingBatch,
        reason: String,
        index: ConversationSourceIndex
    ) throws {
        let failedIDs = batch.pointers.map { segmentID(for: $0.pointer.id) }
        try scanner.finalizePointerBatch(
            successfulRoutes: [],
            failedSegmentIDs: failedIDs
        )
        _ = try index.markBatchFailed(batch.id, errorMessage: reason)
    }

    private func boundedPointerCount(
        _ records: [ConversationSourcePointerRecord]
    ) -> Int {
        var total: UInt64 = 0
        var count = 0
        for record in records {
            let bytes = estimatedRelevantBytes(record.pointer)
            if count > 0, total + bytes > policy.maximumEstimatedSourceBytes { break }
            total += bytes
            count += 1
        }
        return count
    }

    private func estimatedRelevantBytes(_ pointer: ConversationSourcePointer) -> UInt64 {
        if !pointer.messageSpans.isEmpty {
            return pointer.messageSpans.reduce(into: 0) { total, span in
                total += span.endOffset - span.startOffset
            }
        }
        return min(
            pointer.endOffset - pointer.startOffset,
            policy.maximumEstimatedSourceBytes + 1
        )
    }

    private func segmentID(for pointerID: ConversationSourcePointerID) -> String {
        "\(pointerID.threadID):\(pointerID.turnID)"
    }
}

private final class ConversationBatchExecutionLock {
    private var descriptor: Int32

    init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("conversation-batch.lock")
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw WorkstateStorageError.invalidState(
                "Cannot open conversation batch lock: \(url.path)"
            )
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            descriptor = -1
            throw WorkstateStorageError.invalidState(
                "Another Workstate conversation batch is already running"
            )
        }
    }

    deinit {
        unlock()
    }

    func unlock() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }
}

private struct ConversationBatchOutcomeRecord: Codable {
    var batchID: String
    var createdAt: Date
    var plan: ConversationBatchCommitPlan
}

private struct ConversationBatchOutcomeRepository {
    private let maximumRecordBytes = 8 * 1024 * 1024
    let root: URL

    init(runtimeRoot: URL) {
        root = runtimeRoot.appendingPathComponent("batch-outcomes", isDirectory: true)
    }

    func save(batchID: String, plan: ConversationBatchCommitPlan) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = ConversationBatchOutcomeRecord(
            batchID: batchID,
            createdAt: Date(),
            plan: plan
        )
        let data = try WorkstateCoding.makeEncoder().encode(record)
        guard data.count <= maximumRecordBytes else {
            throw WorkstateStorageError.invalidState(
                "Conversation batch outcome exceeded 8 MiB"
            )
        }
        try data.write(
            to: url(batchID: batchID),
            options: .atomic
        )
    }

    func load(batchID: String) throws -> ConversationBatchOutcomeRecord? {
        let url = url(batchID: batchID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumRecordBytes else {
            throw WorkstateStorageError.invalidState(
                "Conversation batch outcome exceeded 8 MiB"
            )
        }
        let record = try WorkstateCoding.makeDecoder().decode(
            ConversationBatchOutcomeRecord.self,
            from: Data(contentsOf: url)
        )
        guard record.batchID == batchID else {
            throw WorkstateStorageError.invalidState(
                "Conversation batch outcome belongs to another batch"
            )
        }
        return record
    }

    func remove(batchID: String) throws {
        let url = url(batchID: batchID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func prune(retaining batchIDs: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) where item.pathExtension == "json"
            && !batchIDs.contains(item.deletingPathExtension().lastPathComponent) {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func url(batchID: String) -> URL {
        root.appendingPathComponent("\(batchID).json")
    }
}
