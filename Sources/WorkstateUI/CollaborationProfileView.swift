import SwiftUI
import WorkstateCore

struct CollaborationProfileView: View {
    let profile: CollaborationProfile
    let conversation: CollaborationConversation
    let isSending: Bool
    let onClose: () -> Void
    let onSend: (String) -> Void
    @State private var section: Section = .profile
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    private enum Section: String, CaseIterable, Identifiable {
        case profile = "档案"
        case conversation = "对话"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if section == .profile {
                profileContent
            } else {
                conversationContent
            }
        }
        .background(WorkstateTheme.workspaceBackground)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("返回")
                Spacer()
                Text("协作档案")
                    .font(WorkstateTheme.windowTitleFont)
                Spacer()
                Color.clear.frame(width: 14, height: 14)
            }

            if snapshotRendering {
                HStack(spacing: 0) {
                    ForEach(Section.allCases) { item in
                        Text(item.rawValue)
                            .font(WorkstateTheme.captionEmphasisFont)
                            .frame(width: 120, height: 28)
                            .background(
                                item == section
                                    ? WorkstateTheme.raisedSurfaceBackground
                                    : Color.clear
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(WorkstateTheme.separator, lineWidth: 0.5)
                }
            } else {
                Picker("协作档案", selection: $section) {
                    ForEach(Section.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var profileContent: some View {
        Group {
            if snapshotRendering {
                VStack(alignment: .leading, spacing: 20) {
                    profileEntries
                    Spacer(minLength: 0)
                }
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        profileEntries
                    }
                    .padding(20)
                }
            }
        }
    }

    @ViewBuilder
    private var profileEntries: some View {
        if profile.entries.isEmpty {
            ContentUnavailableView(
                "还没有协作档案",
                systemImage: "person.text.rectangle",
                description: Text("在“对话”中说明你的协作习惯，明确内容会沉淀到这里。")
            )
            .frame(maxWidth: .infinity, minHeight: 520)
        } else {
            ForEach(CollaborationEntryKind.allCases) { kind in
                let entries = profile.entries
                    .filter { $0.kind == kind && $0.status != .superseded }
                    .sorted { $0.updatedAt > $1.updatedAt }
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title(for: kind))
                            .font(WorkstateTheme.sectionTitleFont)
                        ForEach(entries) { entry in
                            CollaborationEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private var conversationContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if conversation.messages.isEmpty {
                            Text("这里讨论的是我们怎么协作，不是某个项目本身。")
                                .font(WorkstateTheme.bodyFont)
                                .foregroundStyle(WorkstateTheme.secondaryLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 16)
                        }
                        ForEach(conversation.messages) { message in
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
                                    .frame(maxWidth: 420)
                                    .id(message.id)
                                if message.role == .owner { Spacer(minLength: 0) }
                            }
                        }
                        if isSending {
                            OwnerTypingIndicator()
                                .id("collaboration-thinking")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    guard let id = conversation.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
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

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(WorkstateTheme.onAccent, WorkstateTheme.activeState)
                }
                .buttonStyle(.plain)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
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
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        draft = ""
        onSend(message)
        composerFocused = true
    }

    private func title(for kind: CollaborationEntryKind) -> String {
        switch kind {
        case .userPersona: "你的 Persona"
        case .collaboratorPersona: "协作者 Persona"
        case .preference: "偏好"
        case .rule: "Rules"
        case .loop: "Loops"
        case .prohibition: "禁止项"
        }
    }
}

private struct CollaborationEntryRow: View {
    let entry: CollaborationProfileEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(WorkstateTheme.headlineFont)
                Spacer()
                if entry.status == .candidate {
                    Text("候选")
                        .font(WorkstateTheme.microFont)
                        .foregroundStyle(WorkstateTheme.warning)
                }
            }
            Text(entry.detail)
                .font(WorkstateTheme.bodyFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.evidence.isEmpty {
                DisclosureGroup("依据") {
                    ForEach(entry.evidence, id: \.self) { evidence in
                        Text(evidence)
                            .font(WorkstateTheme.captionFont)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            WorkstateTheme.raisedSurfaceBackground,
            in: RoundedRectangle(cornerRadius: WorkstateTheme.cornerRadius, style: .continuous)
        )
    }
}
