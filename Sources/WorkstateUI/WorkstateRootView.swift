import Combine
import SwiftUI

public struct WorkstateRootView: View {
    @ObservedObject private var model: WorkstateViewModel
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(model: WorkstateViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let project = model.selectedProject {
                ProjectWorkspaceView(project: project, model: model)
            } else {
                ProjectGraphView(model: model)
            }
        }
        .frame(width: model.preferredWidth, height: model.preferredHeight)
        .foregroundStyle(WorkstateTheme.primaryLabel)
        .background(WorkstateTheme.windowBackground)
        .overlay(alignment: .bottom) {
            if let errorMessage = model.errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(10)
            }
        }
        .onReceive(refreshTimer) { _ in
            model.reload()
        }
        .animation(.easeInOut(duration: 0.18), value: model.preferredWidth)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(WorkstateTheme.danger)
            Text(message)
                .font(WorkstateTheme.captionFont)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: WorkstateTheme.smallCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkstateTheme.smallCornerRadius, style: .continuous)
                .stroke(WorkstateTheme.separator, lineWidth: 0.5)
        }
    }
}
