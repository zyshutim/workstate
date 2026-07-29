import Foundation
import WorkstateCore

public struct LiveActivityProjector: Sendable {
    public init() {}

    public func project(
        sessions: [ActiveSession],
        routeBindingHistory: [String: [ThreadRouteBinding]] = [:],
        phase: LiveActivityPhase = .active
    ) -> [LiveProjectActivity] {
        sessions.compactMap { session in
            guard let projectID = routeBindingHistory[session.threadID]?
                    .max(by: { $0.updatedAt < $1.updatedAt })?.projectID else {
                return nil
            }
            return LiveProjectActivity(
                id: session.id,
                projectID: projectID,
                threadID: session.threadID,
                turnID: session.turnID,
                title: title(from: session.userText),
                updatedAt: session.updatedAt,
                phase: phase
            )
        }
    }

    private func title(from userText: String) -> String {
        let candidates = userText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("<")
                    && !line.hasPrefix("![")
            }
        let raw = candidates.first ?? userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 64 else { return raw }
        return String(raw.prefix(64)) + "…"
    }
}
