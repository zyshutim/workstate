import Foundation
import WorkstateCore

public struct BriefCompositionService: Sendable {
    public let repository: DailyBriefRepository
    public let runtime: AgentRuntimeClient
    public let scanner: CodexSessionScanner

    public init(
        repository: DailyBriefRepository = .init(),
        runtime: AgentRuntimeClient = .init(),
        scanner: CodexSessionScanner = .init()
    ) {
        self.repository = repository
        self.runtime = runtime
        self.scanner = scanner
    }

    @discardableResult
    public func refreshLatest(
        workspace: WorkspaceSnapshot,
        through referenceDate: Date = Date(),
        force: Bool = false
    ) throws -> DailyBrief? {
        guard let latest = try repository.synchronize(
            workspace: workspace,
            through: referenceDate
        ).last else {
            return nil
        }
        if !force, latest.currentNarrative != nil {
            return latest
        }
        let narrative = try runtime.composeBrief(latest, workspace: workspace, scanner: scanner)
        return try repository.applyNarrative(narrative, to: latest.dateKey)
    }

    @discardableResult
    public func refreshPreviousActivityDay(
        workspace: WorkspaceSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        force: Bool = false
    ) throws -> DailyBrief? {
        let today = calendar.startOfDay(for: now)
        let activityDays = try DailyBriefBuilder(calendar: calendar)
            .activityDays(in: workspace, through: now)
            .filter { $0 < today }
        guard let previousActivityDay = activityDays.last else { return nil }
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: previousActivityDay
        )
        let dateKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        if !force,
           let existing = try repository.load(dateKey: dateKey),
           existing.currentNarrative != nil {
            return existing
        }
        let brief = try repository.brief(
            for: previousActivityDay,
            workspace: workspace,
            calendar: calendar,
            includeCurrentState: true
        )
        guard !brief.isEmpty else { return nil }
        if !force, brief.currentNarrative != nil {
            return brief
        }
        let narrative = try runtime.composeBrief(brief, workspace: workspace, scanner: scanner)
        return try repository.applyNarrative(narrative, to: brief.dateKey)
    }
}
