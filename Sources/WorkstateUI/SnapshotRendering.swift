import SwiftUI

private struct WorkstateSnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct WorkstateSnapshotFocusedProjectKey: EnvironmentKey {
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
}

public extension View {
    func workstateSnapshotRendering(_ enabled: Bool = true) -> some View {
        environment(\.workstateSnapshotRendering, enabled)
    }

    func workstateSnapshotFocusedProject(_ projectID: String?) -> some View {
        environment(\.workstateSnapshotFocusedProjectID, projectID)
    }
}
