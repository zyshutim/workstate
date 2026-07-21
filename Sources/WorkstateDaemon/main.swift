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
        let liveActivities = LiveActivityRepository()
        let liveProjector = LiveActivityProjector()
        let runtime = AgentRuntimeClient()
        let orchestrator = WorkstateOrchestrator(service: service, scanner: scanner, runtime: runtime)
        let briefComposer = BriefCompositionService(runtime: runtime, scanner: scanner)
        _ = try AutomationRecovery(service: service, scanner: scanner).run()

        if runsOnce {
            try autoreleasepool {
                _ = try scanner.scan()
                try updateLiveActivities(
                    repository: liveActivities,
                    projector: liveProjector,
                    scanner: scanner,
                    workspace: service.snapshot()
                )
                try processPending(
                    orchestrator: orchestrator,
                    status: daemonStatus,
                    scanner: scanner
                )
            }
            return
        }

        let changes = SessionChangeQueue()
        let watcher = CodexSessionWatcher(root: scanner.sessionsRoot) { batch in
            changes.enqueue(batch)
        }
        let signals = SignalMonitor(runtime: runtime, changes: changes)
        let briefScheduler = DailyBriefScheduler(changes: changes)
        signals.start()
        try watcher.start()
        defer {
            watcher.stop()
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
                _ = try scanner.scan()
                try updateLiveActivities(
                    repository: liveActivities,
                    projector: liveProjector,
                    scanner: scanner,
                    workspace: service.snapshot()
                )
                try processPending(
                    orchestrator: orchestrator,
                    status: daemonStatus,
                    scanner: scanner
                )
                if DailyBriefScheduler.isDueToday() {
                    try composePreviousDayBrief(
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
                        try setDaemonState(
                            repository: daemonStatus,
                            scanner: scanner,
                            activity: .scanning,
                            detail: "正在读取变化的会话"
                        )
                        if batch.requiresFullScan {
                            _ = try scanner.scan()
                        } else {
                            _ = try scanner.scanChangedFiles(batch.paths)
                        }
                        try updateLiveActivities(
                            repository: liveActivities,
                            projector: liveProjector,
                            scanner: scanner,
                            workspace: service.snapshot()
                        )
                        try processPending(
                            orchestrator: orchestrator,
                            status: daemonStatus,
                            scanner: scanner
                        )
                    }
                    if changes.consumeScheduledBrief() {
                        try composePreviousDayBrief(
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
        let summary = try orchestrator.process(segments)
        let detail: String
        let activity: DaemonActivity
        if summary.failed > 0 {
            activity = .failed
            detail = "\(summary.failed) 条处理失败，已停止自动重试"
        } else {
            activity = .idle
            detail = "已更新 \(summary.changed) 条 · 已忽略 \(summary.ignored) 条"
        }
        try setDaemonState(
            repository: status,
            scanner: scanner,
            activity: activity,
            detail: detail
        )
    }

    private static func composePreviousDayBrief(
        composer: BriefCompositionService,
        orchestrator: WorkstateOrchestrator,
        status: DaemonStatusRepository,
        scanner: CodexSessionScanner
    ) throws {
        try setDaemonState(
            repository: status,
            scanner: scanner,
            activity: .analyzing,
            detail: "正在生成昨日工作总结"
        )
        _ = try composer.refreshPreviousDay(workspace: orchestrator.service.snapshot())
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
        condition.signal()
        condition.unlock()
    }

    func wait() -> SessionChangeBatch? {
        condition.lock()
        defer { condition.unlock() }
        while !stopped && paths.isEmpty && !requiresFullScan && !scheduledBrief {
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
