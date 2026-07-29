import Foundation
import WorkstateCore

public final class AppHostedConversationRuntime: @unchecked Sendable {
    private let coordinator: ConversationBatchCoordinator
    private let statusRepository: RuntimeStatusRepository
    private let briefComposer: BriefCompositionService
    private let dailyBriefRunGate: DailyBriefRunGate
    private let minimumTimestamp: Date?
    private let snapshotObserver: @Sendable (RuntimeSnapshot) -> Void
    private let queue = DispatchQueue(label: "com.timshu.workstate.app-observer")
    private let lock = NSLock()
    private var watcher: CodexSessionWatcher?
    private var scheduledWork: DispatchWorkItem?
    private var scheduledBriefWork: DispatchWorkItem?
    private var scheduledSourcePollWork: DispatchWorkItem?
    private var scheduledReconciliationWork: DispatchWorkItem?
    private var running = false
    private var pendingPaths = Set<String>()
    private var pendingRequiresFullScan = false
    private var changeDrainScheduled = false
    private var automaticNotBeforeByThread: [String: Date] = [:]

    public init(
        runtimeRoot: URL = WorkstatePaths.defaultPaths().root,
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        policy: ConversationBatchPolicy = .init(),
        minimumTimestamp: Date? = nil,
        snapshotObserver: @escaping @Sendable (RuntimeSnapshot) -> Void = { _ in }
    ) {
        let scanner = CodexSessionScanner(
            sessionsRoot: sessionsRoot,
            runtimeRoot: runtimeRoot,
            retainsLegacyPendingState: false
        )
        coordinator = ConversationBatchCoordinator(scanner: scanner, policy: policy)
        statusRepository = RuntimeStatusRepository(root: runtimeRoot)
        dailyBriefRunGate = DailyBriefRunGate(root: runtimeRoot)
        self.minimumTimestamp = minimumTimestamp
        self.snapshotObserver = snapshotObserver
        briefComposer = BriefCompositionService(
            repository: DailyBriefRepository(root: runtimeRoot),
            runtime: coordinator.orchestrator.runtime,
            scanner: scanner
        )
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }

        let watcher = CodexSessionWatcher(root: coordinator.scanner.sessionsRoot) { [weak self] batch in
            self?.enqueue(batch)
        }
        try watcher.start()
        self.watcher = watcher
        running = true
        queue.async { [weak self] in
            self?.establishBaseline()
            self?.scheduleSourcePoll()
            self?.scheduleReconciliation()
            self?.scheduleDailyBrief()
        }
    }

    public func stop() {
        lock.lock()
        let watcher = self.watcher
        self.watcher = nil
        running = false
        scheduledWork?.cancel()
        scheduledWork = nil
        scheduledBriefWork?.cancel()
        scheduledBriefWork = nil
        scheduledSourcePollWork?.cancel()
        scheduledSourcePollWork = nil
        scheduledReconciliationWork?.cancel()
        scheduledReconciliationWork = nil
        pendingPaths.removeAll(keepingCapacity: false)
        pendingRequiresFullScan = false
        changeDrainScheduled = false
        automaticNotBeforeByThread.removeAll(keepingCapacity: false)
        lock.unlock()
        watcher?.stop()
        coordinator.orchestrator.runtime.cancelActiveProcess()
        publish(activity: .stopped, detail: "同步未运行")
    }

    public func syncNow(
        completion: (@Sendable (Result<ConversationBatchRunResult?, Error>) -> Void)? = nil
    ) {
        flush(trigger: .manual, completion: completion)
    }

    public func flush(
        trigger: ConversationBatchTrigger,
        projectID: String? = nil,
        completion: (@Sendable (Result<ConversationBatchRunResult?, Error>) -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                do {
                    self.cancelScheduledWork()
                    _ = try self.coordinator.recoverInterruptedBatches()
                    try self.discardDisabledPeriod()
                    _ = try self.coordinator.scanAll(minimumTimestamp: self.minimumTimestamp)
                    let result = try self.coordinator.process(
                        trigger: trigger,
                        projectID: projectID
                    )
                    try self.writeStatus(for: result)
                    completion?(.success(result))
                } catch {
                    self.publish(activity: .failed, detail: error.localizedDescription)
                    completion?(.failure(error))
                }
            }
        }
    }

    public func flush(
        trigger: ConversationBatchTrigger,
        projectID: String? = nil
    ) async throws -> ConversationBatchRunResult? {
        try await withCheckedThrowingContinuation { continuation in
            flush(trigger: trigger, projectID: projectID) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func enqueue(_ batch: SessionChangeBatch) {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        pendingPaths.formUnion(batch.paths)
        pendingRequiresFullScan = pendingRequiresFullScan || batch.requiresFullScan
        guard !changeDrainScheduled else {
            lock.unlock()
            return
        }
        changeDrainScheduled = true
        lock.unlock()
        queue.async { [weak self] in self?.drainChanges() }
    }

    private func drainChanges() {
        while true {
            lock.lock()
            guard running else {
                changeDrainScheduled = false
                pendingPaths.removeAll(keepingCapacity: false)
                pendingRequiresFullScan = false
                lock.unlock()
                return
            }
            guard pendingRequiresFullScan || !pendingPaths.isEmpty else {
                changeDrainScheduled = false
                lock.unlock()
                return
            }
            let batch = SessionChangeBatch(
                paths: pendingPaths.sorted(),
                requiresFullScan: pendingRequiresFullScan
            )
            pendingPaths.removeAll(keepingCapacity: true)
            pendingRequiresFullScan = false
            lock.unlock()
            handle(batch)
        }
    }

    private func establishBaseline() {
        autoreleasepool {
            do {
                _ = try coordinator.recoverInterruptedBatches()
                try discardDisabledPeriod()
                let activity = try coordinator.scanAll(minimumTimestamp: minimumTimestamp)
                try schedule(for: activity)
            } catch {
                publish(activity: .failed, detail: error.localizedDescription)
            }
        }
    }

    private func handle(_ batch: SessionChangeBatch) {
        autoreleasepool {
            do {
                let activity = batch.requiresFullScan
                    ? try coordinator.scanAll(minimumTimestamp: minimumTimestamp)
                    : try coordinator.scanChanged(
                        paths: batch.paths,
                        minimumTimestamp: minimumTimestamp
                    )
                try schedule(for: activity)
            } catch {
                cancelScheduledWork()
                publish(activity: .failed, detail: error.localizedDescription)
            }
        }
    }

    private func schedule(for activity: PendingConversationActivity) throws {
        cancelScheduledWork()
        guard activity.pointerCount > 0 else {
            publish(activity: .idle, detail: "正在监听 Codex 会话", pendingCount: 0)
            return
        }
        let cooldowns = automaticCooldownSnapshot()
        guard let delay = try coordinator.nextAutomaticDelay(
            notBeforeByThread: cooldowns
        ) else { return }
        publish(
            activity: .idle,
            detail: "已记录 \(activity.pointerCount) 个新对话片段，等待会话告一段落",
            pendingCount: activity.pointerCount
        )
        let work = DispatchWorkItem { [weak self] in
            autoreleasepool {
                do {
                    try self?.processAutomaticBatch()
                } catch {
                    self?.publish(activity: .failed, detail: error.localizedDescription)
                }
            }
        }
        scheduledWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func processAutomaticBatch() throws {
        _ = try coordinator.recoverInterruptedBatches()
        publish(activity: .analyzing, detail: "正在整理新的项目上下文")
        let result = try coordinator.processAutomaticallyIfDue()
        try writeStatus(for: result)
    }

    private func writeStatus(for result: ConversationBatchRunResult?) throws {
        guard let result else {
            publish(activity: .idle, detail: "正在监听 Codex 会话")
            return
        }
        if result.trigger == .quietPeriod || result.trigger == .safetySize {
            lock.lock()
            automaticNotBeforeByThread[result.threadID] = Date()
                .addingTimeInterval(coordinator.policy.quietInterval)
            lock.unlock()
        }
        let remaining = try coordinator.pendingActivity()
        let remainingDetail = remaining.pointerCount > 0
            ? " · 仍有 \(remaining.pointerCount) 个片段"
            : ""
        if result.failedPointerCount > 0 {
            publish(
                activity: .failed,
                detail: "\(result.failedPointerCount) 条处理失败，已停止自动重试\(remainingDetail)",
                pendingCount: remaining.pointerCount
            )
        } else {
            publish(
                activity: .idle,
                detail: "已更新 \(result.summary.changed) 条 · 已忽略 \(result.summary.ignored) 条\(remainingDetail)",
                pendingCount: remaining.pointerCount
            )
        }
        scheduleRemainingBatchIfNeeded(activity: remaining)
    }

    private func scheduleRemainingBatchIfNeeded(activity: PendingConversationActivity) {
        lock.lock()
        let shouldSchedule = running
        lock.unlock()
        guard shouldSchedule else { return }
        guard activity.pointerCount > 0 else { return }
        do {
            try schedule(for: activity)
        } catch {
            publish(activity: .failed, detail: error.localizedDescription)
        }
    }

    private func cancelScheduledWork() {
        scheduledWork?.cancel()
        scheduledWork = nil
    }

    private func scheduleSourcePoll(interval: TimeInterval = 3) {
        scheduledSourcePollWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            autoreleasepool {
                do {
                    let paths = try self.coordinator.scanner.knownSessionPathsWithSizeChanges()
                    if !paths.isEmpty {
                        self.handle(SessionChangeBatch(paths: paths))
                    }
                } catch {
                    self.publish(activity: .failed, detail: error.localizedDescription)
                }
            }
            if self.isRunning {
                self.scheduleSourcePoll(interval: interval)
            }
        }
        scheduledSourcePollWork = work
        queue.asyncAfter(deadline: .now() + interval, execute: work)
    }

    private func scheduleReconciliation(interval: TimeInterval = 5 * 60) {
        scheduledReconciliationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            autoreleasepool {
                do {
                    let activity = try self.coordinator.scanAll(
                        minimumTimestamp: self.minimumTimestamp
                    )
                    try self.schedule(for: activity)
                } catch {
                    self.publish(activity: .failed, detail: error.localizedDescription)
                }
            }
            if self.isRunning {
                self.scheduleReconciliation(interval: interval)
            }
        }
        scheduledReconciliationWork = work
        queue.asyncAfter(deadline: .now() + interval, execute: work)
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func automaticCooldownSnapshot() -> [String: Date] {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        automaticNotBeforeByThread = automaticNotBeforeByThread.filter { $0.value > now }
        return automaticNotBeforeByThread
    }

    private func scheduleDailyBrief(now: Date = Date(), calendar: Calendar = .current) {
        scheduledBriefWork?.cancel()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = 0
        guard let todayAtNine = calendar.date(from: components) else { return }
        if now >= todayAtNine {
            runDailyBrief(now: now)
        }
        guard let next = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 9, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.runDailyBrief()
            if self.isRunning {
                self.scheduleDailyBrief()
            }
        }
        scheduledBriefWork = work
        queue.asyncAfter(deadline: .now() + max(0, next.timeIntervalSince(now)), execute: work)
    }

    private func runDailyBrief(now: Date = Date()) {
        guard isRunning else { return }
        autoreleasepool {
            do {
                guard try dailyBriefRunGate.beginIfNeeded(now: now) else { return }
                _ = try coordinator.recoverInterruptedBatches()
                _ = try coordinator.scanAll(minimumTimestamp: minimumTimestamp)
                _ = try coordinator.process(trigger: .dailyBrief)
                _ = try briefComposer.refreshPreviousActivityDay(
                    workspace: coordinator.orchestrator.service.snapshot()
                )
            } catch {
                publish(activity: .failed, detail: error.localizedDescription)
            }
        }
    }

    private func publish(
        activity: RuntimeActivity,
        detail: String,
        pendingCount: Int? = nil
    ) {
        do {
            let bindings = try coordinator.scanner.routeBindingHistory()
            let activeSessions = try coordinator.scanner.activeSessions()
            let pendingSegments = try coordinator.scanner.pendingIndexedSegments()
            let activeIDs = Set(activeSessions.map(\.id))
            let waitingSessions = pendingSegments
                .filter { !activeIDs.contains($0.id) }
                .map {
                    ActiveSession(
                        threadID: $0.threadID,
                        turnID: $0.turnID,
                        cwd: $0.cwd,
                        userText: $0.userText,
                        updatedAt: $0.timestamp
                    )
                }
            let projector = LiveActivityProjector()
            let live = projector.project(
                sessions: activeSessions,
                routeBindingHistory: bindings,
                phase: .active
            ) + projector.project(
                sessions: waitingSessions,
                routeBindingHistory: bindings,
                phase: .waitingForOwner
            )
            let allThreadIDs = Set(activeSessions.map(\.threadID) + waitingSessions.map(\.threadID))
            let snapshot = RuntimeSnapshot(
                activity: activity,
                detail: detail,
                pendingEvidenceCount: pendingCount ?? pendingSegments.count,
                unboundConversationCount: allThreadIDs.filter { bindings[$0]?.isEmpty != false }.count,
                liveActivities: live.sorted { $0.updatedAt > $1.updatedAt }
            )
            _ = try statusRepository.saveIfChanged(snapshot)
            snapshotObserver(snapshot)
        } catch {
            let snapshot = RuntimeSnapshot(activity: .failed, detail: error.localizedDescription)
            _ = try? statusRepository.saveIfChanged(snapshot)
            snapshotObserver(snapshot)
        }
    }

    private func discardDisabledPeriod() throws {
        guard let minimumTimestamp else { return }
        _ = try coordinator.scanner.discardUnprocessed(before: minimumTimestamp)
    }
}
