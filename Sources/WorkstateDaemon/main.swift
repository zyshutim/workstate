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
        let runtime = AgentRuntimeClient()
        let mode = AutomationMode(
            rawValue: ProcessInfo.processInfo.environment["WORKSTATE_AUTOMATION_MODE"] ?? "shadow"
        ) ?? .shadow
        let orchestrator = WorkstateOrchestrator(service: service, scanner: scanner, runtime: runtime, mode: mode)
        var pollInterval: TimeInterval = 5

        try setDaemonState(
            service: service,
            scanner: scanner,
            runtime: runtime,
            dailyLimit: orchestrator.maxDailyInputTokens,
            activity: .idle,
            detail: "正在监听 Codex 会话"
        )

        repeat {
            do {
                let segments = try scanner.scan()
                if !segments.isEmpty {
                    try setDaemonState(
                        service: service,
                        scanner: scanner,
                        runtime: runtime,
                        dailyLimit: orchestrator.maxDailyInputTokens,
                        activity: .analyzing,
                        detail: "正在分析 \(segments.count) 个新对话片段"
                    )
                    let summary = try orchestrator.process(segments)
                    pollInterval = summary.budgetPaused ? 300 : 5
                    try setDaemonState(
                        service: service,
                        scanner: scanner,
                        runtime: runtime,
                        dailyLimit: orchestrator.maxDailyInputTokens,
                        activity: summary.budgetPaused ? .paused : .idle,
                        detail: summary.budgetPaused
                            ? "今日模型预算已到上限 · \(summary.processed) 段已处理"
                            : mode == .shadow
                                ? "Shadow 分析完成 · \(summary.processed) 段"
                                : "已更新 \(summary.changed) 条 · 待确认 \(summary.reviews) 条"
                    )
                }
            } catch {
                try? setDaemonState(
                    service: service,
                    scanner: scanner,
                    runtime: runtime,
                    dailyLimit: orchestrator.maxDailyInputTokens,
                    activity: .failed,
                    detail: error.localizedDescription
                )
                if runsOnce { throw error }
            }

            if !runsOnce {
                Thread.sleep(forTimeInterval: pollInterval)
            }
        } while !runsOnce
    }

    private static func setDaemonState(
        service: WorkstateService,
        scanner: CodexSessionScanner,
        runtime: AgentRuntimeClient,
        dailyLimit: Int,
        activity: DaemonActivity,
        detail: String
    ) throws {
        let ingestion = try scanner.loadState()
        let dailyTokens = try runtime.dailyInputTokens()
        _ = try service.updateDaemon(
            DaemonSnapshot(
                activity: activity,
                lastScanAt: ingestion.lastScanAt,
                pendingEvidenceCount: ingestion.pendingSegmentIDs.count,
                detail: detail,
                dailyInputTokens: dailyTokens,
                dailyInputTokenLimit: dailyLimit
            )
        )
    }
}
