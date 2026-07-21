import Foundation
import WorkstateCore

public struct LiveActivityProjector: Sendable {
    public init() {}

    public func project(
        sessions: [ActiveSession],
        workspace: WorkspaceSnapshot,
        routeBindings: [String: ThreadRouteBinding] = [:]
    ) -> [LiveProjectActivity] {
        sessions.compactMap { session in
            guard let projectID = routeBindings[session.threadID]?.projectID
                    ?? projectID(for: session, workspace: workspace) else {
                return nil
            }
            return LiveProjectActivity(
                id: session.id,
                projectID: projectID,
                threadID: session.threadID,
                turnID: session.turnID,
                title: title(from: session.userText),
                updatedAt: session.updatedAt
            )
        }
    }

    private func projectID(
        for session: ActiveSession,
        workspace: WorkspaceSnapshot
    ) -> String? {
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.sources.map { ($0.id, $0) })
        let exactMatches = workspace.projects.filter { project in
            projectSourceIDs(project).contains { sourceID in
                sourceByID[sourceID]?.threadID == session.threadID
            }
        }
        if exactMatches.count == 1 {
            return exactMatches[0].id
        }

        let cwd = session.cwd.lowercased()
        let text = session.userText.lowercased()
        if cwd.contains("/documents/workstate") || text.contains("workstate") {
            return existing("workstate", in: workspace)
        }
        if cwd.contains("reframe_website") || text.contains("reframe 官网") {
            return existing("reframe-website", in: workspace)
        }
        if cwd.contains("reframe-app-material-graph")
            || text.contains("reframe beta")
            || text.contains("storyboard")
            || text.contains("素材图谱")
            || text.contains("候选池") {
            return existing("reframe-beta", in: workspace)
        }
        if text.contains("v1.0 rc")
            || text.contains("reframe rc")
            || text.contains("正式版")
            || text.contains("多机位版本") {
            return existing("reframe-rc", in: workspace)
        }
        return nil
    }

    private func projectSourceIDs(_ project: ProjectRecord) -> Set<String> {
        Set(
            project.sourceIDs
                + project.tasks.flatMap(\.sourceIDs)
                + project.events.flatMap(\.sourceIDs)
                + project.context.understanding.flatMap(\.sourceIDs)
                + project.context.revisions.flatMap(\.sourceIDs)
        )
    }

    private func existing(_ projectID: String, in workspace: WorkspaceSnapshot) -> String? {
        workspace.project(id: projectID) == nil ? nil : projectID
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
