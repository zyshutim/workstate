import SwiftUI
import WorkstateCore

struct DailyBriefView: View {
    @ObservedObject var model: WorkstateViewModel
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering
    @State private var recordsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(WorkstateTheme.separator)

            Group {
                if let brief = model.dailyBrief {
                    briefContent(brief)
                } else {
                    ContentUnavailableView(
                        "尚未形成工作摘要",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("出现有效项目进展后会保留在这里")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: WorkstateTheme.projectWidth, height: WorkstateTheme.projectHeight)
        .background(WorkstateTheme.workspaceBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: model.closeDailyBrief) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .workstateGlassSurface(cornerRadius: 14, interactive: true)
            .help("返回项目图谱")

            VStack(alignment: .leading, spacing: 2) {
                Text("工作摘要")
                    .font(WorkstateTheme.windowTitleFont)
                if let brief = model.dailyBrief {
                    Text(dateText(brief.intervalStart))
                        .font(WorkstateTheme.captionFont.monospacedDigit())
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                dateNavigationButton(
                    systemName: "chevron.left",
                    label: "上一份工作摘要",
                    isEnabled: model.canShowPreviousDailyBrief,
                    action: model.showPreviousDailyBrief
                )
                dateNavigationButton(
                    systemName: "chevron.right",
                    label: "下一份工作摘要",
                    isEnabled: model.canShowNextDailyBrief,
                    action: model.showNextDailyBrief
                )
            }
            .padding(3)
            .workstateGlassSurface(cornerRadius: 14, interactive: true)
        }
        .padding(.horizontal, 14)
        .frame(height: WorkstateTheme.headerHeight)
        .background(WorkstateTheme.headerVeil)
    }

    @ViewBuilder
    private func briefContent(_ brief: DailyBrief) -> some View {
        if snapshotRendering {
            narrativeContent(brief)
                .frame(
                    width: WorkstateTheme.projectWidth,
                    height: WorkstateTheme.projectHeight - WorkstateTheme.headerHeight - 1,
                    alignment: .top
                )
        } else {
            ScrollView {
                narrativeContent(brief)
            }
            .scrollIndicators(.automatic)
            .frame(
                width: WorkstateTheme.projectWidth,
                height: WorkstateTheme.projectHeight - WorkstateTheme.headerHeight - 1
            )
        }
    }

    private func narrativeContent(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let narrative = brief.currentNarrative {
                Text(narrative.overview)
                    .font(WorkstateTheme.bodyFont)
                    .foregroundStyle(WorkstateTheme.primaryLabel)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)

                Divider()

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(brief.projects) { project in
                        if let summary = narrative.projectSummaries.first(where: {
                            $0.projectID == project.projectID
                        }) {
                            NarrativeProjectSection(
                                project: project,
                                summary: summary.summary,
                                action: { model.openDailyBriefProject(project.projectID) }
                            )
                        }
                    }
                }
                .padding(.vertical, 24)

                if !narrative.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("接下来", systemImage: "play.circle")
                            .font(WorkstateTheme.headlineFont)
                            .foregroundStyle(WorkstateTheme.secondaryLabel)
                        Text(narrative.nextStep)
                            .font(WorkstateTheme.bodyFont)
                            .foregroundStyle(WorkstateTheme.primaryLabel)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 22)
                }
            } else {
                ContentUnavailableView(
                    "摘要等待生成",
                    systemImage: "text.quote",
                    description: Text("当天原始记录已经保留")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 54)
            }

            Divider()

            DisclosureGroup(isExpanded: $recordsExpanded) {
                DailyBriefRawRecords(brief: brief, onSelect: model.openDailyBriefItem)
                    .padding(.top, 14)
            } label: {
                Label("查看 \(brief.rawRecordCount) 条原始记录", systemImage: "doc.text.magnifyingglass")
                    .font(WorkstateTheme.headlineFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
            .disclosureGroupStyle(.automatic)
            .padding(.vertical, 18)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .long,
                time: .omitted,
                locale: Locale(identifier: "zh_CN")
            )
        )
    }

    private func dateNavigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 25, height: 25)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NarrativeProjectSection: View {
    let project: DailyProjectBrief
    let summary: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(project.accent.color)
                        .frame(width: 7, height: 7)
                    Text(project.projectName)
                        .font(WorkstateTheme.sectionTitleFont)
                        .foregroundStyle(WorkstateTheme.primaryLabel)
                }
                Text(summary)
                    .font(WorkstateTheme.bodyFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 0.78 : 1)
        .onHover { isHovered = $0 }
        .help("打开 \(project.projectName)")
    }
}

private struct DailyBriefRawRecords: View {
    let brief: DailyBrief
    let onSelect: (DailyBriefItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(brief.projects) { project in
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.projectName)
                        .font(WorkstateTheme.captionEmphasisFont)
                        .foregroundStyle(project.accent.color)
                        .padding(.bottom, 6)

                    ForEach(records(project)) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(WorkstateTheme.secondaryFont)
                                    .foregroundStyle(WorkstateTheme.primaryLabel)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !item.detail.isEmpty {
                                    Text(item.detail)
                                        .font(WorkstateTheme.captionFont)
                                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func records(_ project: DailyProjectBrief) -> [DailyBriefItem] {
        project.progress + project.confirmed + project.unresolved + project.resumePoints
    }
}
