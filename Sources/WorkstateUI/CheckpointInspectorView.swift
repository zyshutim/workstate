import AppKit
import SwiftUI
import WorkstateCore

struct EventDetailPopover: View {
    let workspace: WorkspaceSnapshot
    let project: ProjectRecord
    let task: TaskRecord?
    let event: ProjectEvent
    let onSelectTaskEvent: (String) -> Void
    let onClose: () -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.66))
                .frame(height: 0.5)

            referenceSection
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: task == nil ? event.kind.symbol : "arrow.triangle.branch")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(task?.title ?? event.title)
                    .font(WorkstateTheme.headlineFont)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                    Text(headerContext)
                        .lineLimit(1)
                }
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            }

            Spacer(minLength: 8)

            InspectorToolbarButton(
                systemName: "xmark",
                accessibilityLabel: "关闭",
                action: onClose
            )
        }
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .padding(.vertical, 13)
        .frame(minHeight: 62)
        .background(WorkstateTheme.headerVeil.opacity(0.22))
    }

    private var referenceSection: some View {
        Group {
            if snapshotRendering {
                referenceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    referenceContent
                }
                .scrollIndicators(.visible)
            }
        }
        .background(referenceBackground)
    }

    private var referenceContent: some View {
        VStack(spacing: 0) {
            EventSummarySection(event: event)

            if !event.decisions.isEmpty {
                DecisionReferenceSection(decisions: event.decisions)
            }

            InspectorReferenceSection(
                title: "已验证事实",
                systemImage: "checkmark.seal",
                values: event.facts
            )

            InspectorReferenceSection(
                title: "涉及范围",
                systemImage: "tag",
                values: event.tags
            )

            if !operationValues.isEmpty {
                InspectorReferenceSection(
                    title: "运行与文件",
                    systemImage: "terminal",
                    values: operationValues
                )
            }

            if !deliveryValues.isEmpty {
                InspectorReferenceSection(
                    title: "交付",
                    systemImage: "shippingbox",
                    values: deliveryValues
                )
            }

            if !resolvedSources.isEmpty {
                sourcesSection
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("证据", systemImage: "link")
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)

            ForEach(resolvedSources) { source in
                if source.kind == "conversation" {
                    ConversationEvidence(source: source)
                        .padding(.bottom, 8)
                }
                SourceReferenceButton(
                    source: source,
                    symbol: sourceSymbol(source.kind),
                    action: { open(source.locator) }
                )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    private var resolvedSources: [SourceReference] {
        let ids = Set(event.sourceIDs + (task?.sourceIDs ?? []))
        return workspace.sources.filter { ids.contains($0.id) }
    }

    private var operationValues: [String] {
        [
            event.operations.branch.isEmpty ? nil : "branch · \(event.operations.branch)",
            event.operations.commit.isEmpty ? nil : "commit · \(event.operations.commit)",
            event.operations.cwd.isEmpty ? nil : event.operations.cwd
        ].compactMap { $0 } + event.operations.files + event.operations.runtime
    }

    private var deliveryValues: [String] {
        let stage = event.delivery.stage == .unchanged ? [] : [event.delivery.stage.displayName]
        return stage + event.delivery.checks
    }

    private var accent: Color {
        task?.accent.color ?? project.accent.color
    }

    private var headerContext: String {
        if let task {
            return "\(task.currentStage.displayName) · \(task.status.displayName)"
        }
        return "项目主线 · \(event.loopStage.displayName)"
    }

    private var referenceBackground: Color {
        WorkstateTheme.inspectorReferenceBackground.opacity(0.98)
    }

    private func sourceSymbol(_ kind: String) -> String {
        switch kind {
        case "file": "doc.text"
        case "conversation": "bubble.left.and.text.bubble.right"
        case "repository": "shippingbox"
        case "commit": "point.3.connected.trianglepath.dotted"
        default: "link"
        }
    }

    private func open(_ locator: String) {
        let url = locator.hasPrefix("/")
            ? URL(fileURLWithPath: locator)
            : URL(string: locator)
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct InspectorToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
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

private struct TaskEventTimeline: View {
    let events: [ProjectEvent]
    let selectedEventID: String
    let accent: Color
    let onSelectEvent: (String) -> Void
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    var body: some View {
        Group {
            if snapshotRendering {
                timelineContent
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(height: 166, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    timelineContent
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private var timelineContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                TaskEventRow(
                    event: event,
                    isSelected: event.id == selectedEventID,
                    drawsContinuation: index < events.count - 1,
                    accent: accent,
                    action: { onSelectEvent(event.id) }
                )
            }
        }
    }
}

private struct TaskEventRow: View {
    let event: ProjectEvent
    let isSelected: Bool
    let drawsContinuation: Bool
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                ZStack(alignment: .top) {
                    if drawsContinuation {
                        Rectangle()
                            .fill(accent.opacity(0.30))
                            .frame(width: 1, height: 48)
                            .offset(y: 11)
                    }

                    Circle()
                        .fill(isSelected ? accent : WorkstateTheme.contentBackground)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(accent, lineWidth: 1.4)
                        }
                }
                .frame(width: 14, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(event.title)
                            .font(isSelected ? WorkstateTheme.captionEmphasisFont : WorkstateTheme.captionFont)
                            .foregroundStyle(isSelected ? accent : WorkstateTheme.primaryLabel)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(WorkstateDateText.compact(event.timestamp))
                            .font(WorkstateTheme.microFont.monospacedDigit())
                            .foregroundStyle(WorkstateTheme.tertiaryLabel)
                    }

                    Text(event.summary)
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                        .lineLimit(2)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(isSelected ? 0.10 : isHovered ? 0.05 : 0))
                }
                .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct EventSummarySection: View {
    let event: ProjectEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(event.title)
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)

            Text(event.summary)
                .font(WorkstateTheme.secondaryFont.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Label(event.loopStage.displayName, systemImage: "arrow.triangle.branch")

                if event.delivery.stage != .unchanged {
                    Label(event.delivery.stage.displayName, systemImage: "shippingbox")
                }
            }
            .font(WorkstateTheme.captionFont)
            .foregroundStyle(WorkstateTheme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            InspectorHairline()
        }
    }
}

private struct InspectorReferenceSection: View {
    let title: String
    let systemImage: String
    let values: [String]

    private var visibleValues: [String] {
        values.filter { !$0.isEmpty && $0 != DeliveryStage.unchanged.displayName }
    }

    var body: some View {
        if !visibleValues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(WorkstateTheme.captionEmphasisFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)

                ForEach(Array(visibleValues.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(WorkstateTheme.captionFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                InspectorHairline()
            }
        }
    }
}

private struct DecisionReferenceSection: View {
    let decisions: [DecisionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("决定", systemImage: "checkmark.seal")
                .font(WorkstateTheme.captionEmphasisFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)

            ForEach(decisions) { decision in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(decision.status.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)

                    Text(decision.text)
                        .font(WorkstateTheme.captionFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            InspectorHairline()
        }
    }
}

private struct SourceReferenceButton: View {
    let source: SourceReference
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .frame(width: 17)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.label)
                        .font(WorkstateTheme.captionEmphasisFont)
                        .foregroundStyle(WorkstateTheme.primaryLabel)
                    Text(source.locator)
                        .font(WorkstateTheme.microFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(WorkstateTheme.microFont)
                    .foregroundStyle(WorkstateTheme.tertiaryLabel)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(WorkstateTheme.primaryLabel.opacity(isHovered ? 0.05 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct InspectorHairline: View {
    var body: some View {
        Rectangle()
            .fill(WorkstateTheme.separator.opacity(0.58))
            .frame(height: 0.5)
    }
}
