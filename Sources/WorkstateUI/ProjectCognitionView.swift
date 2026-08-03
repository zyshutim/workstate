import SwiftUI
import WorkstateCore

struct ProjectCognitionView: View {
    let project: ProjectRecord
    @ObservedObject var model: WorkstateViewModel
    @State private var activeRevisionID: String?
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    private var cognition: ProjectCognitionDocument? { project.context.cognition }
    private var isGenerating: Bool { model.cognitionGeneratingProjectIDs.contains(project.id) }
    private var missingContext: [String] { model.cognitionMissingContext[project.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if snapshotRendering {
                GeometryReader { proxy in
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .topLeading
                        )
                        .clipped()
                }
            } else {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity)
        .background(WorkstateTheme.contextBackground.opacity(0.42))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(WorkstateTheme.projectTitleFont)
                Text("Owner 项目报告")
                    .font(WorkstateReportTokens.metadataFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
            Spacer(minLength: 8)
            if let cognition {
                switch cognition.state {
                case .uninitialized:
                    EmptyView()
                case .draft:
                    Label("草稿", systemImage: "doc.text")
                        .font(WorkstateReportTokens.metadataFont)
                        .foregroundStyle(WorkstateTheme.warning)
                case .confirmed:
                    Text("v\(cognition.version)")
                        .font(WorkstateReportTokens.metadataFont.monospacedDigit())
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                    if cognition.revisions.contains(where: { $0.status == .pending }) {
                        Label("待确认", systemImage: "pencil.line")
                            .font(WorkstateReportTokens.metadataFont)
                            .foregroundStyle(WorkstateTheme.warning)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 76)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var content: some View {
        if isGenerating {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView()
                Text("正在根据项目证据生成 Owner 报告…")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
        } else if !missingContext.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("证据还不够，暂不生成", systemImage: "exclamationmark.circle")
                    .font(WorkstateTheme.headlineFont)
                    .foregroundStyle(WorkstateTheme.warning)
                ForEach(missingContext, id: \.self) { item in
                    Text(item)
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }
                Button("重新生成") {
                    model.generateProjectCognition(projectID: project.id)
                }
                .buttonStyle(.bordered)
            }
        } else if cognition == nil || cognition?.state == .uninitialized {
            VStack(alignment: .leading, spacing: 12) {
                Text("还没有 Owner 项目报告")
                    .font(WorkstateTheme.headlineFont)
                Text("只在你点击后生成，生成后仍需你确认才会成为正式项目认知。")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                Button("建立项目报告") {
                    model.generateProjectCognition(projectID: project.id)
                }
                .buttonStyle(.borderedProminent)
            }
        } else if cognition?.state == .draft {
            draftContent(cognition!)
        } else if cognition?.state == .confirmed {
            confirmedContent(cognition!)
        }
    }

    private func draftContent(_ cognition: ProjectCognitionDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if missingContext.isEmpty {
                Text("这是 Owner 报告草稿。确认后才会成为正式项目认知 v1。")
                    .font(WorkstateReportTokens.metadataFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            } else {
                Label("证据还不够，暂不生成", systemImage: "exclamationmark.circle")
                    .foregroundStyle(WorkstateTheme.warning)
                ForEach(missingContext, id: \.self) { item in
                    Text(item)
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }
            }
            cognitionSections(cognition.sections, revisions: [])
            if missingContext.isEmpty {
                HStack {
                    Button("重新生成", systemImage: "arrow.clockwise") {
                        model.generateProjectCognition(projectID: project.id)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("确认成为 v1") {
                        model.confirmProjectCognition(projectID: project.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
    }

    private func confirmedContent(_ cognition: ProjectCognitionDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cognitionSections(cognition.sections, revisions: cognition.revisions)
        }
    }

    @ViewBuilder
    private func cognitionSections(
        _ sections: [ProjectCognitionSection],
        revisions: [ProjectCognitionRevision]
    ) -> some View {
        let sortedSections = sections.sorted { $0.order < $1.order }
        ForEach(Array(sortedSections.enumerated()), id: \.element.id) { index, section in
            let revision = revisions.first {
                $0.status == .pending
                    && ($0.beforeSections + $0.afterSections).contains(where: { $0.id == section.id })
            }
            CognitionSectionRow(section: section, revision: revision, isLead: index == 0) {
                guard let revision else { return }
                activeRevisionID = revision.id
            }
            .popover(
                isPresented: Binding(
                    get: { activeRevisionID == revision?.id && revision != nil },
                    set: { if !$0 { activeRevisionID = nil } }
                ),
                arrowEdge: .trailing
            ) {
                if let revision {
                    CognitionRevisionPopover(
                        revision: revision,
                        sources: sources(for: revision),
                        onResolve: { resolution, edited in
                            model.resolveProjectCognitionRevision(
                                projectID: project.id,
                                revisionID: revision.id,
                                resolution: resolution,
                                editedAfterSections: edited
                            )
                            activeRevisionID = nil
                        }
                    )
                    .frame(width: 310)
                }
            }
        }

        ForEach(
            revisions.filter { revision in
                revision.status == .pending && revision.operation != .update
                    && !sections.contains { section in
                        (revision.beforeSections + revision.afterSections).contains { candidate in
                            candidate.id == section.id
                        }
                    }
            }
        ) { revision in
            CognitionStructuralRevisionRow(revision: revision) {
                activeRevisionID = revision.id
            }
            .popover(
                isPresented: Binding(
                    get: { activeRevisionID == revision.id },
                    set: { if !$0 { activeRevisionID = nil } }
                ),
                arrowEdge: .trailing
            ) {
                CognitionRevisionPopover(
                    revision: revision,
                    sources: sources(for: revision),
                    onResolve: { resolution, edited in
                        model.resolveProjectCognitionRevision(
                            projectID: project.id,
                            revisionID: revision.id,
                            resolution: resolution,
                            editedAfterSections: edited
                        )
                        activeRevisionID = nil
                    }
                )
                .frame(width: 310)
            }
        }
    }

    private func sources(for revision: ProjectCognitionRevision) -> [SourceReference] {
        let ids = Set(revision.sourceIDs)
        return model.workspace.sources.filter { ids.contains($0.id) }
    }
}

private struct CognitionSectionRow: View {
    let section: ProjectCognitionSection
    let revision: ProjectCognitionRevision?
    let isLead: Bool
    let onRevisionTap: () -> Void

    var body: some View {
        Group {
            if let revision,
               revision.operation != .update,
               revision.beforeSections.first?.id != section.id {
                EmptyView()
            } else {
                sectionContent
            }
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: isLead ? 12 : 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    if let revision, revision.operation == .update,
                       let before = revision.beforeSections.first,
                       let after = revision.afterSections.first,
                       before.title != after.title {
                        Text(before.title)
                            .strikethrough()
                            .foregroundStyle(WorkstateTheme.danger.opacity(0.8))
                        Text(after.title)
                            .foregroundStyle(WorkstateTheme.success)
                    } else {
                        Text(section.title)
                    }
                }
                .font(isLead
                    ? WorkstateReportTokens.leadTitleFont
                    : WorkstateReportTokens.sectionTitleFont)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if revision != nil {
                    Button(action: onRevisionTap) {
                        Image(systemName: "pencil.line")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WorkstateTheme.warning)
                    .help("查看这处认知修改")
                }
            }
            if let revision, revision.operation == .update,
               let before = revision.beforeSections.first,
               let after = revision.afterSections.first {
                WorkstateMarkdownView(source: before.body, style: markdownStyle)
                    .strikethrough()
                    .foregroundStyle(WorkstateTheme.danger.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                WorkstateMarkdownView(source: after.body, style: markdownStyle)
                    .padding(7)
                    .background(WorkstateTheme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let revision {
                ForEach(revision.beforeSections) { before in
                    WorkstateMarkdownView(source: before.body, style: markdownStyle)
                        .strikethrough()
                        .foregroundStyle(WorkstateTheme.danger.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(revision.afterSections) { after in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(after.title)
                            .font(WorkstateTheme.captionEmphasisFont)
                        WorkstateMarkdownView(source: after.body, style: markdownStyle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(5)
                    .background(
                        WorkstateTheme.success.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
            } else {
                WorkstateMarkdownView(source: section.body, style: markdownStyle)
                    .foregroundStyle(WorkstateTheme.primaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, isLead
            ? WorkstateReportTokens.leadSectionSpacing
            : WorkstateReportTokens.sectionSpacing)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.62))
                .frame(height: 0.5)
        }
    }

    private var markdownStyle: WorkstateMarkdownStyle {
        isLead ? .reportLead : .report
    }
}

private struct CognitionRevisionPopover: View {
    let revision: ProjectCognitionRevision
    let sources: [SourceReference]
    let onResolve: (ProjectCognitionRevisionResolution, [ProjectCognitionSection]?) -> Void
    @State private var isEditing = false
    @State private var editedBodies: [String: String]

    init(
        revision: ProjectCognitionRevision,
        sources: [SourceReference],
        onResolve: @escaping (ProjectCognitionRevisionResolution, [ProjectCognitionSection]?) -> Void
    ) {
        self.revision = revision
        self.sources = sources
        self.onResolve = onResolve
        _editedBodies = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: revision.afterSections.map { ($0.id, $0.body) }
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("认知修改")
                .font(WorkstateTheme.headlineFont)
            Text(revision.rationale)
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            if isEditing, !revision.afterSections.isEmpty {
                ForEach(revision.afterSections) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.title)
                            .font(WorkstateTheme.captionEmphasisFont)
                        TextEditor(text: Binding(
                            get: { editedBodies[section.id] ?? section.body },
                            set: { editedBodies[section.id] = $0 }
                        ))
                        .font(WorkstateTheme.bodyFont)
                        .frame(height: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(WorkstateTheme.separator, lineWidth: 0.5)
                        }
                    }
                }
            } else {
                ForEach(revision.afterSections) { after in
                    WorkstateMarkdownView(source: after.body, style: .message)
                        .fixedSize(horizontal: false, vertical: true)
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

            HStack {
                Button("拒绝") { onResolve(.rejected, nil) }
                    .buttonStyle(.bordered)
                Spacer()
                if isEditing {
                    Button("接受修改") {
                        let edited = revision.afterSections.map { section in
                            var value = section
                            value.body = editedBodies[section.id] ?? section.body
                            return value
                        }
                        onResolve(.accepted, edited)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("编辑后接受") { isEditing = true }
                        .buttonStyle(.bordered)
                    Button("接受") { onResolve(.accepted, nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
    }
}

private struct CognitionStructuralRevisionRow: View {
    let revision: ProjectCognitionRevision
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(WorkstateTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(structureTitle)
                        .font(WorkstateTheme.captionEmphasisFont)
                        .foregroundStyle(WorkstateTheme.primaryLabel)
                    ForEach(revision.afterSections) { section in
                        WorkstateMarkdownView(source: section.body, style: .report)
                            .foregroundStyle(WorkstateTheme.success)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if revision.afterSections.isEmpty {
                        Text(revision.rationale)
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private var structureTitle: String {
        switch revision.operation {
        case .insert: "新增认知段落"
        case .delete: "删除认知段落"
        case .split: "拆分认知段落"
        case .merge: "合并认知段落"
        case .update: "更新认知段落"
        }
    }
}
