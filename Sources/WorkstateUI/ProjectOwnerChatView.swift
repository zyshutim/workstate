import SwiftUI
import WorkstateCore

struct ProjectOwnerChatView: View {
    let project: ProjectRecord
    let activeTopic: ProjectTopic?
    let conversation: ProjectOwnerConversation
    let isSending: Bool
    let onClearTopic: () -> Void
    let onSend: (String) -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ownerHeader

            Divider()

            messageHistory

            Divider()

            composer
        }
        .background(WorkstateTheme.workspaceBackground)
    }

    private var ownerHeader: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(project.accent.color)
                    .frame(width: 46, height: 46)
                Image(systemName: "person.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(WorkstateTheme.onAccent)
            }

            Text(project.name)
                .font(WorkstateTheme.headlineFont)
                .lineLimit(1)

            HStack(spacing: 5) {
                Text("Project Owner")
                Circle()
                    .fill(WorkstateTheme.success)
                    .frame(width: 5, height: 5)
                Text("已同步")
            }
            .font(WorkstateTheme.microFont)
            .foregroundStyle(WorkstateTheme.secondaryLabel)

            if let activeTopic {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                    Text(activeTopic.title)
                        .lineLimit(1)
                    Button(action: onClearTopic) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("退出当前议题")
                }
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(project.accent.color)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    project.accent.color.opacity(0.12),
                    in: Capsule()
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 76)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var messageHistory: some View {
        Group {
            if snapshotRendering {
                VStack(spacing: 8) {
                    messageContent
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            messageContent
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: conversation.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isSending) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if conversation.messages.isEmpty {
            ownerIntroduction
        } else {
            ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                if shouldShowTimestamp(at: index) {
                    OwnerMessageTimestamp(timestamp: message.timestamp)
                }
                OwnerMessageRow(message: message)
                    .id(message.id)
            }
        }

        if isSending {
            OwnerTypingIndicator()
            .id("owner-thinking")
        }
    }

    private var ownerIntroduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cognition = project.context.cognition, cognition.state == .confirmed {
                ForEach(cognition.sections.sorted(by: { $0.order < $1.order }).prefix(2)) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(WorkstateTheme.captionEmphasisFont)
                        Text(section.body)
                            .font(WorkstateTheme.bodyFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("项目认知尚未建立，Owner 只会使用当前会话和项目识别信息。")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }

            let openTopics = project.topics
                .filter { $0.status == .captured || $0.status == .discussing }
                .sorted { $0.updatedAt > $1.updatedAt }
            if !openTopics.isEmpty {
                Divider()
                Text("待讨论议题")
                    .font(WorkstateTheme.captionEmphasisFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                ForEach(openTopics.prefix(3)) { topic in
                    Label(topic.title, systemImage: "circle")
                        .labelStyle(OwnerIssueLabelStyle())
                        .font(WorkstateTheme.captionFont)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            WorkstateTheme.contentBackground,
            in: RoundedRectangle(cornerRadius: WorkstateTheme.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkstateTheme.cornerRadius, style: .continuous)
                .stroke(WorkstateTheme.separator.opacity(0.7), lineWidth: 0.5)
        }
    }

    private var composer: some View {
        Group {
            if snapshotRendering {
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(WorkstateTheme.activeState.opacity(0.45))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(height: 88)
                .background(
                    WorkstateTheme.contentBackground,
                    in: RoundedRectangle(cornerRadius: 25, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .stroke(WorkstateTheme.separator.opacity(0.8), lineWidth: 0.7)
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    TextEditor(text: $draft)
                        .font(WorkstateTheme.bodyFont)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.automatic)
                        .padding(.horizontal, 1)
                        .frame(height: 74)
                        .focused($composerFocused)
                        .onKeyPress(.return, phases: .down) { keyPress in
                            if keyPress.modifiers.contains(.shift)
                                || keyPress.modifiers.contains(.option) {
                                return .ignored
                            }
                            send()
                            return .handled
                        }

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(WorkstateTheme.onAccent, WorkstateTheme.activeState)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                    .help("发送")
                    .accessibilityLabel("发送给 Project Owner")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(height: 88)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 25, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .stroke(WorkstateTheme.separator.opacity(0.8), lineWidth: 0.7)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        draft = ""
        onSend(message)
        composerFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = isSending
            ? AnyHashable("owner-thinking")
            : conversation.messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func shouldShowTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = conversation.messages[index].timestamp
        let previous = conversation.messages[index - 1].timestamp
        return current.timeIntervalSince(previous) > 5 * 60
    }
}

struct GlobalChatView: View {
    let conversation: GlobalConversation
    let isSending: Bool
    let onClose: () -> Void
    let onSend: (String) -> Void
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("返回")

                Spacer()

                VStack(spacing: 2) {
                    Text("Project Owners")
                        .font(WorkstateTheme.headlineFont)
                    Text("自动转给相关项目")
                        .font(WorkstateTheme.microFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }

                Spacer()

                Color.clear.frame(width: 14, height: 14)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(.bar)

            Divider()

            Group {
                if snapshotRendering {
                    VStack(spacing: 8) {
                        globalMessageContent
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                globalMessageContent
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                        }
                        .onChange(of: conversation.messages.count) { _, _ in
                            let target: AnyHashable? = conversation.messages.last.map { AnyHashable($0.id) }
                            guard let target else { return }
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(target, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                if !snapshotRendering {
                    TextEditor(text: $draft)
                        .font(WorkstateTheme.bodyFont)
                        .scrollContentBackground(.hidden)
                        .frame(height: 74)
                        .focused($composerFocused)
                        .onKeyPress(.return, phases: .down) { keyPress in
                            if keyPress.modifiers.contains(.shift)
                                || keyPress.modifiers.contains(.option) {
                                return .ignored
                            }
                            send()
                            return .handled
                        }
                } else {
                    Spacer(minLength: 0)
                }

                if !snapshotRendering {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(WorkstateTheme.onAccent, WorkstateTheme.activeState)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(WorkstateTheme.onAccent, WorkstateTheme.activeState)
                        .opacity(0.42)
                }
            }
            .padding(8)
            .frame(height: 88)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(WorkstateTheme.separator.opacity(0.8), lineWidth: 0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .background(WorkstateTheme.workspaceBackground)
    }

    @ViewBuilder
    private var globalMessageContent: some View {
        if conversation.messages.isEmpty {
            Text("写下正在想的事情，我会把它交给相关项目的 Owner。")
                .font(WorkstateTheme.bodyFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
        }
        ForEach(conversation.messages) { message in
            if message.role == .system {
                Text(message.text)
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .padding(.vertical, 5)
            } else {
                GlobalMessageRow(message: message)
                    .id(message.id)
            }
        }
        if isSending {
            OwnerTypingIndicator()
                .id("global-owner-thinking")
        }
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        draft = ""
        onSend(message)
        composerFocused = true
    }
}

private struct GlobalMessageRow: View {
    let message: GlobalChatMessage

    var body: some View {
        VStack(
            alignment: message.role == .user ? .trailing : .leading,
            spacing: 4
        ) {
            if message.role == .owner, let projectName = message.projectName {
                Text(projectName)
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .padding(.horizontal, 6)
            }
            HStack(alignment: .bottom) {
                if message.role == .user { Spacer(minLength: 0) }
                OwnerMessageContent(source: message.text)
                    .textSelection(.enabled)
                    .foregroundStyle(
                        message.role == .user
                            ? WorkstateTheme.onAccent
                            : WorkstateTheme.primaryLabel
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        message.role == .user
                            ? WorkstateTheme.activeState
                            : WorkstateTheme.raisedSurfaceBackground,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .frame(maxWidth: 420, alignment: message.role == .user ? .trailing : .leading)
                if message.role == .owner { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct OwnerMessageRow: View {
    let message: ProjectOwnerMessage
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 0)
            }

            Group {
                if snapshotRendering {
                    OwnerMessageContent(source: message.text)
                } else {
                    OwnerMessageContent(source: message.text)
                        .textSelection(.enabled)
                }
            }
                .foregroundStyle(message.role == .user ? WorkstateTheme.onAccent : WorkstateTheme.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    message.role == .user ? WorkstateTheme.activeState : WorkstateTheme.raisedSurfaceBackground,
                    in: UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: 17,
                            bottomLeading: message.role == .owner ? 4 : 17,
                            bottomTrailing: message.role == .user ? 4 : 17,
                            topTrailing: 17
                        ),
                        style: .continuous
                    )
                )
                .frame(
                    maxWidth: 420,
                    alignment: message.role == .user ? .trailing : .leading
                )

            if message.role == .owner {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct OwnerMessageContent: View {
    let source: String

    var body: some View {
        WorkstateMarkdownView(source: source, style: .message)
    }
}

private struct OwnerMessageTimestamp: View {
    let timestamp: Date

    var body: some View {
        Text(OwnerMessageDateText.string(from: timestamp))
            .font(WorkstateTheme.captionEmphasisFont.monospacedDigit())
            .foregroundStyle(WorkstateTheme.tertiaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

struct OwnerTypingIndicator: View {
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(WorkstateTheme.secondaryLabel)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(
                WorkstateTheme.raisedSurfaceBackground,
                in: UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 16,
                        bottomLeading: 4,
                        bottomTrailing: 16,
                        topTrailing: 16
                    ),
                    style: .continuous
                )
            )
            Spacer(minLength: 0)
        }
    }
}

private enum OwnerMessageDateText {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private struct OwnerIssueLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .padding(.top, 6)
            configuration.title
        }
    }
}
