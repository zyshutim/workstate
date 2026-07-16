import SwiftUI
import WorkstateCore

struct ProjectWorkspaceView: View {
    let project: ProjectRecord
    @ObservedObject var model: WorkstateViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            workspaceBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ProjectContextSection(
                    project: project,
                    isExpanded: model.isContextExpanded,
                    onToggle: model.toggleContext
                )

                ProjectTimelineSection(
                    project: project,
                    isContextExpanded: model.isContextExpanded,
                    selectedTaskID: model.selectedTaskID,
                    selectedProjectEventID: model.selectedTaskID == nil ? model.selectedEventID : nil,
                    onSelectTask: model.selectTask,
                    onSelectProjectEvent: model.selectProjectEvent
                )
            }

            utilityHeader
                .zIndex(30)

            if let event = model.selectedEvent {
                EventDetailPopover(
                    workspace: model.workspace,
                    project: project,
                    task: model.selectedTask,
                    event: event,
                    onSelectTaskEvent: model.selectTaskEvent,
                    onClose: model.closeEvent
                )
                .frame(width: WorkstateTheme.eventPopoverWidth, height: WorkstateTheme.eventPopoverHeight)
                .padding(.top, 58)
                .padding(.trailing, 12)
                .transition(
                    .scale(scale: 0.985, anchor: .topTrailing)
                        .combined(with: .opacity)
                )
                .zIndex(40)
            }
        }
        .animation(
            reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.24),
            value: model.selectedEventID
        )
    }

    private var utilityHeader: some View {
        WorkstateGlassContainer {
            HStack(spacing: 10) {
                WorkspaceToolbarButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "返回项目图谱",
                    action: model.leaveProject
                )
                .frame(width: 38, height: 38)
                .workstateGlassSurface(cornerRadius: 14, interactive: true)

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    Circle()
                        .fill(project.status.color(accent: project.accent))
                        .frame(width: 6, height: 6)
                    Text(project.status.displayName)
                        .font(WorkstateTheme.captionEmphasisFont)
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

    private var workspaceBackground: Color {
        WorkstateTheme.workspaceBackground
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
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    ProjectFacts(project: project)
                        .padding(.top, 2)
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
            ContextBlock(title: "对象与关系", values: project.context.objectModel)
            ContextBlock(title: "范围", values: project.context.inScope)
            ContextBlock(
                title: "禁止方向",
                values: project.context.forbiddenDirections.isEmpty
                    ? project.context.outOfScope
                    : project.context.forbiddenDirections
            )
            ContextBlock(title: "开放问题", values: project.context.openIssues)

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.64))
                .frame(height: 0.5)

            ContextUnderstandingSection(statements: project.context.understanding)

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.64))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 12) {
                Text("理解更新日志")
                    .font(WorkstateTheme.captionEmphasisFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                ForEach(project.context.revisions.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)) { revision in
                    ContextRevisionRow(revision: revision)
                }
            }
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

private struct ProjectFacts: View {
    let project: ProjectRecord

    var body: some View {
        HStack(spacing: 15) {
            Label("\(project.tasks.count) 工作线", systemImage: "arrow.triangle.branch")
            Label("\(project.activeTasks.count) 活跃", systemImage: "arrow.triangle.branch")
            Label("\(project.context.revisions.count) 理解更新", systemImage: "text.book.closed")
        }
        .font(WorkstateTheme.captionFont.monospacedDigit())
        .foregroundStyle(WorkstateTheme.secondaryLabel)
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
    let project: ProjectRecord
    let isContextExpanded: Bool
    let selectedTaskID: String?
    let selectedProjectEventID: String?
    let onSelectTask: (String) -> Void
    let onSelectProjectEvent: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.72))
                .frame(height: 0.5)

            HStack(spacing: 10) {
                Text("工作历史")
                    .font(WorkstateTheme.sectionTitleFont)
                Text("最新在上")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)

                Spacer(minLength: 8)

                if let task = project.activeTasks.first {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(task.accent.color)
                            .frame(width: 6, height: 6)
                        Text(task.title)
                            .font(WorkstateTheme.captionEmphasisFont)
                            .lineLimit(1)
                    }
                    if project.activeTasks.count > 1 {
                        Text("+\(project.activeTasks.count - 1)")
                            .font(WorkstateTheme.captionFont.monospacedDigit())
                            .foregroundStyle(WorkstateTheme.secondaryLabel)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 46)

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.54))
                .frame(height: 0.5)

            ProjectGitTimeline(
                project: project,
                isContextExpanded: isContextExpanded,
                selectedTaskID: selectedTaskID,
                selectedProjectEventID: selectedProjectEventID,
                onSelectTask: onSelectTask,
                onSelectProjectEvent: onSelectProjectEvent
            )
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .background(timelineBackground)
    }

    private var timelineBackground: Color {
        WorkstateTheme.timelineBackground
    }
}

private struct ProjectGitTimeline: View {
    let project: ProjectRecord
    let isContextExpanded: Bool
    let selectedTaskID: String?
    let selectedProjectEventID: String?
    let onSelectTask: (String) -> Void
    let onSelectProjectEvent: (String) -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    private var layout: ProjectTimelineLayout {
        ProjectTimelineLayout(project: project)
    }

    var body: some View {
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
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private var timelineContent: some View {
        ZStack(alignment: .topLeading) {
            TimelineBackdrop(layout: layout)
            TimelineTaskBranches(
                layout: layout,
                selectedTaskID: selectedTaskID
            )

            ForEach(layout.nodes) { node in
                if let point = layout.points[node.id] {
                    let labelOnLeading = point.x > layout.contentSize.width * 0.56
                    switch node.content {
                    case .projectEvent(let event):
                        TimelineProjectEventButton(
                            project: project,
                            event: event,
                            isSelected: selectedProjectEventID == event.id,
                            labelOnLeading: labelOnLeading,
                            action: { onSelectProjectEvent(event.id) }
                        )
                        .position(
                            x: point.x + (labelOnLeading ? -TimelineNodeLayout.centerOffset : TimelineNodeLayout.centerOffset),
                            y: point.y
                        )
                    case .task(let task):
                        TimelineTaskButton(
                            task: task,
                            timestamp: node.timestamp,
                            isSelected: selectedTaskID == task.id,
                            labelOnLeading: labelOnLeading,
                            action: { onSelectTask(task.id) }
                        )
                        .position(
                            x: point.x + (labelOnLeading ? -TimelineNodeLayout.centerOffset : TimelineNodeLayout.centerOffset),
                            y: point.y
                        )
                    }
                }
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
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
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )

            for y in layout.rowYs {
                var row = Path()
                row.move(to: CGPoint(x: 20, y: y + 31))
                row.addLine(to: CGPoint(x: size.width - 20, y: y + 31))
                context.stroke(row, with: .color(WorkstateTheme.separator.opacity(0.20)), lineWidth: 0.5)
            }

            let cap = CGRect(x: ProjectTimelineLayout.mainlineX - 3, y: 25, width: 6, height: 6)
            context.fill(Path(ellipseIn: cap), with: .color(WorkstateTheme.secondaryLabel.opacity(0.58)))
        }
        .allowsHitTesting(false)
    }
}

private struct TimelineTaskBranches: View {
    let layout: ProjectTimelineLayout
    let selectedTaskID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, _ in
            for branch in layout.branches {
                let color = branch.task.accent.color
                let isSelected = branch.task.id == selectedTaskID
                let path = branchPath(branch)

                if isSelected {
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.14)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                }

                context.stroke(
                    path,
                    with: .color(color.opacity(isSelected ? 0.96 : 0.72)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )

                let startCap = CGRect(
                    x: branch.startPoint.x - 2.5,
                    y: branch.startPoint.y - 2.5,
                    width: 5,
                    height: 5
                )
                context.fill(Path(ellipseIn: startCap), with: .color(color.opacity(0.72)))

                if let mergePoint = branch.mergePoint {
                    let mergeCap = CGRect(
                        x: mergePoint.x - 2.5,
                        y: mergePoint.y - 2.5,
                        width: 5,
                        height: 5
                    )
                    context.fill(Path(ellipseIn: mergeCap), with: .color(color.opacity(0.72)))
                }
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedTaskID)
    }

    private func branchPath(_ branch: ProjectTimelineBranch) -> Path {
        var path = Path()
        path.move(to: branch.startPoint)
        appendCurve(from: branch.startPoint, to: branch.taskPoint, path: &path)
        if let mergePoint = branch.mergePoint {
            appendCurve(from: branch.taskPoint, to: mergePoint, path: &path)
        }
        return path
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

private struct TimelineProjectEventButton: View {
    let project: ProjectRecord
    let event: ProjectEvent
    let isSelected: Bool
    let labelOnLeading: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: TimelineNodeLayout.spacing) {
                if labelOnLeading {
                    eventInfo(alignment: .trailing)
                    eventNode
                } else {
                    eventNode
                    eventInfo(alignment: .leading)
                }
            }
            .frame(
                width: TimelineNodeLayout.width,
                height: TimelineNodeLayout.height,
                alignment: labelOnLeading ? .trailing : .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !reduceMotion ? 1.012 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(event.summary)
    }

    private var eventNode: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(eventColor.opacity(0.14))
                    .frame(width: 26, height: 26)
            }
            Circle()
                .fill(isSelected ? eventColor : WorkstateTheme.contentBackground)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(eventColor, lineWidth: 1.3)
                }
            Image(systemName: event.kind.symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(isSelected ? WorkstateTheme.onAccent : eventColor)
        }
        .frame(width: TimelineNodeLayout.dotSize, height: TimelineNodeLayout.dotSize)
    }

    private func eventInfo(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(event.title)
                .font(isSelected ? WorkstateTheme.headlineFont : WorkstateTheme.secondaryFont.weight(.medium))
                .foregroundStyle(isSelected ? eventColor : WorkstateTheme.primaryLabel)
                .lineLimit(1)

            HStack(spacing: 5) {
                Text(event.loopStage.displayName)
                Text("·")
                Text(WorkstateDateText.compact(event.timestamp))
                    .monospacedDigit()
            }
            .font(WorkstateTheme.microFont)
            .foregroundStyle(WorkstateTheme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: TimelineNodeLayout.infoWidth, alignment: alignment == .leading ? .leading : .trailing)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(eventColor.opacity(isSelected ? 0.09 : isHovered ? 0.05 : 0))
        }
    }

    private var eventColor: Color {
        project.accent.color
    }
}

private struct TimelineTaskButton: View {
    let task: TaskRecord
    let timestamp: Date
    let isSelected: Bool
    let labelOnLeading: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: TimelineNodeLayout.spacing) {
                if labelOnLeading {
                    taskInfo(alignment: .trailing)
                    taskNode
                } else {
                    taskNode
                    taskInfo(alignment: .leading)
                }
            }
            .frame(
                width: TimelineNodeLayout.width,
                height: TimelineNodeLayout.height,
                alignment: labelOnLeading ? .trailing : .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !reduceMotion ? 1.012 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(task.objective)
    }

    private var taskNode: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(branchColor.opacity(0.14))
                    .frame(width: 28, height: 28)
            }
            Circle()
                .fill(task.status == .active ? branchColor : WorkstateTheme.contentBackground)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(branchColor, lineWidth: 1.4)
                }
            Image(systemName: task.status.symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(task.status == .active ? WorkstateTheme.onAccent : statusColor)
        }
        .frame(width: TimelineNodeLayout.dotSize, height: TimelineNodeLayout.dotSize)
    }

    private func taskInfo(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(task.title)
                .font(isSelected ? WorkstateTheme.headlineFont : WorkstateTheme.secondaryFont.weight(.medium))
                .foregroundStyle(isSelected ? branchColor : WorkstateTheme.primaryLabel)
                .lineLimit(1)

            Text("\(task.currentStage.displayName) · \(task.status.displayName) · \(WorkstateDateText.compact(timestamp))")
                .font(WorkstateTheme.microFont.monospacedDigit())
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: TimelineNodeLayout.infoWidth, alignment: alignment == .leading ? .leading : .trailing)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(branchColor.opacity(isSelected ? 0.09 : isHovered ? 0.05 : 0))
        }
    }

    private var branchColor: Color {
        task.accent.color
    }

    private var statusColor: Color {
        task.status.color(accent: task.accent)
    }
}

private enum TimelineNodeLayout {
    static let width = WorkstateTheme.timelineNodeWidth
    static let height: CGFloat = 54
    static let dotSize: CGFloat = 26
    static let infoWidth: CGFloat = 192
    static let spacing: CGFloat = 8
    static let centerOffset = (width - dotSize) / 2
}
