import AppKit
import SwiftUI
import WorkstateCore

enum ProjectWorkspacePage: Hashable {
    case progress
    case topics
    case owner
}

extension ProjectTopicStatus {
    var title: String {
        switch self {
        case .captured: "暂存"
        case .discussing: "讨论中"
        case .converted: "已进入流程"
        case .closed: "已关闭"
        }
    }

    var symbol: String {
        switch self {
        case .captured: "tray.full"
        case .discussing: "bubble.left.and.bubble.right"
        case .converted: "arrow.triangle.branch"
        case .closed: "checkmark"
        }
    }

    var color: Color {
        switch self {
        case .captured: WorkstateTheme.warning
        case .discussing: WorkstateTheme.activeState
        case .converted: WorkstateTheme.success
        case .closed: WorkstateTheme.secondaryLabel
        }
    }
}

extension ProjectTopicKind: Identifiable {
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .product: "产品"
        case .frontend: "前端"
        case .backend: "后端"
        }
    }

    var symbol: String {
        switch self {
        case .product: "lightbulb"
        case .frontend: "macwindow"
        case .backend: "server.rack"
        }
    }
}

extension ProjectTopic {
    var discussionContext: String {
        let questions = openQuestions.map { "- \($0)" }.joined(separator: "\n")
        let sourceText = sourceIDs.map { "- \($0)" }.joined(separator: "\n")
        return """
        项目议题：\(title)

        当前理解
        \(currentUnderstanding)

        初步方向
        \(proposedDirection)

        暂缓原因
        \(deferredReason)

        本次讨论需要解决
        \(questions.isEmpty ? "- 进一步明确问题和处理方向" : questions)

        来源
        \(sourceText)
        """
    }
}

private struct ProjectTopicOriginalStatement: Identifiable {
    let id: String
    let text: String
    let source: String
    let timestamp: Date?

    static func resolve(
        topic: ProjectTopic,
        ownerConversation: ProjectOwnerConversation,
        sources: [SourceReference]
    ) -> [ProjectTopicOriginalStatement] {
        let ownerMessages = Dictionary(
            uniqueKeysWithValues: ownerConversation.messages.map { ($0.id, $0) }
        )
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var statements: [ProjectTopicOriginalStatement] = []
        var seenText = Set<String>()

        func append(_ statement: ProjectTopicOriginalStatement) {
            let key = statement.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seenText.insert(key).inserted else { return }
            statements.append(statement)
        }

        for note in topic.notes.sorted(by: { $0.timestamp < $1.timestamp }) {
            for messageID in note.ownerMessageIDs {
                guard let message = ownerMessages[messageID], message.role == .user else { continue }
                append(
                    ProjectTopicOriginalStatement(
                        id: "owner-\(message.id)",
                        text: message.text,
                        source: "Owner 对话",
                        timestamp: message.timestamp
                    )
                )
            }
        }

        let sourceIDs = topic.sourceIDs + topic.notes.flatMap(\.sourceIDs)
        for sourceID in sourceIDs {
            guard let source = sourceByID[sourceID] else { continue }
            for message in source.excerpt where message.role.lowercased() == "user" {
                append(
                    ProjectTopicOriginalStatement(
                        id: "source-\(source.id)-\(message.id)",
                        text: message.text,
                        source: source.label,
                        timestamp: message.timestamp
                    )
                )
            }
        }

        return statements.sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }
    }
}

struct ProjectTopicsPage: View {
    let project: ProjectRecord
    let topics: [ProjectTopic]
    let ownerConversation: ProjectOwnerConversation
    let sources: [SourceReference]
    @Binding var selectedTopicID: String?
    let onAddTopic: () -> Void
    let onDiscussTopic: (String) -> Void
    let onPromoteTopic: (String, ProjectTopicPromotionKind, String, String) -> Void

    private var selectedTopic: ProjectTopic? {
        selectedTopicID.flatMap { id in topics.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let selectedTopic {
                ProjectTopicDetail(
                    topic: selectedTopic,
                    originalStatements: ProjectTopicOriginalStatement.resolve(
                        topic: selectedTopic,
                        ownerConversation: ownerConversation,
                        sources: sources
                    ),
                    accent: project.accent.color,
                    onDiscuss: { onDiscussTopic(selectedTopic.id) },
                    onPromote: { kind, title, detail in
                        onPromoteTopic(selectedTopic.id, kind, title, detail)
                    }
                )
            } else {
                ProjectTopicList(
                    project: project,
                    topics: topics,
                    onSelect: { selectedTopicID = $0 },
                    onAddTopic: onAddTopic
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkstateTheme.workspaceBackground)
    }
}

private struct ProjectTopicList: View {
    let project: ProjectRecord
    let topics: [ProjectTopic]
    let onSelect: (String) -> Void
    let onAddTopic: () -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(WorkstateTheme.captionEmphasisFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                    Text("议题")
                        .font(WorkstateTheme.projectTitleFont)
                }

                Spacer(minLength: 8)

                Button(action: onAddTopic) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("新增议题")
                .accessibilityLabel("新增议题")
            }
            .padding(.horizontal, 20)
            .padding(.top, 76)
            .padding(.bottom, 18)

            Divider()

            HStack(spacing: 14) {
                TopicCount(status: .captured, topics: topics)
                TopicCount(status: .discussing, topics: topics)
                TopicCount(status: .converted, topics: topics)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 42)

            Divider()

            if topics.isEmpty {
                ContentUnavailableView(
                    "没有议题",
                    systemImage: "tray",
                    description: Text("暂时无法处理的问题会留在这里。")
                )
                .frame(maxHeight: .infinity)
            } else if snapshotRendering {
                VStack(spacing: 0) {
                    topicRows
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        topicRows
                    }
                }
                .scrollIndicators(.visible)
            }
        }
    }

    @ViewBuilder
    private var topicRows: some View {
        ForEach(topics.sorted { $0.updatedAt > $1.updatedAt }) { topic in
            TopicRow(topic: topic, onSelect: { onSelect(topic.id) })
            Divider()
                .padding(.leading, 54)
        }
    }
}

private struct TopicCount: View {
    let status: ProjectTopicStatus
    let topics: [ProjectTopic]

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text("\(topics.filter { $0.status == status }.count) \(status.title)")
        }
        .font(WorkstateTheme.captionFont.monospacedDigit())
        .foregroundStyle(WorkstateTheme.secondaryLabel)
    }
}

private struct TopicRow: View {
    let topic: ProjectTopic
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: topic.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(topic.status.color)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(topic.title)
                            .font(WorkstateTheme.headlineFont)
                            .lineLimit(1)
                        Text(topic.kind.title)
                            .font(WorkstateTheme.microFont)
                            .foregroundStyle(WorkstateTheme.secondaryLabel)
                    }

                    Text(topic.summary)
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(topic.status.title)
                            .foregroundStyle(topic.status.color)
                        Text("·")
                        Text("\(topic.sourceIDs.count) 个来源")
                        Text("·")
                        Text(WorkstateDateText.compact(topic.updatedAt))
                    }
                    .font(WorkstateTheme.microFont.monospacedDigit())
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(WorkstateTheme.primaryLabel.opacity(isHovered ? 0.045 : 0))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ProjectTopicDetail: View {
    let topic: ProjectTopic
    let originalStatements: [ProjectTopicOriginalStatement]
    let accent: Color
    let onDiscuss: () -> Void
    let onPromote: (ProjectTopicPromotionKind, String, String) -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var isPromotionPresented = false

    var body: some View {
        Group {
            if snapshotRendering {
                detailContent
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    detailContent
                }
                .scrollIndicators(.visible)
            }
        }
        .sheet(isPresented: $isPromotionPresented) {
            TopicPromotionSheet(topic: topic, originalStatements: originalStatements) { kind, title, detail in
                onPromote(kind, title, detail)
                isPromotionPresented = false
            }
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
                topicHeader

                Divider()

                TopicDetailSection(title: "你的原话", systemImage: "quote.opening") {
                    OriginalStatementReview(statements: originalStatements)
                }

                TopicDetailSection(title: "当前理解", systemImage: "text.book.closed") {
                    Text(topic.currentUnderstanding)
                        .font(WorkstateTheme.bodyFont)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TopicDetailSection(title: "初步方向", systemImage: "arrow.up.forward") {
                    Text(topic.proposedDirection)
                        .font(WorkstateTheme.secondaryFont)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TopicDetailSection(title: "暂缓", systemImage: "pause.circle") {
                    TopicKeyValue(label: "原因", value: topic.deferredReason)
                    TopicKeyValue(label: "回来处理", value: topic.revisitTrigger)
                }

                if !topic.openQuestions.isEmpty {
                    TopicDetailSection(title: "开放问题", systemImage: "questionmark.circle") {
                        ForEach(topic.openQuestions, id: \.self) { question in
                            Label(question, systemImage: "circle")
                                .labelStyle(TopicQuestionLabelStyle())
                                .font(WorkstateTheme.secondaryFont)
                        }
                    }
                }

                TopicDetailSection(title: "思考记录", systemImage: "clock.arrow.circlepath") {
                    if topic.notes.isEmpty {
                        Text("尚无补充记录")
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    } else {
                        TopicNotesTimeline(notes: topic.notes, accent: accent)
                    }
                }

                TopicDetailSection(title: "来源", systemImage: "text.bubble") {
                    if topic.sourceIDs.isEmpty {
                        Text("尚未关联会话")
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    } else {
                        ForEach(topic.sourceIDs, id: \.self) { sourceID in
                            Text(sourceID)
                                .font(WorkstateTheme.captionFont.monospaced())
                                .foregroundStyle(WorkstateTheme.secondaryLabel)
                                .textSelection(.enabled)
                        }
                    }
                }

                TopicDetailSection(title: "派生任务", systemImage: "arrow.triangle.branch") {
                    if topic.derivedTaskIDs.isEmpty {
                        Text("尚未转成任务")
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    } else {
                        ForEach(topic.derivedTaskIDs, id: \.self) { task in
                            Label(task, systemImage: "checklist")
                                .font(WorkstateTheme.secondaryFont)
                        }
                    }
                }
        }
    }

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Label(topic.status.title, systemImage: topic.status.symbol)
                    .foregroundStyle(topic.status.color)
                Text("·")
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
                Label(topic.kind.title, systemImage: topic.kind.symbol)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
            .font(WorkstateTheme.captionEmphasisFont)

            Text(topic.title)
                .font(WorkstateTheme.projectTitleFont)
                .fixedSize(horizontal: false, vertical: true)

            Text(topic.summary)
                .font(WorkstateTheme.secondaryFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("更新于 \(WorkstateDateText.compact(topic.updatedAt))")
                    .font(WorkstateTheme.captionFont.monospacedDigit())
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)

                Spacer(minLength: 12)

                Button(action: onDiscuss) {
                    Label("开始讨论", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(accent)

                if topic.status == .captured || topic.status == .discussing {
                    Button {
                        isPromotionPresented = true
                    } label: {
                        Label("确认进入流程", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 76)
        .padding(.bottom, 18)
    }
}

private struct OriginalStatementReview: View {
    let statements: [ProjectTopicOriginalStatement]

    var body: some View {
        if statements.isEmpty {
            Label("这个议题尚未关联原始对话", systemImage: "exclamationmark.triangle")
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.warning)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(statements) { statement in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text(statement.source)
                            if let timestamp = statement.timestamp {
                                Text("·")
                                Text(WorkstateDateText.compact(timestamp))
                            }
                        }
                        .font(WorkstateTheme.microFont.monospacedDigit())
                        .foregroundStyle(WorkstateTheme.tertiaryLabel)

                        Text(statement.text)
                            .font(WorkstateTheme.secondaryFont)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, 13)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(WorkstateTheme.separator)
                            .frame(width: 2)
                    }
                }
            }
        }
    }
}

private struct TopicDetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TopicKeyValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.tertiaryLabel)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(WorkstateTheme.secondaryFont)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TopicNotesTimeline: View {
    let notes: [ProjectTopicNote]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(notes.sorted { $0.timestamp > $1.timestamp }) { note in
                HStack(alignment: .top, spacing: 11) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                        Rectangle()
                            .fill(WorkstateTheme.separator)
                            .frame(width: 1, height: 54)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(note.title)
                                .font(WorkstateTheme.secondaryFont.weight(.medium))
                            Spacer(minLength: 8)
                            Text(WorkstateDateText.compact(note.timestamp))
                                .font(WorkstateTheme.microFont.monospacedDigit())
                                .foregroundStyle(WorkstateTheme.tertiaryLabel)
                        }
                        Text(note.detail)
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct TopicQuestionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .padding(.top, 6)
            configuration.title
        }
    }
}

struct TopicComposerSheet: View {
    let project: ProjectRecord
    let onSave: (ProjectTopic) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var kind: ProjectTopicKind = .product
    @State private var origin = ""
    @State private var direction = ""
    @State private var deferredReason = ""
    @State private var revisitTrigger = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新增议题")
                    .font(WorkstateTheme.windowTitleFont)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)

            Divider()

            Form {
                TextField("标题", text: $title)
                Picker("类型", selection: $kind) {
                    ForEach(ProjectTopicKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                TextField("一句话说明", text: $summary, axis: .vertical)
                    .lineLimit(2...4)
                TextField("起源", text: $origin, axis: .vertical)
                    .lineLimit(2...4)
                TextField("初步方向", text: $direction, axis: .vertical)
                    .lineLimit(2...4)
                TextField("为什么现在不做", text: $deferredReason, axis: .vertical)
                    .lineLimit(2...4)
                TextField("什么时候回来处理", text: $revisitTrigger, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
            .padding(12)
        }
        .frame(width: 500, height: 540)
    }

    private func save() {
        let now = Date()
        let originText = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = ProjectTopic(
            id: UUID().uuidString.lowercased(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.isEmpty ? "尚未补充说明。" : summary,
            status: .captured,
            kind: kind,
            currentUnderstanding: originText.isEmpty ? "议题刚刚建立，等待进一步整理。" : originText,
            proposedDirection: direction.isEmpty ? "尚未形成明确方向。" : direction,
            deferredReason: deferredReason.isEmpty ? "当前项目主线优先。" : deferredReason,
            revisitTrigger: revisitTrigger.isEmpty ? "等待合适的处理窗口。" : revisitTrigger,
            openQuestions: [],
            notes: [
                ProjectTopicNote(
                    id: UUID().uuidString.lowercased(),
                    timestamp: now,
                    kind: .origin,
                    title: "议题建立",
                    detail: originText.isEmpty ? "手动建立议题。" : originText
                )
            ],
            sourceIDs: [],
            updatedAt: now
        )
        onSave(topic)
        dismiss()
    }
}

private struct TopicPromotionSheet: View {
    let topic: ProjectTopic
    let originalStatements: [ProjectTopicOriginalStatement]
    let onConfirm: (ProjectTopicPromotionKind, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ProjectTopicPromotionKind = .decision
    @State private var title: String
    @State private var detail: String

    init(
        topic: ProjectTopic,
        originalStatements: [ProjectTopicOriginalStatement],
        onConfirm: @escaping (ProjectTopicPromotionKind, String, String) -> Void
    ) {
        self.topic = topic
        self.originalStatements = originalStatements
        self.onConfirm = onConfirm
        _title = State(initialValue: topic.title)
        _detail = State(initialValue: topic.currentUnderstanding)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("确认进入后续流程")
                        .font(WorkstateTheme.windowTitleFont)
                    Text("先对照原话，再确认 Owner 的总结")
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
                Button("确认") {
                    onConfirm(
                        kind,
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding(18)

            Divider()

            Form {
                Section("你的原话") {
                    OriginalStatementReview(statements: originalStatements)
                }

                Section("正式写入") {
                    Picker("进入方式", selection: $kind) {
                        Label("确认为项目方向", systemImage: "checkmark.seal")
                            .tag(ProjectTopicPromotionKind.decision)
                        Label("转为后续任务", systemImage: "arrow.triangle.branch")
                            .tag(ProjectTopicPromotionKind.task)
                    }
                    .pickerStyle(.radioGroup)

                    TextField("标题", text: $title)
                    TextField(
                        kind == .decision ? "正式结论" : "任务目标",
                        text: $detail,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                }
            }
            .formStyle(.grouped)
            .padding(12)
        }
        .frame(width: 560, height: 620)
    }
}

private struct DiscussionContextSheet: View {
    let topic: ProjectTopic
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("讨论上下文", systemImage: "bubble.left.and.bubble.right")
                    .font(WorkstateTheme.windowTitleFont)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(18)

            Divider()

            ScrollView {
                Text(topic.discussionContext)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }

            Divider()

            HStack {
                Text(copied ? "已复制" : "")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.success)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(topic.discussionContext, forType: .string)
                    copied = true
                } label: {
                    Label("复制上下文", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }
}
