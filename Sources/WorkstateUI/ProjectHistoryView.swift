import SwiftUI
import WorkstateCore

struct ProjectWorkspaceView: View {
    let project: ProjectRecord
    @ObservedObject var model: WorkstateViewModel
    @Environment(\.workstateSnapshotWorkspacePage) private var snapshotWorkspacePage
    @Environment(\.workstateSnapshotTopicID) private var snapshotTopicID
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var page: ProjectWorkspacePage = .progress
    @State private var selectedTopicID: String?
    @State private var activeOwnerTopicID: String?
    @State private var isComposerPresented = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            workspaceBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                switch displayedPage {
                case .progress:
                    ProjectContextSection(
                        project: project,
                        isExpanded: model.isContextExpanded,
                        onToggle: model.toggleContext
                    )

                    ProjectTimelineSection(
                        workspace: model.workspace,
                        project: project,
                        liveActivity: model.liveActivity(for: project.id),
                        isContextExpanded: model.isContextExpanded,
                        selectedEventID: model.selectedEventID,
                        onSelectEvent: model.selectEvent,
                        onSelectTaskEvent: model.selectTaskEvent,
                        onDismissEvent: model.closeEvent
                    )
                case .topics:
                    ProjectTopicsPage(
                        project: project,
                        topics: project.topics,
                        ownerConversation: model.ownerConversation(for: project.id),
                        sources: model.workspace.sources,
                        selectedTopicID: displayedSelectedTopicID,
                        onAddTopic: { isComposerPresented = true },
                        onDiscussTopic: beginTopicDiscussion,
                        onPromoteTopic: { topicID, kind, title, detail in
                            model.promoteTopic(
                                projectID: project.id,
                                topicID: topicID,
                                kind: kind,
                                title: title,
                                detail: detail
                            )
                        },
                        onResolveTopic: { topicID, resolution in
                            model.resolveTopic(
                                projectID: project.id,
                                topicID: topicID,
                                resolution: resolution
                            )
                        }
                    )
                case .owner:
                    ProjectOwnerChatView(
                        project: project,
                        activeTopic: activeOwnerTopicID.flatMap(project.topic(id:)),
                        conversation: model.ownerConversation(for: project.id),
                        isSending: model.ownerChatSendingProjectIDs.contains(project.id),
                        onClearTopic: { activeOwnerTopicID = nil },
                        onSend: {
                            model.sendOwnerMessage(
                                $0,
                                projectID: project.id,
                                topicID: activeOwnerTopicID
                            )
                        }
                    )
                }
            }

            utilityHeader
                .zIndex(30)

            if snapshotRendering,
               displayedPage == .progress,
               let eventID = model.selectedEventID,
               let event = project.event(id: eventID) {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .zIndex(35)

                EventDetailPopover(
                    workspace: model.workspace,
                    project: project,
                    task: event.taskID.flatMap(project.task(id:)),
                    event: event,
                    onSelectTaskEvent: model.selectTaskEvent,
                    onClose: model.closeEvent
                )
                .frame(
                    width: WorkstateTheme.eventPopoverWidth,
                    height: WorkstateTheme.eventPopoverHeight
                )
                .padding(.top, 76)
                .padding(.trailing, 22)
                .zIndex(40)
            }
        }
        .frame(width: WorkstateTheme.projectWidth)
        .sheet(isPresented: $isComposerPresented) {
            TopicComposerSheet(project: project) { topic in
                model.saveTopic(topic, projectID: project.id)
                selectedTopicID = topic.id
            }
        }
        .onChange(of: page) { _, newValue in
            if newValue != .topics {
                selectedTopicID = nil
            }
        }
    }

    private var utilityHeader: some View {
        WorkstateGlassContainer {
            HStack(spacing: 10) {
                WorkspaceToolbarButton(
                    systemName: "chevron.left",
                    accessibilityLabel: selectedTopicID == nil ? "返回项目图谱" : "返回议题列表",
                    action: navigateBack
                )
                .frame(width: 38, height: 38)
                .workstateGlassSurface(cornerRadius: 14, interactive: true)

                Spacer(minLength: 8)

                Group {
                    if snapshotRendering {
                        SnapshotWorkspacePicker(selectedPage: displayedPage, topicCount: project.topics.count)
                            .frame(width: 270)
                    } else {
                        Picker("项目页面", selection: displayedPageBinding) {
                            Label("进展", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                                .tag(ProjectWorkspacePage.progress)
                            Label("议题 \(project.topics.count)", systemImage: "tray.full")
                                .tag(ProjectWorkspacePage.topics)
                            Label("Owner", systemImage: "person.crop.circle")
                                .tag(ProjectWorkspacePage.owner)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 270)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    model.copyHandoffPrompt(projectID: project.id)
                } label: {
                    Image(
                        systemName: model.copiedHandoffProjectID == project.id
                            ? "checkmark"
                            : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .help(
                    model.copiedHandoffProjectID == project.id
                        ? "已复制交接 Prompt"
                        : "复制项目交接 Prompt"
                )
                .accessibilityLabel("复制项目交接 Prompt")

                HStack(spacing: 5) {
                    Circle()
                        .fill(project.status.color(accent: project.accent))
                        .frame(width: 6, height: 6)
                    WorkspaceToolbarButton(
                        systemName: "arrow.clockwise",
                        accessibilityLabel: "刷新",
                        action: { model.reload(force: true) }
                    )
                }
                .padding(.leading, 12)
                .padding(.trailing, 5)
                .frame(height: 38)
                .workstateGlassSurface(cornerRadius: 14, interactive: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func navigateBack() {
        if selectedTopicID != nil {
            selectedTopicID = nil
        } else {
            model.leaveProject()
        }
    }

    private func beginTopicDiscussion(_ topicID: String) {
        activeOwnerTopicID = topicID
        selectedTopicID = nil
        page = .owner
    }

    private var displayedPage: ProjectWorkspacePage {
        switch snapshotWorkspacePage {
        case "topics": .topics
        case "owner": .owner
        default: page
        }
    }

    private var displayedPageBinding: Binding<ProjectWorkspacePage> {
        switch snapshotWorkspacePage {
        case "topics": .constant(.topics)
        case "owner": .constant(.owner)
        default: $page
        }
    }

    private var displayedSelectedTopicID: Binding<String?> {
        guard snapshotWorkspacePage == "topics" else { return $selectedTopicID }
        return .constant(snapshotTopicID)
    }

    private var workspaceBackground: Color {
        WorkstateTheme.workspaceBackground
    }
}

private struct SnapshotWorkspacePicker: View {
    let selectedPage: ProjectWorkspacePage
    let topicCount: Int

    var body: some View {
        HStack(spacing: 2) {
            segment("进展", page: .progress)
            segment("议题 \(topicCount)", page: .topics)
            segment("Owner", page: .owner)
        }
        .padding(2)
        .background(
            WorkstateTheme.primaryLabel.opacity(0.08),
            in: RoundedRectangle(cornerRadius: WorkstateTheme.smallCornerRadius)
        )
    }

    private func segment(_ title: String, page: ProjectWorkspacePage) -> some View {
        Text(title)
            .font(WorkstateTheme.captionEmphasisFont)
            .foregroundStyle(page == selectedPage ? WorkstateTheme.primaryLabel : WorkstateTheme.secondaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                page == selectedPage ? WorkstateTheme.raisedSurfaceBackground : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

private struct WorkspaceToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(WorkstateTheme.primaryLabel.opacity(isHovered ? 0.09 : 0))
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct ProjectContextSection: View {
    let project: ProjectRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(project.name)
                        .font(WorkstateTheme.projectTitleFont)
                        .lineLimit(1)

                    Text(project.context.currentSummary)
                        .font(WorkstateTheme.secondaryFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                }

                Spacer(minLength: 8)

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起项目理解" : "展开项目理解")
                .help(isExpanded ? "收起项目理解" : "展开项目理解")
            }
            .padding(.horizontal, 20)
            .padding(.top, 76)
            .padding(.bottom, 18)

            if isExpanded {
                Rectangle()
                    .fill(WorkstateTheme.separator.opacity(0.72))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                expandedContext
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: isExpanded)
    }

    private var expandedContext: some View {
        Group {
            if snapshotRendering {
                expandedContextSnapshotContent
                    .frame(width: WorkstateTheme.projectWidth, height: 220, alignment: .topLeading)
                    .clipped()
            } else {
                ScrollView {
                    expandedContextContent
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(height: 220)
        .background(contextBackground)
        .clipped()
    }

    private var expandedContextContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ContextBlock(title: "项目目的", values: [project.context.purpose])
            ContextBlock(title: "开放问题", values: project.context.openIssues)

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.64))
                .frame(height: 0.5)

            ContextUnderstandingSection(statements: project.context.understanding)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var expandedContextSnapshotContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContextBlock(title: "项目目的", values: [project.context.purpose])
            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.64))
                .frame(height: 0.5)
            ContextUnderstandingSection(statements: Array(project.context.understanding.prefix(2)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var contextBackground: Color {
        WorkstateTheme.contextBackground.opacity(0.38)
    }
}

private struct ContextBlock: View {
    let title: String
    let values: [String]

    private var visibleValues: [String] {
        values.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)

            ForEach(Array(visibleValues.enumerated()), id: \.offset) { _, value in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(WorkstateTheme.tertiaryLabel)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                    Text(value)
                        .font(WorkstateTheme.captionFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ContextRevisionRow: View {
    let revision: ContextRevision

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(revision.title)
                    .font(WorkstateTheme.captionEmphasisFont)
                Spacer(minLength: 4)
                Text(WorkstateDateText.compact(revision.timestamp))
                    .font(WorkstateTheme.microFont.monospacedDigit())
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
            }
            Text(revision.summary)
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.56))
                .frame(height: 0.5)
        }
    }
}

private struct ContextUnderstandingSection: View {
    let statements: [ContextStatement]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前有效理解")
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)

            ForEach(statements) { statement in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(statement.status.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statement.text)
                            .font(WorkstateTheme.secondaryFont)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(statement.status.displayName) · \(WorkstateDateText.compact(statement.updatedAt))")
                            .font(WorkstateTheme.microFont.monospacedDigit())
                            .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    }
                }
            }
        }
    }
}

private struct ProjectTimelineSection: View {
    let workspace: WorkspaceSnapshot
    let project: ProjectRecord
    let liveActivity: LiveProjectActivity?
    let isContextExpanded: Bool
    let selectedEventID: String?
    let onSelectEvent: (String) -> Void
    let onSelectTaskEvent: (String) -> Void
    let onDismissEvent: () -> Void
    @Environment(\.workstateSnapshotProgressMode) private var snapshotProgressMode
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var mode: ProjectProgressVisualizationMode = .timeline
    @State private var includesBranchHistory = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.72))
                .frame(height: 0.5)

            HStack {
                if displayedMode == .branches {
                    if snapshotRendering {
                        SnapshotHistoryToggle(isOn: displayedIncludesBranchHistory)
                    } else {
                        Toggle("历史", isOn: $includesBranchHistory)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(WorkstateTheme.microFont)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
                Group {
                    if snapshotRendering {
                        SnapshotProgressModePicker(mode: displayedMode)
                    } else {
                        Picker("进展视图", selection: $mode) {
                            Text("时间").tag(ProjectProgressVisualizationMode.timeline)
                            Text("分支").tag(ProjectProgressVisualizationMode.branches)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                    }
                }
                .frame(width: 132)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.54))
                .frame(height: 0.5)

            Group {
                switch displayedMode {
                case .timeline:
                    ProjectGitTimeline(
                        workspace: workspace,
                        project: project,
                        liveActivity: liveActivity,
                        isContextExpanded: isContextExpanded,
                        selectedEventID: selectedEventID,
                        onSelectEvent: onSelectEvent,
                        onSelectTaskEvent: onSelectTaskEvent,
                        onDismissEvent: onDismissEvent
                    )
                case .branches:
                    ProjectBranchTreeView(
                        workspace: workspace,
                        project: project,
                        includesHistory: displayedIncludesBranchHistory,
                        isContextExpanded: isContextExpanded,
                        selectedEventID: selectedEventID,
                        onSelectEvent: onSelectEvent,
                        onSelectTaskEvent: onSelectTaskEvent,
                        onDismissEvent: onDismissEvent
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .background(timelineBackground)
        .onChange(of: mode) { _, _ in
            onDismissEvent()
        }
        .onChange(of: includesBranchHistory) { _, _ in
            onDismissEvent()
        }
    }

    private var displayedMode: ProjectProgressVisualizationMode {
        snapshotProgressMode?.hasPrefix(ProjectProgressVisualizationMode.branches.rawValue) == true
            ? .branches
            : mode
    }

    private var displayedIncludesBranchHistory: Bool {
        snapshotProgressMode == "branches-history" ? true : includesBranchHistory
    }

    private var timelineBackground: Color {
        WorkstateTheme.timelineBackground
    }
}

private struct SnapshotHistoryToggle: View {
    let isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("历史")
                .font(WorkstateTheme.microFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            Capsule()
                .fill(isOn ? WorkstateTheme.activeState : WorkstateTheme.primaryLabel.opacity(0.14))
                .frame(width: 26, height: 15)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                        .padding(2)
                }
        }
    }
}

private enum ProjectProgressVisualizationMode: String, CaseIterable {
    case timeline
    case branches
}

private struct SnapshotProgressModePicker: View {
    let mode: ProjectProgressVisualizationMode

    var body: some View {
        HStack(spacing: 2) {
            segment("时间", mode: .timeline)
            segment("分支", mode: .branches)
        }
        .padding(2)
        .background(
            WorkstateTheme.primaryLabel.opacity(0.08),
            in: RoundedRectangle(cornerRadius: WorkstateTheme.smallCornerRadius)
        )
    }

    private func segment(_ title: String, mode candidate: ProjectProgressVisualizationMode) -> some View {
        Text(title)
            .font(WorkstateTheme.microFont.weight(.medium))
            .foregroundStyle(candidate == mode ? WorkstateTheme.primaryLabel : WorkstateTheme.secondaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                candidate == mode ? WorkstateTheme.raisedSurfaceBackground : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

private struct ProjectGitTimeline: View {
    let workspace: WorkspaceSnapshot
    let project: ProjectRecord
    let liveActivity: LiveProjectActivity?
    let isContextExpanded: Bool
    let selectedEventID: String?
    let onSelectEvent: (String) -> Void
    let onSelectTaskEvent: (String) -> Void
    let onDismissEvent: () -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    private var layout: ProjectTimelineLayout {
        ProjectTimelineLayout(
            project: project,
            topInset: liveActivity == nil ? 0 : WorkstateTheme.timelineRowHeight
        )
    }

    private var taskColors: [String: Color] {
        TimelineTaskPalette.colors(
            for: project,
            primaryTaskID: layout.primaryTaskID
        )
    }

    private var legendTasks: [TaskRecord] {
        let displayedTaskIDs = Set(layout.nodes.compactMap { $0.task?.id })
        return project.tasks
            .filter {
                displayedTaskIDs.contains($0.id)
                    && ($0.status == .active || $0.status == .waiting)
            }
            .sorted { left, right in
                if left.id == layout.primaryTaskID { return true }
                if right.id == layout.primaryTaskID { return false }
                if left.status.sortOrder != right.status.sortOrder {
                    return left.status.sortOrder < right.status.sortOrder
                }
                if left.updatedAt == right.updatedAt { return left.id < right.id }
                return left.updatedAt > right.updatedAt
            }
    }

    private var legendHeight: CGFloat {
        TimelineTaskLegend.height(for: legendTasks.count)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if snapshotRendering {
                    timelineContent
                        .frame(
                            width: WorkstateTheme.projectWidth,
                            height: isContextExpanded ? 284 : 520,
                            alignment: .topLeading
                        )
                        .clipped()
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        timelineContent
                            .padding(.bottom, legendHeight + 24)
                    }
                    .scrollIndicators(.visible)
                }
            }

            if !legendTasks.isEmpty {
                TimelineTaskLegend(
                    tasks: legendTasks,
                    colors: taskColors,
                    primaryTaskID: layout.primaryTaskID
                )
                .padding(12)
            }
        }
    }

    private var timelineContent: some View {
        ZStack(alignment: .topLeading) {
            TimelineBackdrop(layout: layout)
            TimelineBranches(project: project, layout: layout, taskColors: taskColors)

            if let liveActivity {
                LiveActivityNode(
                    activity: liveActivity,
                    accent: project.accent.color,
                    nodeX: ProjectTimelineLayout.mainlineX,
                    labelStartX: layout.labelStartX,
                    contentWidth: layout.contentSize.width
                )
                    .position(
                        x: layout.contentSize.width / 2,
                        y: 58
                    )
            }

            ForEach(layout.nodes) { node in
                TimelineEventButton(
                    workspace: workspace,
                    project: project,
                    event: node.event,
                    task: node.task,
                    taskColors: taskColors,
                    isSelected: selectedEventID == node.event.id,
                    nodeX: node.point.x,
                    labelStartX: layout.labelStartX,
                    contentWidth: layout.contentSize.width,
                    onSelect: { onSelectEvent(node.event.id) },
                    onSelectTaskEvent: onSelectTaskEvent,
                    onDismiss: onDismissEvent
                )
                .position(
                    x: layout.contentSize.width / 2,
                    y: node.point.y
                )
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
    }
}

private struct LiveActivityNode: View {
    let activity: LiveProjectActivity
    let accent: Color
    let nodeX: CGFloat
    let labelStartX: CGFloat
    let contentWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            ProgressView()
                .controlSize(.small)
                .tint(accent)
                .frame(width: TimelineNodeLayout.hitSize, height: TimelineNodeLayout.hitSize)
                .offset(x: nodeX - TimelineNodeLayout.hitSize / 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(WorkstateTheme.secondaryFont.weight(.semibold))
                    .foregroundStyle(WorkstateTheme.primaryLabel)
                    .lineLimit(1)
                Text(WorkstateDateText.compact(activity.updatedAt))
                    .font(WorkstateTheme.microFont.monospacedDigit())
                    .foregroundStyle(accent)
            }
            .padding(.leading, labelStartX)
        }
        .frame(
            width: contentWidth,
            height: TimelineNodeLayout.labelHeight,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在进行，\(activity.title)")
    }
}

private struct TimelineBackdrop: View {
    let layout: ProjectTimelineLayout

    var body: some View {
        Canvas { context, size in
            var mainline = Path()
            mainline.move(to: CGPoint(x: ProjectTimelineLayout.mainlineX, y: 28))
            mainline.addLine(to: CGPoint(x: ProjectTimelineLayout.mainlineX, y: size.height))
            context.stroke(
                mainline,
                with: .color(WorkstateTheme.secondaryLabel.opacity(0.34)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )

            for y in layout.rowYs.dropLast() {
                var row = Path()
                row.move(to: CGPoint(x: 20, y: y + WorkstateTheme.timelineRowHeight / 2))
                row.addLine(to: CGPoint(x: size.width - 20, y: y + WorkstateTheme.timelineRowHeight / 2))
                context.stroke(row, with: .color(WorkstateTheme.separator.opacity(0.20)), lineWidth: 0.5)
            }

            let cap = CGRect(x: ProjectTimelineLayout.mainlineX - 3, y: 25, width: 6, height: 6)
            context.fill(Path(ellipseIn: cap), with: .color(WorkstateTheme.secondaryLabel.opacity(0.58)))
        }
        .allowsHitTesting(false)
    }
}

private struct TimelineBranches: View {
    let project: ProjectRecord
    let layout: ProjectTimelineLayout
    let taskColors: [String: Color]

    var body: some View {
        Canvas { context, _ in
            for branch in layout.branches {
                guard let first = branch.points.first else { continue }
                let color = branch.task.flatMap { taskColors[$0.id] } ?? project.accent.color
                var path = Path()
                path.move(to: first)
                var previous = first
                for point in branch.points.dropFirst() {
                    appendCurve(from: previous, to: point, path: &path)
                    previous = point
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(0.74)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func appendCurve(from start: CGPoint, to end: CGPoint, path: inout Path) {
        let middleY = (start.y + end.y) / 2
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x, y: middleY),
            control2: CGPoint(x: end.x, y: middleY)
        )
    }
}

private struct TimelineEventButton: View {
    let workspace: WorkspaceSnapshot
    let project: ProjectRecord
    let event: ProjectEvent
    let task: TaskRecord?
    let taskColors: [String: Color]
    let isSelected: Bool
    let nodeX: CGFloat
    let labelStartX: CGFloat
    let contentWidth: CGFloat
    let onSelect: () -> Void
    let onSelectTaskEvent: (String) -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if snapshotRendering {
            eventButton
        } else {
            eventButton
                .popover(
                    isPresented: detailPopoverBinding,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .leading
                ) {
                    EventDetailPopover(
                        workspace: workspace,
                        project: project,
                        task: task,
                        event: event,
                        onSelectTaskEvent: onSelectTaskEvent,
                        onClose: dismissDetail
                    )
                    .frame(
                        width: WorkstateTheme.eventPopoverWidth,
                        height: WorkstateTheme.eventPopoverHeight
                    )
                }
        }
    }

    private var eventButton: some View {
        Button(action: selectEvent) {
            ZStack(alignment: .leading) {
                eventNode
                    .offset(x: nodeX - TimelineNodeLayout.hitSize / 2)
                eventLabel
                    .padding(.leading, labelStartX)
            }
            .frame(
                width: contentWidth,
                height: TimelineNodeLayout.labelHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                isHovered || isSelected
                    ? nodeColor.opacity(isSelected ? 0.10 : 0.055)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            guard !isSelected else { return }
            isHovered = hovering
        }
    }

    private var eventNode: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(nodeColor.opacity(0.14))
                    .frame(width: 22, height: 22)
            }
            Circle()
                .fill(isSelected || task?.status == .active ? nodeColor : WorkstateTheme.contentBackground)
                .frame(width: isHovered ? 12 : 10, height: isHovered ? 12 : 10)
                .overlay {
                    Circle()
                        .stroke(nodeColor, lineWidth: 1)
                }
        }
        .frame(width: TimelineNodeLayout.hitSize, height: TimelineNodeLayout.hitSize)
    }

    private var eventLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .font(WorkstateTheme.secondaryFont.weight(.semibold))
                .foregroundStyle(WorkstateTheme.primaryLabel)
                .lineLimit(1)

            Text(WorkstateDateText.compact(event.timestamp))
                .font(WorkstateTheme.microFont.monospacedDigit())
                .foregroundStyle(WorkstateTheme.tertiaryLabel)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nodeColor: Color {
        task.flatMap { taskColors[$0.id] } ?? project.accent.color
    }

    private var detailPopoverBinding: Binding<Bool> {
        Binding(
            get: { isSelected },
            set: { presented in
                if !presented && isSelected {
                    onDismiss()
                }
            }
        )
    }

    private func selectEvent() {
        isHovered = false
        onSelect()
    }

    private func dismissDetail() {
        isHovered = false
        onDismiss()
    }
}

private struct TimelineTaskLegend: View {
    private static let width: CGFloat = 280
    private static let rowHeight: CGFloat = 18
    private static let rowSpacing: CGFloat = 8
    private static let verticalPadding: CGFloat = 12

    let tasks: [TaskRecord]
    let colors: [String: Color]
    let primaryTaskID: String?

    static func height(for taskCount: Int) -> CGFloat {
        guard taskCount > 0 else { return 0 }
        return verticalPadding * 2
            + CGFloat(taskCount) * rowHeight
            + CGFloat(taskCount - 1) * rowSpacing
    }

    var body: some View {
        WorkstateGlassContainer {
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(tasks) { task in
                    legendItem(for: task)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, Self.verticalPadding)
            .frame(
                width: Self.width,
                height: Self.height(for: tasks.count),
                alignment: .topLeading
            )
            .workstateGlassSurface(cornerRadius: WorkstateTheme.cornerRadius)
        }
        .frame(width: Self.width, height: Self.height(for: tasks.count))
    }

    private func legendItem(for task: TaskRecord) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(colors[task.id] ?? task.accent.color)
                .frame(width: 7, height: 7)

            Text(task.title)
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.primaryLabel)

            if task.id == primaryTaskID {
                Spacer(minLength: 8)
                Text("主线")
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        .help(task.title)
    }
}

enum TimelineTaskPalette {
    private struct Token {
        let id: String
        let color: Color
    }

    private static let tokens: [Token] = [
        Token(id: ProjectAccent.blue.rawValue, color: ProjectAccent.blue.color),
        Token(id: ProjectAccent.green.rawValue, color: ProjectAccent.green.color),
        Token(id: ProjectAccent.red.rawValue, color: ProjectAccent.red.color),
        Token(id: ProjectAccent.amber.rawValue, color: ProjectAccent.amber.color),
        Token(id: ProjectAccent.violet.rawValue, color: ProjectAccent.violet.color),
        Token(id: ProjectAccent.cyan.rawValue, color: ProjectAccent.cyan.color),
        Token(id: "yellow", color: SmartisanColorTokens.Theme.yellow.representative),
        Token(id: "orange", color: SmartisanColorTokens.Theme.orange.representative),
        Token(id: "rose", color: SmartisanColorTokens.Theme.sekichiku.representative),
        Token(id: "gold", color: SmartisanColorTokens.Theme.karekusa.representative),
        Token(id: "sage", color: SmartisanColorTokens.Theme.sabiseiji.representative),
        Token(id: "lavender", color: SmartisanColorTokens.Theme.hatobaMurasaki.representative),
        Token(id: "olive", color: SmartisanColorTokens.Theme.yanagisuTakecha.representative),
        Token(id: "warm-gray", color: SmartisanColorTokens.Theme.enshuNezumi.representative),
        Token(id: "brown", color: SmartisanColorTokens.Theme.ochikuri.representative),
        Token(id: "wine", color: SmartisanColorTokens.Theme.suoh.representative)
    ]

    static func colors(for project: ProjectRecord, primaryTaskID: String?) -> [String: Color] {
        guard !project.tasks.isEmpty else { return [:] }

        let mainlineTokenID = project.accent.rawValue
        var usedTokenIDs = Set([mainlineTokenID])
        var assigned: [String: Color] = [:]
        if let primaryTaskID {
            assigned[primaryTaskID] = project.accent.color
        }

        let branchTasks = project.tasks
            .filter { $0.id != primaryTaskID }
            .sorted {
                if $0.startedAt == $1.startedAt { return $0.id < $1.id }
                return $0.startedAt < $1.startedAt
            }

        for task in branchTasks {
            let preferredID = task.accent.rawValue
            let token = tokens.first {
                $0.id == preferredID && !usedTokenIDs.contains($0.id)
            } ?? tokens.first {
                !usedTokenIDs.contains($0.id)
            } ?? reusableToken(for: task.id, excluding: mainlineTokenID)

            assigned[task.id] = token.color
            usedTokenIDs.insert(token.id)
        }
        return assigned
    }

    private static func reusableToken(for taskID: String, excluding excludedID: String) -> Token {
        let available = tokens.filter { $0.id != excludedID }
        let index = taskID.utf8.reduce(0) { ($0 + Int($1)) % available.count }
        return available[index]
    }
}

private extension TaskStatus {
    var sortOrder: Int {
        switch self {
        case .active: 0
        case .waiting: 1
        case .parked: 2
        case .completed: 3
        case .abandoned: 4
        }
    }
}

private enum TimelineNodeLayout {
    static let hitSize: CGFloat = 28
    static let labelWidth: CGFloat = 460
    static let labelHeight: CGFloat = 56
    static let labelSpacing: CGFloat = 8
}
