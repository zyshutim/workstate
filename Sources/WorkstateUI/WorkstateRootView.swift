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
            if model.needsOnboarding {
                ColdStartView(model: model)
            } else if model.isSettingsPresented {
                SettingsView(model: model)
            } else if model.isDailyBriefPresented {
                DailyBriefView(model: model)
            } else if model.isGlobalChatPresented {
                GlobalChatView(
                    conversation: model.globalConversation,
                    isSending: model.isGlobalChatSending,
                    onClose: model.closeGlobalChat,
                    onSend: model.sendGlobalMessage
                )
            } else if model.isCollaborationPresented {
                CollaborationProfileView(
                    profile: model.collaborationProfile,
                    conversation: model.collaborationConversation,
                    isSending: model.isCollaborationSending,
                    onClose: model.closeCollaborationProfile,
                    onSend: model.sendCollaborationMessage
                )
            } else if let project = model.selectedProject {
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
        .overlay(alignment: .bottomTrailing) {
            if !model.needsOnboarding,
               !model.isSettingsPresented,
               !model.isDailyBriefPresented,
               !model.isGlobalChatPresented,
               !model.isCollaborationPresented {
                HStack(spacing: 10) {
                    Button(action: model.presentCollaborationProfile) {
                        Label("协作档案", systemImage: "person.text.rectangle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .help("协作档案")

                    Button(action: model.presentGlobalChat) {
                        Label("和 Project Owner 讨论", systemImage: "message.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(WorkstateTheme.activeState)
                    .help("和 Project Owner 讨论")
                }
                .padding(.trailing, 16)
                .padding(.bottom, 100)
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
