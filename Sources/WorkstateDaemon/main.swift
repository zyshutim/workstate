import Darwin
import Foundation
import WorkstateCore
import WorkstateIngestion

@main
struct WorkstateDaemon {
    static func main() throws {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let runsOnce = arguments.contains("--once")
        let scanner = CodexSessionScanner()
        let service = WorkstateService()
        let daemonStatus = DaemonStatusRepository()
        let settingsRepository = WorkstateSettingsRepository()
        let liveActivities = LiveActivityRepository()
        let liveProjector = LiveActivityProjector()
        let runtime = AgentRuntimeClient()
        let orchestrator = WorkstateOrchestrator(service: service, scanner: scanner, runtime: runtime)
        let briefComposer = BriefCompositionService(runtime: runtime, scanner: scanner)
        _ = try AutomationRecovery(service: service, scanner: scanner).run()
        _ = try scanner.recoverInterruptedProcessing()
        _ = try scanner.requeueLegacyPendingRoutes()

        if runsOnce {
            try autoreleasepool {
                let settings = try currentSettings(repository: settingsRepository, service: service)
                try discardDisabledPeriod(scanner: scanner, settings: settings)
                _ = try scanner.scan(minimumTimestamp: monitoringCutoff(settings))
                try updateLiveActivities(
                    repository: liveActivities,
                    projector: liveProjector,
                    scanner: scanner,
                    workspace: service.snapshot()
                )
                if settings.setupCompleted && settings.liveMonitoringEnabled {
                    try processPending(
                        orchestrator: orchestrator,
                        status: daemonStatus,
                        scanner: scanner
                    )
                } else {
                    try setMonitoringPausedState(
                        repository: daemonStatus,
                        scanner: scanner,
                        setupCompleted: settings.setupCompleted
                    )
                }
            }
            return
        }

        let changes = SessionChangeQueue()
        let pendingScheduler = PendingProcessingScheduler(changes: changes)
        let watcher = CodexSessionWatcher(root: scanner.sessionsRoot) { batch in
            changes.enqueue(batch)
            pendingScheduler.schedule()
        }
        let signals = SignalMonitor(runtime: runtime, changes: changes)
        let briefScheduler = DailyBriefScheduler(changes: changes)
        signals.start()
        try watcher.start()
        defer {
            watcher.stop()
            pendingScheduler.stop()
            briefScheduler.stop()
            signals.stop()
            runtime.cancelActiveProcess()
        }

        do {
            try autoreleasepool {
                try setDaemonState(
                    repository: daemonStatus,
                    scanner: scanner,
                    activity: .scanning,
                    detail: "正在检查会话状态"
                )
                let settings = try currentSettings(repository: settingsRepository, service: service)
                try discardDisabledPeriod(scanner: scanner, settings: settings)
                _ = try scanner.scan(minimumTimestamp: monitoringCutoff(settings))
                try updateLiveActivities(
                    repository: liveActivities,
                    projector: liveProjector,
                    scanner: scanner,
                    workspace: service.snapshot()
                )
                if settings.setupCompleted && settings.liveMonitoringEnabled {
                    try processPending(
                        orchestrator: orchestrator,
                        status: daemonStatus,
                        scanner: scanner
                    )
                } else {
                    try setMonitoringPausedState(
                        repository: daemonStatus,
                        scanner: scanner,
                        setupCompleted: settings.setupCompleted
                    )
                }
                if DailyBriefScheduler.isDueToday() {
                    try composePreviousActivityBrief(
                        composer: briefComposer,
                        orchestrator: orchestrator,
                        status: daemonStatus,
                        scanner: scanner
                    )
                }
            }
        } catch {
            try? setDaemonState(
                repository: daemonStatus,
                scanner: scanner,
                activity: .failed,
                detail: error.localizedDescription
            )
        }

        briefScheduler.start()

        while let batch = changes.wait() {
            autoreleasepool {
                do {
                    if batch.requiresFullScan || !batch.paths.isEmpty {
                        let settings = try currentSettings(
                            repository: settingsRepository,
                            service: service
                        )
                        try discardDisabledPeriod(scanner: scanner, settings: settings)
                        try setDaemonState(
                            repository: daemonStatus,
                            scanner: scanner,
                            activity: .scanning,
                            detail: "正在读取变化的会话"
                        )
                        if batch.requiresFullScan {
                            _ = try scanner.scan(minimumTimestamp: monitoringCutoff(settings))
                        } else {
                            _ = try scanner.scanChangedFiles(
                                batch.paths,
                                minimumTimestamp: monitoringCutoff(settings)
                            )
                        }
                        try updateLiveActivities(
                            repository: liveActivities,
                            projector: liveProjector,
                            scanner: scanner,
                            workspace: service.snapshot()
                        )
                        if settings.setupCompleted && settings.liveMonitoringEnabled {
                            try processPending(
                                orchestrator: orchestrator,
                                status: daemonStatus,
                                scanner: scanner
                            )
                        } else {
                            try setMonitoringPausedState(
                                repository: daemonStatus,
                                scanner: scanner,
                                setupCompleted: settings.setupCompleted
                            )
                        }
                    }
                    if changes.consumeScheduledPendingProcessing() {
                        let settings = try currentSettings(
                            repository: settingsRepository,
                            service: service
                        )
                        if settings.setupCompleted && settings.liveMonitoringEnabled {
                            try processPending(
                                orchestrator: orchestrator,
                                status: daemonStatus,
                                scanner: scanner
                            )
                        } else {
                            try setMonitoringPausedState(
                                repository: daemonStatus,
                                scanner: scanner,
                                setupCompleted: settings.setupCompleted
                            )
                        }
                    }
                    if changes.consumeScheduledBrief() {
                        try composePreviousActivityBrief(
                            composer: briefComposer,
                            orchestrator: orchestrator,
                            status: daemonStatus,
                            scanner: scanner
                        )
                    }
                } catch {
                    try? setDaemonState(
                        repository: daemonStatus,
                        scanner: scanner,
                        activity: .failed,
                        detail: error.localizedDescription
                    )
                }
            }
        }

        try? setDaemonState(
            repository: daemonStatus,
            scanner: scanner,
            activity: .stopped,
            detail: "监听已停止"
        )
    }

    private static func setPendingState(
        repository: DaemonStatusRepository,
        scanner: CodexSessionScanner
    ) throws {
        let pendingCount = try scanner.pendingSegments().count
        if pendingCount == 0 {
            try setDaemonState(
                repository: repository,
                scanner: scanner,
                activity: .idle,
                detail: "正在监听 Codex 会话"
            )
        } else {
            try setDaemonState(
                repository: repository,
                scanner: scanner,
                activity: .idle,
                detail: "已记录 \(pendingCount) 个新对话片段，等待会话告一段落"
            )
        }
    }

    private static func processPending(
        orchestrator: WorkstateOrchestrator,
        status: DaemonStatusRepository,
        scanner: CodexSessionScanner
    ) throws {
        let segments = try scanner.pendingSegments()
        guard !segments.isEmpty else {
            try setDaemonState(
                repository: status,
                scanner: scanner,
                activity: .idle,
                detail: "正在监听 Codex 会话"
            )
            return
        }
        try setDaemonState(
            repository: status,
            scanner: scanner,
            activity: .analyzing,
            detail: "正在分析 \(segments.count) 个新对话片段"
        )
        let summary = try orchestrator.processBacklog(segments)
        let detail: String
        let activity: DaemonActivity
        if summary.failed > 0 {
            activity = .failed
            detail = "\(summary.failed) 条处理失败，已停止自动重试"
        } else {
            activity = .idle
            let carried = try scanner.openSemanticBundles().count
            if carried > 0 {
                detail = "已更新 \(summary.changed) 条 · \(carried) 条讨论等待收束"
            } else {
                detail = "已更新 \(summary.changed) 条 · 已忽略 \(summary.ignored) 条"
            }
        }
        try setDaemonState(
            repository: status,
            scanner: scanner,
            activity: activity,
            detail: detail
        )
    }

    private static func currentSettings(
        repository: WorkstateSettingsRepository,
        service: WorkstateService
    ) throws -> WorkstateSettings {
        let workspace = try service.snapshot()
        return try repository.load(workspaceHasProjects: !workspace.projects.isEmpty)
    }

    private static func monitoringCutoff(_ settings: WorkstateSettings) -> Date? {
        guard settings.setupCompleted, settings.liveMonitoringEnabled else {
            return .distantFuture
        }
        return settings.liveMonitoringStartedAt
    }

    private static func discardDisabledPeriod(
        scanner: CodexSessionScanner,
        settings: WorkstateSettings
    ) throws {
        guard settings.setupCompleted,
              settings.liveMonitoringEnabled,
              let cutoff = settings.liveMonitoringStartedAt else {
            return
        }
        _ = try scanner.discardUnprocessed(before: cutoff)
    }

    private static func setMonitoringPausedState(
        repository: DaemonStatusRepository,
        scanner: CodexSessionScanner,
        setupCompleted: Bool
    ) throws {
        try setDaemonState(
            repository: repository,
            scanner: scanner,
            activity: .idle,
            detail: setupCompleted ? "实时监听已关闭" : "等待完成冷启动"
        )
    }

    private static func composePreviousActivityBrief(
        composer: BriefCompositionService,
        orchestrator: WorkstateOrchestrator,
        status: DaemonStatusRepository,
        scanner: CodexSessionScanner
    ) throws {
        try setDaemonState(
            repository: status,
            scanner: scanner,
            activity: .analyzing,
            detail: "正在生成最近工作日总结"
        )
        _ = try composer.refreshPreviousActivityDay(
            workspace: orchestrator.service.snapshot()
        )
        try setDaemonState(
            repository: status,
            scanner: scanner,
            activity: .idle,
            detail: "正在监听 Codex 会话"
        )
    }

    private static func updateLiveActivities(
        repository: LiveActivityRepository,
        projector: LiveActivityProjector,
        scanner: CodexSessionScanner,
        workspace: WorkspaceSnapshot
    ) throws {
        let snapshot = LiveActivitySnapshot(
            activities: projector.project(
                sessions: try scanner.activeSessions(),
                workspace: workspace,
                routeBindings: try scanner.loadState().routeBindings ?? [:]
            )
        )
        try repository.save(snapshot)
    }

    private static func setDaemonState(
        repository: DaemonStatusRepository,
        scanner: CodexSessionScanner,
        activity: DaemonActivity,
        detail: String
    ) throws {
        let ingestion = try scanner.loadState()
        _ = try repository.saveIfChanged(
            DaemonSnapshot(
                activity: activity,
                lastScanAt: ingestion.lastScanAt,
                pendingEvidenceCount: ingestion.pendingSegmentIDs.count,
                detail: detail,
                dailyInputTokens: nil,
                dailyInputTokenLimit: nil
            )
        )
    }
}

private final class SessionChangeQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var paths = Set<String>()
    private var requiresFullScan = false
    private var scheduledPendingProcessing = false
    private var scheduledBrief = false
    private var stopped = false

    func enqueue(_ batch: SessionChangeBatch) {
        condition.lock()
        guard !stopped else {
            condition.unlock()
            return
        }
        paths.formUnion(batch.paths)
        requiresFullScan = requiresFullScan || batch.requiresFullScan
        scheduledPendingProcessing = false
        condition.signal()
        condition.unlock()
    }

    func wait() -> SessionChangeBatch? {
        condition.lock()
        defer { condition.unlock() }
        while !stopped
            && paths.isEmpty
            && !requiresFullScan
            && !scheduledPendingProcessing
            && !scheduledBrief {
            condition.wait()
        }
        guard !stopped else { return nil }
        let batch = SessionChangeBatch(
            paths: paths.sorted(),
            requiresFullScan: requiresFullScan
        )
        paths.removeAll(keepingCapacity: true)
        requiresFullScan = false
        return batch
    }

    func enqueueScheduledPendingProcessing() {
        condition.lock()
        guard !stopped else {
            condition.unlock()
            return
        }
        scheduledPendingProcessing = true
        condition.signal()
        condition.unlock()
    }

    func consumeScheduledPendingProcessing() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let value = scheduledPendingProcessing
        scheduledPendingProcessing = false
        return value
    }

    func enqueueScheduledBrief() {
        condition.lock()
        guard !stopped else {
            condition.unlock()
            return
        }
        scheduledBrief = true
        condition.signal()
        condition.unlock()
    }

    func consumeScheduledBrief() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let value = scheduledBrief
        scheduledBrief = false
        return value
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class PendingProcessingScheduler: @unchecked Sendable {
    private let changes: SessionChangeQueue
    private let quietInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.timshu.workstate.pending-processing")
    private var timer: DispatchSourceTimer?

    init(
        changes: SessionChangeQueue,
        quietInterval: TimeInterval = 20 * 60
    ) {
        self.changes = changes
        self.quietInterval = quietInterval
    }

    func schedule() {
        queue.async { [weak self] in
            guard let self else { return }
            let source: DispatchSourceTimer
            if let timer {
                source = timer
            } else {
                source = DispatchSource.makeTimerSource(queue: queue)
                source.setEventHandler { [weak self] in
                    self?.changes.enqueueScheduledPendingProcessing()
                }
                timer = source
                source.resume()
            }
            source.schedule(
                deadline: .now() + quietInterval,
                leeway: .seconds(5)
            )
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }
}

private final class DailyBriefScheduler: @unchecked Sendable {
    private let changes: SessionChangeQueue
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "com.timshu.workstate.daily-brief")
    private var timer: DispatchSourceTimer?

    init(changes: SessionChangeQueue, calendar: Calendar = .current) {
        self.changes = changes
        self.calendar = calendar
    }

    func start() {
        queue.sync {
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                changes.enqueueScheduledBrief()
                scheduleNext(after: Date().addingTimeInterval(1))
            }
            timer = source
            scheduleNext(after: Date())
            source.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    static func isDueToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) else {
            return false
        }
        return now >= nine
    }

    private func scheduleNext(after date: Date) {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        components.second = 0
        guard let next = calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime
        ) else { return }
        timer?.schedule(
            deadline: .now() + max(1, next.timeIntervalSinceNow),
            leeway: .seconds(30)
        )
    }
}

private final class SignalMonitor: @unchecked Sendable {
    private let runtime: AgentRuntimeClient
    private let changes: SessionChangeQueue
    private let queue = DispatchQueue(label: "com.timshu.workstate.signals")
    private var sources: [DispatchSourceSignal] = []

    init(runtime: AgentRuntimeClient, changes: SessionChangeQueue) {
        self.runtime = runtime
        self.changes = changes
    }

    func start() {
        for signalNumber in [SIGTERM, SIGINT] {
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler { [runtime, changes] in
                runtime.cancelActiveProcess()
                changes.stop()
            }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }
}
