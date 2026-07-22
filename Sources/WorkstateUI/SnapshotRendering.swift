import SwiftUI

private struct WorkstateSnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct WorkstateSnapshotFocusedProjectKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct WorkstateSnapshotWorkspacePageKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct WorkstateSnapshotTopicIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct WorkstateSnapshotProgressModeKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var workstateSnapshotRendering: Bool {
        get { self[WorkstateSnapshotRenderingKey.self] }
        set { self[WorkstateSnapshotRenderingKey.self] = newValue }
    }

    var workstateSnapshotFocusedProjectID: String? {
        get { self[WorkstateSnapshotFocusedProjectKey.self] }
        set { self[WorkstateSnapshotFocusedProjectKey.self] = newValue }
    }

    var workstateSnapshotWorkspacePage: String? {
        get { self[WorkstateSnapshotWorkspacePageKey.self] }
        set { self[WorkstateSnapshotWorkspacePageKey.self] = newValue }
    }

    var workstateSnapshotTopicID: String? {
        get { self[WorkstateSnapshotTopicIDKey.self] }
        set { self[WorkstateSnapshotTopicIDKey.self] = newValue }
    }

    var workstateSnapshotProgressMode: String? {
        get { self[WorkstateSnapshotProgressModeKey.self] }
        set { self[WorkstateSnapshotProgressModeKey.self] = newValue }
    }
}

public extension View {
    func workstateSnapshotRendering(_ enabled: Bool = true) -> some View {
        environment(\.workstateSnapshotRendering, enabled)
    }

    func workstateSnapshotFocusedProject(_ projectID: String?) -> some View {
        environment(\.workstateSnapshotFocusedProjectID, projectID)
    }

    func workstateSnapshotWorkspace(page: String?, topicID: String? = nil) -> some View {
        environment(\.workstateSnapshotWorkspacePage, page)
            .environment(\.workstateSnapshotTopicID, topicID)
    }

    func workstateSnapshotProgressMode(_ mode: String?) -> some View {
        environment(\.workstateSnapshotProgressMode, mode)
    }
}
