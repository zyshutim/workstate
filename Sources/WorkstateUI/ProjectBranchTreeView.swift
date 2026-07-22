import SwiftUI
import WorkstateCore

struct ProjectBranchTreeView: View {
    let workspace: WorkspaceSnapshot
    let project: ProjectRecord
    let includesHistory: Bool
    let isContextExpanded: Bool
    let selectedEventID: String?
    let onSelectEvent: (String) -> Void
    let onSelectTaskEvent: (String) -> Void
    let onDismissEvent: () -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    private var layout: ProjectBranchTreeLayout {
        ProjectBranchTreeLayout(project: project, includesHistory: includesHistory)
    }

    private var taskColors: [String: Color] {
        TimelineTaskPalette.colors(
            for: project,
            primaryTaskID: layout.primaryTaskID
        )
    }

    var body: some View {
        Group {
            if snapshotRendering {
                branchContent
                    .frame(
                        width: WorkstateTheme.projectWidth,
                        height: isContextExpanded ? 244 : 480,
                        alignment: .topLeading
                    )
                    .clipped()
            } else {
                ScrollView([.horizontal, .vertical]) {
                    branchContent
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private var branchContent: some View {
        ZStack(alignment: .topLeading) {
            BranchTreeBackdrop(layout: layout)
            BranchTreePaths(layout: layout, taskColors: taskColors)

            ForEach(layout.rows) { row in
                BranchTreeRowLabel(
                    row: row,
                    color: taskColors[row.task.id] ?? row.task.accent.color,
                    isPrimary: row.task.id == layout.primaryTaskID
                )
                .position(x: ProjectBranchTreeLayout.labelWidth / 2, y: row.y)
            }

            ForEach(layout.nodes) { node in
                BranchTreeEventButton(
                    workspace: workspace,
                    project: project,
                    node: node,
                    color: taskColors[node.task.id] ?? node.task.accent.color,
                    isSelected: selectedEventID == node.event.id,
                    onSelect: { onSelectEvent(node.event.id) },
                    onSelectTaskEvent: onSelectTaskEvent,
                    onDismiss: onDismissEvent
                )
                .position(node.point)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
    }
}

private struct BranchTreeBackdrop: View {
    let layout: ProjectBranchTreeLayout

    var body: some View {
        Canvas { context, size in
            for row in layout.rows.dropLast() {
                var separator = Path()
                separator.move(to: CGPoint(x: 20, y: row.y + ProjectBranchTreeLayout.rowHeight / 2))
                separator.addLine(to: CGPoint(x: size.width - 20, y: row.y + ProjectBranchTreeLayout.rowHeight / 2))
                context.stroke(
                    separator,
                    with: .color(WorkstateTheme.separator.opacity(0.20)),
                    lineWidth: 0.5
                )
            }

            var labelSeparator = Path()
            labelSeparator.move(to: CGPoint(x: ProjectBranchTreeLayout.labelWidth, y: 16))
            labelSeparator.addLine(to: CGPoint(x: ProjectBranchTreeLayout.labelWidth, y: size.height - 16))
            context.stroke(
                labelSeparator,
                with: .color(WorkstateTheme.separator.opacity(0.32)),
                lineWidth: 0.5
            )
        }
        .allowsHitTesting(false)
    }
}

private struct BranchTreePaths: View {
    let layout: ProjectBranchTreeLayout
    let taskColors: [String: Color]

    var body: some View {
        Canvas { context, _ in
            for branch in layout.paths {
                guard let first = branch.points.first else { continue }
                let color = taskColors[branch.task.id] ?? branch.task.accent.color
                var path = Path()
                path.move(to: first)
                var previous = first
                for point in branch.points.dropFirst() {
                    appendSegment(from: previous, to: point, path: &path)
                    previous = point
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(lineOpacity(for: branch.task.status))),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func appendSegment(from start: CGPoint, to end: CGPoint, path: inout Path) {
        guard start.y != end.y else {
            path.addLine(to: end)
            return
        }
        let middleX = (start.x + end.x) / 2
        path.addCurve(
            to: end,
            control1: CGPoint(x: middleX, y: start.y),
            control2: CGPoint(x: middleX, y: end.y)
        )
    }

    private func lineOpacity(for status: TaskStatus) -> Double {
        switch status {
        case .active, .waiting: 0.90
        case .parked: 0.58
        case .completed: 0.50
        case .abandoned: 0.34
        }
    }
}

private struct BranchTreeRowLabel: View {
    let row: ProjectBranchTreeRow
    let color: Color
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(row.task.status == .active || row.task.status == .waiting ? color : Color.clear)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(color.opacity(0.90), lineWidth: 1)
                }
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.task.title)
                    .font(WorkstateTheme.captionEmphasisFont)
                    .foregroundStyle(WorkstateTheme.primaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(row.task.status.displayName)
                        .font(WorkstateTheme.microFont)
                        .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    if isPrimary {
                        Text("主线")
                            .font(WorkstateTheme.microFont)
                            .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    }
                }
            }
        }
        .padding(.leading, min(CGFloat(row.depth) * 10, 30))
        .frame(width: ProjectBranchTreeLayout.labelWidth - 20, height: 54, alignment: .leading)
        .help(row.task.title)
    }
}

private struct BranchTreeEventButton: View {
    let workspace: WorkspaceSnapshot
    let project: ProjectRecord
    let node: ProjectBranchTreeNode
    let color: Color
    let isSelected: Bool
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
                        task: node.task,
                        event: node.event,
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
            ZStack {
                if isSelected {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: 24, height: 24)
                }
                Circle()
                    .fill(nodeFill)
                    .frame(width: isHovered ? 12 : 10, height: isHovered ? 12 : 10)
                    .overlay {
                        Circle()
                            .stroke(color, lineWidth: 1)
                    }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            guard !isSelected else { return }
            isHovered = hovering
        }
        .help("\(node.event.title)\n\(WorkstateDateText.compact(node.event.timestamp))")
        .accessibilityLabel(node.event.title)
    }

    private var nodeFill: Color {
        if isSelected || (node.isLatestInTask && (node.task.status == .active || node.task.status == .waiting)) {
            return color
        }
        return WorkstateTheme.contentBackground
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
