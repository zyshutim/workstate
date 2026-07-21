import SwiftUI
import WorkstateCore

struct ProjectGraphView: View {
    @ObservedObject var model: WorkstateViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workstateSnapshotFocusedProjectID) private var snapshotFocusedProjectID
    @State private var hoveredProjectID: String?
    @State private var draggedProjectID: String?
    @State private var transientPositions: [String: GraphPosition] = [:]
    @State private var dragOrigins: [String: GraphPosition] = [:]
    @State private var cameraOffset = CGSize.zero
    @State private var panOrigin: CGSize?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOriginScale: CGFloat?
    @State private var zoomOriginOffset: CGSize?
    @State private var hasCenteredCamera = false

    var body: some View {
        GeometryReader { proxy in
            let restingScale = hasCenteredCamera ? zoomScale : fitScale(in: proxy.size)
            let restingOffset = hasCenteredCamera
                ? cameraOffset
                : centeredOffset(in: proxy.size, scale: restingScale)
            let screenPositions = projectScreenPositions(offset: restingOffset, scale: restingScale)
            let focusedProjectID = draggedProjectID ?? hoveredProjectID ?? snapshotFocusedProjectID
            let focusedProject = focusedProjectID.flatMap(model.workspace.project(id:))
            let connectedProjectIDs = connectedProjectIDs(to: focusedProjectID)

            ZStack(alignment: .topLeading) {
                ProjectGraphField(cameraOffset: restingOffset, zoomScale: restingScale)
                    .contentShape(Rectangle())
                    .gesture(canvasPanGesture(in: proxy.size))

                ProjectRelationLayer(
                    workspace: model.workspace,
                    screenPositions: screenPositions,
                    focusedProjectID: focusedProjectID,
                    zoomScale: restingScale,
                    focusedColor: focusedProject.map {
                        $0.status.color(accent: $0.accent)
                    }
                )

                ForEach(model.workspace.projects) { project in
                    if let point = screenPositions[project.id] {
                        let labelOnLeading = point.x > proxy.size.width * 0.56
                        let participatesInFocus = focusedProjectID == nil
                            || focusedProjectID == project.id
                            || connectedProjectIDs.contains(project.id)

                        ProjectGraphNode(
                            project: project,
                            isHovered: hoveredProjectID == project.id
                                || (hoveredProjectID == nil && snapshotFocusedProjectID == project.id),
                            isDragging: draggedProjectID == project.id,
                            isFocusActive: focusedProjectID != nil,
                            participatesInFocus: participatesInFocus,
                            labelOnLeading: labelOnLeading,
                            summaryAbove: point.y > proxy.size.height * 0.72,
                            onSelect: { model.selectProject(project.id) },
                            onHover: { hovering in
                                hoveredProjectID = hovering ? project.id : nil
                            },
                            onDragChanged: { translation in
                                updateDrag(
                                    project: project,
                                    translation: translation,
                                    scale: restingScale
                                )
                            },
                            onDragEnded: { translation in
                                finishDrag(
                                    project: project,
                                    translation: translation,
                                    scale: restingScale
                                )
                            }
                        )
                        .scaleEffect(restingScale)
                        .position(
                            x: point.x + (
                                labelOnLeading
                                    ? -ProjectNodeLayout.centerOffset * restingScale
                                    : ProjectNodeLayout.centerOffset * restingScale
                            ),
                            y: point.y
                        )
                        .zIndex(draggedProjectID == project.id ? 30 : hoveredProjectID == project.id ? 20 : participatesInFocus ? 2 : 1)
                    }
                }

                graphTopBar(in: proxy.size, scale: restingScale)
                    .zIndex(100)

                graphFooter
                    .zIndex(100)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .simultaneousGesture(canvasZoomGesture(in: proxy.size))
            .onAppear {
                guard !hasCenteredCamera else { return }
                let initialScale = fitScale(in: proxy.size)
                zoomScale = initialScale
                cameraOffset = centeredOffset(in: proxy.size, scale: initialScale)
                hasCenteredCamera = true
            }
        }
        .background(WorkstateTheme.windowBackground)
    }

    private func graphTopBar(in size: CGSize, scale: CGFloat) -> some View {
        WorkstateGlassContainer {
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 13, weight: .semibold))
                    Text("项目图谱")
                        .font(WorkstateTheme.headlineFont)
                    Text("\(model.workspace.projects.count)")
                        .font(WorkstateTheme.microFont.monospacedDigit())
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }
                .padding(.leading, 13)
                .padding(.trailing, 11)
                .frame(height: 38)
                .workstateGlassSurface(cornerRadius: 14)

                Spacer(minLength: 12)

                HStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        GraphToolbarButton(
                            systemName: "clock.arrow.circlepath",
                            accessibilityLabel: "打开工作摘要",
                            action: model.presentDailyBrief
                        )
                        if model.hasUnreadDailyBrief {
                            Circle()
                                .fill(WorkstateTheme.activeState)
                                .frame(width: 6, height: 6)
                                .offset(x: -3, y: 3)
                                .accessibilityHidden(true)
                        }
                    }

                    DaemonStatusIndicator(daemon: model.daemonStatus)

                    Text(WorkstateDateText.relative(model.workspace.updatedAt))
                        .font(WorkstateTheme.captionFont.monospacedDigit())
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                        .padding(.horizontal, 7)

                    GraphToolbarButton(
                        systemName: "minus.magnifyingglass",
                        accessibilityLabel: "缩小",
                        isEnabled: scale > GraphCamera.minimumScale,
                        action: { zoom(by: -GraphCamera.step, in: size) }
                    )
                    Text("\(Int((scale * 100).rounded()))%")
                        .font(WorkstateTheme.microFont.monospacedDigit())
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                        .frame(width: 34)
                        .accessibilityLabel("当前缩放比例 \(Int((scale * 100).rounded()))%")
                    GraphToolbarButton(
                        systemName: "plus.magnifyingglass",
                        accessibilityLabel: "放大",
                        isEnabled: scale < GraphCamera.maximumScale,
                        action: { zoom(by: GraphCamera.step, in: size) }
                    )
                    GraphToolbarButton(
                        systemName: "scope",
                        accessibilityLabel: "适配全部项目",
                        action: { fitCamera(in: size) }
                    )
                    GraphToolbarButton(
                        systemName: "arrow.clockwise",
                        accessibilityLabel: "刷新",
                        action: { model.reload(force: true) }
                    )
                }
                .padding(.horizontal, 5)
                .frame(height: 38)
                .workstateGlassSurface(cornerRadius: 14, interactive: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var graphFooter: some View {
        WorkstateGlassContainer {
            HStack(spacing: 10) {
                HStack(spacing: 13) {
                    Label("\(model.workspace.projects.count)", systemImage: "circle.grid.2x2")
                    Label("\(model.workspace.relations.count)", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .font(WorkstateTheme.captionFont.monospacedDigit())
                .foregroundStyle(WorkstateTheme.secondaryLabel)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .workstateGlassSurface(cornerRadius: 13)

                Spacer(minLength: 8)

                HStack(spacing: 11) {
                    StatusLegend(status: .active)
                    StatusLegend(status: .waiting)
                    StatusLegend(status: .parked)
                    StatusLegend(status: .completed)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .workstateGlassSurface(cornerRadius: 13)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func canvasPanGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if panOrigin == nil {
                    let scale = currentScale(in: size)
                    panOrigin = currentOffset(in: size, scale: scale)
                    zoomScale = scale
                }
                guard let panOrigin else { return }
                cameraOffset = CGSize(
                    width: panOrigin.width + value.translation.width,
                    height: panOrigin.height + value.translation.height
                )
                hasCenteredCamera = true
            }
            .onEnded { value in
                let scale = currentScale(in: size)
                let origin = panOrigin ?? currentOffset(in: size, scale: scale)
                let settledOffset = CGSize(
                    width: origin.width + value.translation.width,
                    height: origin.height + value.translation.height
                )
                cameraOffset = settledOffset
                panOrigin = nil

                guard !reduceMotion else { return }
                let momentum = CGSize(
                    width: clampedMomentum(value.predictedEndTranslation.width - value.translation.width),
                    height: clampedMomentum(value.predictedEndTranslation.height - value.translation.height)
                )
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.30)) {
                    cameraOffset = CGSize(
                        width: settledOffset.width + momentum.width,
                        height: settledOffset.height + momentum.height
                    )
                }
            }
    }

    private func clampedMomentum(_ value: CGFloat) -> CGFloat {
        min(max(value * 0.32, -120), 120)
    }

    private func canvasZoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.002)
            .onChanged { value in
                if zoomOriginScale == nil {
                    let scale = currentScale(in: size)
                    zoomOriginScale = scale
                    zoomOriginOffset = currentOffset(in: size, scale: scale)
                }
                guard let originScale = zoomOriginScale,
                      let originOffset = zoomOriginOffset else { return }

                let targetScale = clampedScale(originScale * value.magnification)
                let anchor = CGPoint(
                    x: value.startAnchor.x * size.width,
                    y: value.startAnchor.y * size.height
                )
                zoomScale = targetScale
                cameraOffset = offsetPreserving(
                    anchor: anchor,
                    oldScale: originScale,
                    newScale: targetScale,
                    oldOffset: originOffset
                )
                hasCenteredCamera = true
            }
            .onEnded { _ in
                zoomOriginScale = nil
                zoomOriginOffset = nil
            }
    }

    private func zoom(by delta: CGFloat, in size: CGSize) {
        let oldScale = currentScale(in: size)
        let oldOffset = currentOffset(in: size, scale: oldScale)
        let targetScale = clampedScale(oldScale + delta)
        let anchor = CGPoint(x: size.width / 2, y: size.height / 2)
        let targetOffset = offsetPreserving(
            anchor: anchor,
            oldScale: oldScale,
            newScale: targetScale,
            oldOffset: oldOffset
        )
        setCamera(scale: targetScale, offset: targetOffset)
    }

    private func fitCamera(in size: CGSize) {
        let targetScale = fitScale(in: size)
        let targetOffset = centeredOffset(in: size, scale: targetScale)
        setCamera(scale: targetScale, offset: targetOffset)
    }

    private func setCamera(scale: CGFloat, offset: CGSize) {
        if reduceMotion {
            zoomScale = scale
            cameraOffset = offset
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.34)) {
                zoomScale = scale
                cameraOffset = offset
            }
        }
        hasCenteredCamera = true
    }

    private func currentScale(in size: CGSize) -> CGFloat {
        hasCenteredCamera ? zoomScale : fitScale(in: size)
    }

    private func currentOffset(in size: CGSize, scale: CGFloat) -> CGSize {
        hasCenteredCamera ? cameraOffset : centeredOffset(in: size, scale: scale)
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, GraphCamera.minimumScale), GraphCamera.maximumScale)
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        let positions = model.workspace.projects.map { project in
            transientPositions[project.id] ?? project.graphPosition
        }
        guard let minX = positions.map(\.x).min(),
              let maxX = positions.map(\.x).max(),
              let minY = positions.map(\.y).min(),
              let maxY = positions.map(\.y).max() else {
            return 1
        }

        let contentWidth = max(maxX - minX + ProjectNodeLayout.width + 24, 1)
        let contentHeight = max(maxY - minY + ProjectNodeLayout.height + 16, 1)
        let availableWidth = max(size.width - GraphCamera.horizontalInset * 2, 1)
        let availableHeight = max(
            size.height - GraphCamera.topInset - GraphCamera.bottomInset,
            1
        )
        let fittedScale = min(
            1,
            min(availableWidth / contentWidth, availableHeight / contentHeight)
        )
        return clampedScale(fittedScale)
    }

    private func centeredOffset(in size: CGSize, scale: CGFloat) -> CGSize {
        let positions = model.workspace.projects.map { project in
            transientPositions[project.id] ?? project.graphPosition
        }
        guard let minX = positions.map(\.x).min(),
              let maxX = positions.map(\.x).max(),
              let minY = positions.map(\.y).min(),
              let maxY = positions.map(\.y).max() else {
            return .zero
        }
        return CGSize(
            width: size.width / 2 - (minX + maxX) / 2 * scale,
            height: size.height / 2 - (minY + maxY) / 2 * scale
        )
    }

    private func offsetPreserving(
        anchor: CGPoint,
        oldScale: CGFloat,
        newScale: CGFloat,
        oldOffset: CGSize
    ) -> CGSize {
        let worldX = (anchor.x - oldOffset.width) / oldScale
        let worldY = (anchor.y - oldOffset.height) / oldScale
        return CGSize(
            width: anchor.x - worldX * newScale,
            height: anchor.y - worldY * newScale
        )
    }

    private func projectScreenPositions(offset: CGSize, scale: CGFloat) -> [String: CGPoint] {
        Dictionary(uniqueKeysWithValues: model.workspace.projects.map { project in
            let position = transientPositions[project.id] ?? project.graphPosition
            return (
                project.id,
                CGPoint(
                    x: position.x * scale + offset.width,
                    y: position.y * scale + offset.height
                )
            )
        })
    }

    private func connectedProjectIDs(to projectID: String?) -> Set<String> {
        guard let projectID else { return [] }
        return Set(model.workspace.relations.compactMap { relation in
            if relation.fromProjectID == projectID {
                return relation.toProjectID
            }
            if relation.toProjectID == projectID {
                return relation.fromProjectID
            }
            return nil
        })
    }

    private func updateDrag(project: ProjectRecord, translation: CGSize, scale: CGFloat) {
        if dragOrigins[project.id] == nil {
            dragOrigins[project.id] = transientPositions[project.id] ?? project.graphPosition
        }
        guard let origin = dragOrigins[project.id] else { return }
        transientPositions[project.id] = GraphPosition(
            x: origin.x + translation.width / scale,
            y: origin.y + translation.height / scale
        )
        draggedProjectID = project.id
    }

    private func finishDrag(project: ProjectRecord, translation: CGSize, scale: CGFloat) {
        let origin = dragOrigins[project.id] ?? project.graphPosition
        let finalPosition = GraphPosition(
            x: origin.x + translation.width / scale,
            y: origin.y + translation.height / scale
        )
        model.moveProject(project.id, to: finalPosition)
        transientPositions.removeValue(forKey: project.id)
        dragOrigins.removeValue(forKey: project.id)
        draggedProjectID = nil
    }
}

private struct DaemonStatusIndicator: View {
    let daemon: DaemonSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay {
                    if daemon.activity == .analyzing || daemon.activity == .scanning {
                        Circle()
                            .stroke(color.opacity(0.35), lineWidth: 3)
                            .frame(width: 13, height: 13)
                    }
                }
        }
            .frame(minWidth: 22, minHeight: 28)
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var color: Color {
        switch daemon.activity {
        case .idle: WorkstateTheme.success
        case .scanning, .analyzing: WorkstateTheme.activeState
        case .paused, .stopped: WorkstateTheme.tertiaryLabel
        case .failed: WorkstateTheme.danger
        }
    }

    private var helpText: String {
        let state: String
        switch daemon.activity {
        case .stopped: state = "同步未运行"
        case .idle: state = "同步监听中"
        case .scanning: state = "正在扫描会话"
        case .analyzing: state = "正在分析项目变化"
        case .paused: state = "同步已暂停"
        case .failed: state = "同步发生错误"
        }
        return daemon.detail.isEmpty ? state : "\(state) · \(daemon.detail)"
    }
}

private struct ProjectGraphField: View {
    let cameraOffset: CGSize
    let zoomScale: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fieldColor)

            GraphDepthField(offset: cameraOffset, zoomScale: zoomScale)

            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            WorkstateTheme.shadow.opacity(colorScheme == .dark ? 0.13 : 0.045)
                        ],
                        center: .center,
                        startRadius: 190,
                        endRadius: 520
                    )
                )
                .allowsHitTesting(false)
        }
    }

    private var fieldColor: Color {
        WorkstateTheme.graphBackground
    }
}

private struct GraphDepthField: View {
    let offset: CGSize
    let zoomScale: CGFloat

    var body: some View {
        Canvas { context, size in
            drawLayer(
                context: &context,
                size: size,
                count: 48,
                seed: 17,
                parallax: 0.10,
                radius: 0.65,
                opacity: 0.17
            )
            drawLayer(
                context: &context,
                size: size,
                count: 23,
                seed: 43,
                parallax: 0.22,
                radius: 1.05,
                opacity: 0.10
            )
        }
        .allowsHitTesting(false)
    }

    private func drawLayer(
        context: inout GraphicsContext,
        size: CGSize,
        count: Int,
        seed: Int,
        parallax: CGFloat,
        radius: CGFloat,
        opacity: Double
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let color = WorkstateTheme.secondaryLabel.opacity(opacity)
        let scaledRadius = radius * min(max(zoomScale, 0.78), 1.18)

        for index in 0..<count {
            let rawX = CGFloat((index * 83 + seed * 31) % 997) / 997 * size.width
            let rawY = CGFloat((index * 149 + seed * 47) % 991) / 991 * size.height
            let x = wrapped(rawX + offset.width * parallax, upperBound: size.width)
            let y = wrapped(rawY + offset.height * parallax, upperBound: size.height)
            let rect = CGRect(
                x: x - scaledRadius,
                y: y - scaledRadius,
                width: scaledRadius * 2,
                height: scaledRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func wrapped(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: upperBound)
        return remainder < 0 ? remainder + upperBound : remainder
    }
}

private struct ProjectRelationLayer: View {
    let workspace: WorkspaceSnapshot
    let screenPositions: [String: CGPoint]
    let focusedProjectID: String?
    let zoomScale: CGFloat
    let focusedColor: Color?

    var body: some View {
        Canvas { context, _ in
            for relation in workspace.relations {
                guard let rawStart = screenPositions[relation.fromProjectID],
                      let rawEnd = screenPositions[relation.toProjectID] else { continue }

                let isFocused = focusedProjectID.map {
                    relation.fromProjectID == $0 || relation.toProjectID == $0
                } ?? false
                let isSubdued = focusedProjectID != nil && !isFocused
                let relationColor = isFocused ? (focusedColor ?? WorkstateTheme.primaryLabel) : WorkstateTheme.relation
                let endpoints = insetEndpoints(
                    start: rawStart,
                    end: rawEnd,
                    inset: ProjectNodeLayout.orbSize * 0.42 * zoomScale
                )
                let curve = relationCurve(start: endpoints.start, end: endpoints.end)

                if isFocused {
                    context.stroke(
                        curve.path,
                        with: .color(relationColor.opacity(0.17)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                }

                context.stroke(
                    curve.path,
                    with: .color(relationColor.opacity(isSubdued ? 0.10 : isFocused ? 0.88 : 0.48)),
                    style: StrokeStyle(
                        lineWidth: isFocused ? 1.8 : relation.status == .confirmed ? 1.25 : 1,
                        lineCap: .round,
                        dash: relation.status == .inferred ? [5, 5] : []
                    )
                )

                drawArrow(
                    context: &context,
                    point: endpoints.end,
                    tangentFrom: curve.control2,
                    color: relationColor.opacity(isSubdued ? 0.08 : isFocused ? 0.78 : 0.40)
                )

                guard !isSubdued else { continue }
                context.draw(
                    Text(relation.label)
                        .font(WorkstateTheme.microFont.weight(isFocused ? .semibold : .medium))
                        .foregroundStyle(
                            isFocused
                                ? relationColor.opacity(0.92)
                                : WorkstateTheme.secondaryLabel.opacity(0.72)
                        ),
                    at: CGPoint(x: curve.midpoint.x, y: curve.midpoint.y - 12),
                    anchor: .center
                )
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.16), value: focusedProjectID)
    }

    private func insetEndpoints(start: CGPoint, end: CGPoint, inset: CGFloat) -> (start: CGPoint, end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let unitX = dx / length
        let unitY = dy / length
        return (
            CGPoint(x: start.x + unitX * inset, y: start.y + unitY * inset),
            CGPoint(x: end.x - unitX * inset, y: end.y - unitY * inset)
        )
    }

    private func relationCurve(start: CGPoint, end: CGPoint) -> (path: Path, control2: CGPoint, midpoint: CGPoint) {
        let horizontalDistance = end.x - start.x
        let controlOffset = max(44, abs(horizontalDistance) * 0.34)
        let direction: CGFloat = horizontalDistance >= 0 ? 1 : -1
        let control1 = CGPoint(x: start.x + controlOffset * direction, y: start.y)
        let control2 = CGPoint(x: end.x - controlOffset * direction, y: end.y)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return (
            path,
            control2,
            cubicPoint(start: start, control1: control1, control2: control2, end: end, t: 0.5)
        )
    }

    private func cubicPoint(
        start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        end: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let inverse = 1 - t
        let x = inverse * inverse * inverse * start.x
            + 3 * inverse * inverse * t * control1.x
            + 3 * inverse * t * t * control2.x
            + t * t * t * end.x
        let y = inverse * inverse * inverse * start.y
            + 3 * inverse * inverse * t * control1.y
            + 3 * inverse * t * t * control2.y
            + t * t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private func drawArrow(
        context: inout GraphicsContext,
        point: CGPoint,
        tangentFrom: CGPoint,
        color: Color
    ) {
        let angle = atan2(point.y - tangentFrom.y, point.x - tangentFrom.x)
        let length: CGFloat = 5
        let spread: CGFloat = 0.58
        let first = CGPoint(
            x: point.x - cos(angle - spread) * length,
            y: point.y - sin(angle - spread) * length
        )
        let second = CGPoint(
            x: point.x - cos(angle + spread) * length,
            y: point.y - sin(angle + spread) * length
        )
        var arrow = Path()
        arrow.move(to: first)
        arrow.addLine(to: point)
        arrow.addLine(to: second)
        context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }
}

private struct ProjectGraphNode: View {
    let project: ProjectRecord
    let isHovered: Bool
    let isDragging: Bool
    let isFocusActive: Bool
    let participatesInFocus: Bool
    let labelOnLeading: Bool
    let summaryAbove: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ProjectNodeLayout.spacing) {
                if labelOnLeading {
                    info(alignment: .trailing)
                    orb
                } else {
                    orb
                    info(alignment: .leading)
                }
            }
            .frame(
                width: ProjectNodeLayout.width,
                height: ProjectNodeLayout.height,
                alignment: labelOnLeading ? .trailing : .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: labelOnLeading ? .topLeading : .topTrailing) {
            if isHovered && !isDragging {
                ProjectHoverSummary(project: project)
                    .offset(y: summaryAbove ? -94 : 69)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: summaryAbove ? .bottom : .top)))
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isDragging ? 1.045 : isHovered ? 1.018 : 1)
        .opacity(isFocusActive && !participatesInFocus ? 0.28 : isDragging ? 0.94 : 1)
        .animation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.16), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.16), value: participatesInFocus)
        .onHover(perform: onHover)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in onDragChanged(value.translation) }
                .onEnded { value in onDragEnded(value.translation) }
        )
        .help(project.context.currentSummary)
    }

    private var orb: some View {
        ProjectNodeOrb(
            color: project.status.color(accent: project.accent),
            identityGradient: project.accent.gradient,
            status: project.status,
            activityAge: ActivityAge(lastActivityAt: project.lastActivityAt),
            isHovered: isHovered,
            isDragging: isDragging
        )
        .frame(width: ProjectNodeLayout.orbSize, height: ProjectNodeLayout.orbSize)
    }

    private func info(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(project.name)
                .font(WorkstateTheme.headlineFont)
                .foregroundStyle(WorkstateTheme.primaryLabel)
                .lineLimit(1)

            HStack(spacing: 5) {
                Circle()
                    .fill(project.status.color(accent: project.accent))
                    .frame(width: 5, height: 5)
                Text(project.status.displayName)
                Text("·")
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
                Text(WorkstateDateText.relative(project.lastActivityAt))
                    .monospacedDigit()
            }
            .font(WorkstateTheme.captionFont)
            .foregroundStyle(WorkstateTheme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)

            Text(latestTitle)
                .font(WorkstateTheme.microFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel.opacity(0.76))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        }
        .frame(
            width: ProjectNodeLayout.infoWidth,
            alignment: alignment == .leading ? .leading : .trailing
        )
    }

    private var latestTitle: String {
        project.latestEvent?.title ?? project.summary
    }
}

private struct ProjectNodeOrb: View {
    let color: Color
    let identityGradient: SmartisanGradientToken
    let status: ProjectStatus
    let activityAge: ActivityAge
    let isHovered: Bool
    let isDragging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status == .active {
                Circle()
                    .stroke(color.opacity(pulse ? 0.06 : 0.30), lineWidth: 1)
                    .scaleEffect(pulse ? 1.24 : 1.02)
            }

            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    identityGradient.fillStart.opacity(colorScheme == .dark ? 0.30 : 0.20),
                                    identityGradient.fillEnd.opacity(colorScheme == .dark ? 0.30 : 0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    WorkstateTheme.onAccent.opacity(colorScheme == .dark ? 0.20 : 0.52),
                                    color.opacity(colorScheme == .dark ? 0.18 : 0.11),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 42
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            WorkstateTheme.onAccent.opacity(colorScheme == .dark ? 0.14 : 0.60),
                            lineWidth: 0.7
                        )
                }
                .overlay {
                    Circle()
                        .trim(from: 0.06, to: 0.82)
                        .stroke(
                            color.opacity(isHovered || isDragging ? 0.95 : 0.70),
                            style: StrokeStyle(
                                lineWidth: isHovered || isDragging ? 1.8 : 1.35,
                                lineCap: .round,
                                dash: activityAge.borderDash
                            )
                        )
                        .rotationEffect(.degrees(-112))
                }

            Capsule()
                .fill(WorkstateTheme.onAccent.opacity(colorScheme == .dark ? 0.28 : 0.72))
                .frame(width: 13, height: 3)
                .rotationEffect(.degrees(-28))
                .offset(x: -9, y: -12)

            Image(systemName: status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .symbolRenderingMode(.monochrome)
        }
        .padding(isHovered || isDragging ? 1 : 4)
        .shadow(
            color: color.opacity(isDragging ? 0.38 : isHovered ? 0.28 : 0.14),
            radius: isDragging ? 14 : isHovered ? 11 : 7,
            y: isDragging ? 5 : 3
        )
        .shadow(
            color: WorkstateTheme.shadow.opacity(colorScheme == .dark ? 0.42 : 0.16),
            radius: isDragging ? 12 : 8,
            y: isDragging ? 7 : 4
        )
        .animation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.16), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .onAppear {
            guard status == .active, !reduceMotion, !snapshotRendering else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ProjectHoverSummary: View {
    let project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(summary)
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.primaryLabel)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(WorkstateDateText.relative(project.lastActivityAt))
                    .monospacedDigit()
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
            }
            .font(WorkstateTheme.microFont)
            .foregroundStyle(WorkstateTheme.secondaryLabel)
        }
        .padding(10)
        .frame(width: 218, alignment: .leading)
        .workstateGlassSurface(cornerRadius: 10)
        .shadow(color: WorkstateTheme.shadow.opacity(0.18), radius: 14, y: 7)
    }

    private var summary: String {
        project.context.currentSummary.isEmpty ? project.summary : project.context.currentSummary
    }
}

private enum ProjectNodeLayout {
    static let width: CGFloat = 258
    static let height: CGFloat = 68
    static let orbSize: CGFloat = 54
    static let infoWidth: CGFloat = 190
    static let spacing: CGFloat = 10
    static let centerOffset = (width - orbSize) / 2
}

private enum GraphCamera {
    static let minimumScale: CGFloat = 0.60
    static let maximumScale: CGFloat = 1.60
    static let step: CGFloat = 0.15
    static let horizontalInset: CGFloat = 24
    static let topInset: CGFloat = 74
    static let bottomInset: CGFloat = 62
}

private struct StatusLegend: View {
    let status: ProjectStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.displayName)
        }
        .font(WorkstateTheme.captionFont)
        .foregroundStyle(WorkstateTheme.secondaryLabel)
    }

    private var color: Color {
        switch status {
        case .active: WorkstateTheme.activeState
        case .waiting: WorkstateTheme.warning
        case .parked: WorkstateTheme.secondaryLabel
        case .completed: WorkstateTheme.success
        case .archived: WorkstateTheme.tertiaryLabel
        }
    }
}

private struct GraphToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 27, height: 27)
                .background {
                    Circle()
                        .fill(WorkstateTheme.primaryLabel.opacity(isHovered ? 0.09 : 0))
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = isEnabled && $0 }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}
