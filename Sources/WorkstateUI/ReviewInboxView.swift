import AppKit
import SwiftUI
import WorkstateCore
import WorkstateIngestion

struct ReviewInboxPopover: View {
    @ObservedObject var model: WorkstateViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.68))
                .frame(height: 0.5)

            if let review = model.selectedReview {
                reviewPicker

                Rectangle()
                    .fill(WorkstateTheme.separator.opacity(0.56))
                    .frame(height: 0.5)

                if snapshotRendering {
                    ReviewDetail(review: review, workspace: model.workspace)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 326, alignment: .top)
                        .clipped()
                } else {
                    ScrollView {
                        ReviewDetail(review: review, workspace: model.workspace)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 326)
                    .layoutPriority(1)
                    .scrollIndicators(.visible)
                }

                Rectangle()
                    .fill(WorkstateTheme.separator.opacity(0.68))
                    .frame(height: 0.5)

                actions
            } else {
                ContentUnavailableView(
                    "没有待确认内容",
                    systemImage: "checkmark.circle",
                    description: Text("客观进展会继续自动维护。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .workstateGlassSurface(cornerRadius: 18)
        .shadow(
            color: WorkstateTheme.shadow.opacity(colorScheme == .dark ? 0.50 : 0.22),
            radius: 30,
            y: 12
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WorkstateTheme.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("待确认")
                    .font(WorkstateTheme.headlineFont)
                Text("只显示需要你决定的冲突")
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }

            Spacer(minLength: 8)

            Text("\(model.pendingReviews.count)")
                .font(WorkstateTheme.captionEmphasisFont.monospacedDigit())
                .foregroundStyle(WorkstateTheme.warning)

            Button(action: model.closeReviewInbox) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 15)
        .frame(height: 62)
    }

    private var reviewPicker: some View {
        HStack(spacing: 8) {
            ForEach(model.pendingReviews.prefix(4)) { review in
                Button {
                    model.selectReview(review.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(review.kind.color)
                            .frame(width: 6, height: 6)
                        Text(review.projectID.flatMap(model.workspace.project(id:))?.name ?? "未归类")
                            .lineLimit(1)
                    }
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(
                        model.selectedReview?.id == review.id
                            ? WorkstateTheme.primaryLabel
                            : WorkstateTheme.secondaryLabel
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        Capsule()
                            .fill(
                                model.selectedReview?.id == review.id
                                    ? review.kind.color.opacity(0.14)
                                    : WorkstateTheme.primaryLabel.opacity(0.04)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(height: 48)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("拒绝") {
                model.resolveSelectedReview(as: .rejected)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WorkstateTheme.danger)

            Spacer(minLength: 8)

            Button("稍后") {
                model.resolveSelectedReview(as: .deferred)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WorkstateTheme.secondaryLabel)

            Button("确认更新") {
                model.resolveSelectedReview(as: .confirmed)
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkstateTheme.activeState)
        }
        .font(WorkstateTheme.captionEmphasisFont)
        .padding(.horizontal, 15)
        .frame(height: 54)
    }
}

private struct ReviewDetail: View {
    let review: ReviewItem
    let workspace: WorkspaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(review.kind.displayName)
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(review.kind.color)
                Text(review.title)
                    .font(WorkstateTheme.sectionTitleFont)
                Text(review.summary)
                    .font(WorkstateTheme.secondaryFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ReviewTextSection(title: "需要你决定", text: review.reason, lineLimit: 3)

            if !review.previousValue.isEmpty {
                ReviewTextSection(title: "当前", text: review.previousValue, lineLimit: 3)
            }
            if !review.proposedValue.isEmpty {
                ReviewTextSection(title: "建议", text: review.proposedValue, accent: review.kind.color, lineLimit: 3)
            }

            if !review.proposedChanges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("影响")
                        .font(WorkstateTheme.captionEmphasisFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                    ForEach(review.proposedChanges.prefix(3), id: \.self) { change in
                        Label(change, systemImage: "arrow.right")
                            .font(WorkstateTheme.captionFont)
                            .lineLimit(2)
                    }
                }
            }

            if !sources.isEmpty {
                DisclosureGroup("查看原始对话") {
                    ForEach(sources) { source in
                        ConversationEvidence(source: source)
                    }
                }
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var sources: [SourceReference] {
        let ids = Set(review.sourceIDs)
        return workspace.sources.filter { ids.contains($0.id) }
    }
}

private struct ReviewTextSection: View {
    let title: String
    let text: String
    var accent: Color = WorkstateTheme.primaryLabel
    var lineLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            Text(text)
                .font(WorkstateTheme.secondaryFont)
                .foregroundStyle(accent)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ConversationEvidence: View {
    let source: SourceReference
    @State private var resolvedMessages: [ConversationMessage] = []
    @State private var resolutionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.role == "user" ? "你" : "Codex")
                        .font(WorkstateTheme.microFont)
                        .foregroundStyle(
                            message.role == "user"
                                ? WorkstateTheme.activeState
                                : WorkstateTheme.secondaryLabel
                        )
                    Text(message.text)
                        .font(WorkstateTheme.captionFont)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(
                            message.role == "user"
                                ? WorkstateTheme.activeState.opacity(0.65)
                                : WorkstateTheme.separator
                        )
                        .frame(width: 2)
                }
            }

            if messages.isEmpty, resolutionError == nil {
                ProgressView()
                    .controlSize(.small)
            } else if let resolutionError {
                Text(resolutionError)
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }

            if let url = sourceURL {
                Link(destination: url) {
                    Label("打开原始对话", systemImage: "arrow.up.forward.app")
                        .font(WorkstateTheme.captionEmphasisFont)
                }
            }
        }
        .task(id: source.id) {
            do {
                let source = source
                resolvedMessages = try await Task.detached {
                    try CodexSessionScanner().resolveMessages(for: source)
                }.value
                resolutionError = nil
            } catch {
                resolvedMessages = []
                resolutionError = error.localizedDescription
            }
        }
    }

    private var messages: [ConversationMessage] {
        source.excerpt.isEmpty ? resolvedMessages : source.excerpt
    }

    private var sourceURL: URL? {
        if !source.threadID.isEmpty {
            return URL(string: "codex://threads/\(source.threadID)")
        }
        return source.locator.hasPrefix("/")
            ? URL(fileURLWithPath: source.locator)
            : URL(string: source.locator)
    }
}

private extension ReviewKind {
    var displayName: String {
        switch self {
        case .ambiguousRouting: "归属不明确"
        case .candidateProject: "候选新项目"
        case .projectUpdate: "项目进展"
        case .projectStructure: "项目结构变化"
        case .understandingConflict: "项目理解冲突"
        case .decisionConflict: "决策冲突"
        }
    }

    var color: Color {
        switch self {
        case .ambiguousRouting: WorkstateTheme.warning
        case .candidateProject: WorkstateTheme.activeState
        case .projectUpdate: WorkstateTheme.success
        case .projectStructure: WorkstateTheme.activeState
        case .understandingConflict: WorkstateTheme.warning
        case .decisionConflict: WorkstateTheme.danger
        }
    }
}
