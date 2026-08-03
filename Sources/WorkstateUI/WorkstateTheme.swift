import AppKit
import SwiftUI
import WorkstateCore

enum WorkstateTheme {
    static let graphWidth: CGFloat = 600
    static let graphHeight: CGFloat = 680
    static let projectWidth: CGFloat = 600
    static let projectHeight: CGFloat = 790
    static let eventPopoverWidth: CGFloat = 416
    static let eventPopoverHeight: CGFloat = 560
    static let eventTooltipWidth: CGFloat = 286
    static let headerHeight: CGFloat = 54
    static let graphNodeSize = CGSize(width: 190, height: 92)
    static let timelineRowHeight: CGFloat = 62

    static let windowBackground = SmartisanColorTokens.adaptive(light: 0xF5F5F5, dark: 0x222325)
    static let contentBackground = SmartisanColorTokens.adaptive(light: 0xFFFFFF, dark: 0x333333)
    static let surfaceBackground = SmartisanColorTokens.adaptive(light: 0xFFFFFF, dark: 0x333333)
    static let raisedSurfaceBackground = SmartisanColorTokens.adaptive(light: 0xFFFFFF, dark: 0x3B3C3F)
    static let graphBackground = SmartisanColorTokens.adaptive(light: 0xF5F5F5, dark: 0x222325)
    static let workspaceBackground = SmartisanColorTokens.adaptive(light: 0xFAFAFA, dark: 0x222325)
    static let timelineBackground = SmartisanColorTokens.adaptive(light: 0xF2F2F2, dark: 0x333333)
    static let inspectorTimelineBackground = SmartisanColorTokens.adaptive(light: 0xF2F2F2, dark: 0x333333)
    static let inspectorReferenceBackground = SmartisanColorTokens.adaptive(light: 0xFAFAFA, dark: 0x222325)
    static let contextBackground = SmartisanColorTokens.adaptive(light: 0xF2F2F2, dark: 0x333333)
    static let headerVeil = SmartisanColorTokens.adaptive(light: 0xFFFFFF, dark: 0x222325)
    static let snapshotSurfaceColor = SmartisanColorTokens.adaptive(light: 0xFFFFFF, dark: 0x3B3C3F)
    static let separator = SmartisanColorTokens.adaptive(light: 0xE2E2E2, dark: 0x7F7F7F)
    static let grid = SmartisanColorTokens.adaptive(light: 0xE2E2E2, dark: 0x7F7F7F).opacity(0.52)
    static let relation = SmartisanColorTokens.adaptive(light: 0x9D9D9D, dark: 0xBABABA).opacity(0.64)
    static let primaryLabel = SmartisanColorTokens.adaptive(light: 0x333333, dark: 0xFAFAFA)
    static let secondaryLabel = SmartisanColorTokens.adaptive(light: 0x636363, dark: 0xBABABA)
    static let tertiaryLabel = SmartisanColorTokens.adaptive(light: 0x9D9D9D, dark: 0x9D9D9D)
    static let shadow = SmartisanColorTokens.adaptive(light: 0x333333, dark: 0x222325)
    static let onAccent = SmartisanColorTokens.Neutral.white

    static let activeState = SmartisanColorTokens.Brand.b500
    static let success = SmartisanColorTokens.Success.s500
    static let warning = SmartisanColorTokens.Warning.w500
    static let danger = SmartisanColorTokens.Danger.d500
    static let observed = SmartisanColorTokens.Theme.cyan.representative

    static let smallCornerRadius: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let largeCornerRadius: CGFloat = 10

    static let windowTitleFont = Font.title3.weight(.semibold)
    static let projectTitleFont = Font.title2.weight(.semibold)
    static let sectionTitleFont = Font.headline
    static let headlineFont = Font.subheadline.weight(.semibold)
    static let bodyFont = Font.body
    static let secondaryFont = Font.subheadline
    static let captionFont = Font.caption
    static let captionEmphasisFont = Font.caption.weight(.medium)
    static let microFont = Font.caption2
}

enum WorkstateReportTokens {
    static let leadTitleFont = Font.system(size: 18, weight: .semibold)
    static let sectionTitleFont = Font.system(size: 15, weight: .semibold)
    static let subsectionTitleFont = Font.system(size: 13, weight: .semibold)
    static let leadBodyFont = Font.system(size: 15, weight: .regular)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let metadataFont = Font.system(size: 11, weight: .medium)

    static let leadSectionSpacing: CGFloat = 18
    static let sectionSpacing: CGFloat = 24
    static let blockSpacing: CGFloat = 9
    static let bodyLineSpacing: CGFloat = 5
    static let listIndent: CGFloat = 18
}

struct WorkstateGlassContainer<Content: View>: View {
    let content: Content
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if snapshotRendering {
            content
        } else if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func workstateGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(WorkstateGlassSurfaceModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

private struct WorkstateGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workstateSnapshotRendering) private var snapshotRendering

    @ViewBuilder
    func body(content: Content) -> some View {
        if snapshotRendering {
            content
                .background(
                    snapshotSurface,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            WorkstateTheme.onAccent.opacity(colorScheme == .dark ? 0.12 : 0.78),
                            lineWidth: 0.6
                        )
                }
                .shadow(color: WorkstateTheme.shadow.opacity(0.14), radius: 12, y: 5)
        } else if #available(macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(WorkstateTheme.separator.opacity(0.68), lineWidth: 0.5)
                }
        }
    }

    private var snapshotSurface: Color {
        WorkstateTheme.snapshotSurfaceColor.opacity(colorScheme == .dark ? 0.94 : 0.92)
    }
}

extension ProjectAccent {
    var gradient: SmartisanGradientToken {
        switch self {
        case .blue: SmartisanColorTokens.Button.primaryEnabled
        case .green: SmartisanColorTokens.Theme.green
        case .red: SmartisanColorTokens.Theme.suoh
        case .amber: SmartisanColorTokens.Theme.orange
        case .violet: SmartisanColorTokens.Theme.purple
        case .cyan: SmartisanColorTokens.Theme.cyan
        }
    }

    var color: Color {
        gradient.representative
    }
}

extension ProjectStatus {
    var displayName: String {
        switch self {
        case .active: "进行中"
        case .waiting: "等待"
        case .parked: "已停放"
        case .completed: "已完成"
        case .archived: "已归档"
        }
    }

    var symbol: String {
        switch self {
        case .active: "play.fill"
        case .waiting: "clock"
        case .parked: "pause.fill"
        case .completed: "checkmark"
        case .archived: "archivebox"
        }
    }

    func color(accent: ProjectAccent) -> Color {
        switch self {
        case .active: accent.color
        case .waiting: WorkstateTheme.warning
        case .parked: WorkstateTheme.secondaryLabel
        case .completed: WorkstateTheme.success
        case .archived: WorkstateTheme.tertiaryLabel
        }
    }
}

extension TaskStatus {
    var displayName: String {
        switch self {
        case .active: "进行中"
        case .waiting: "等待"
        case .parked: "停放"
        case .completed: "完成"
        case .abandoned: "终止"
        }
    }

    var symbol: String {
        switch self {
        case .active: "play.fill"
        case .waiting: "clock.fill"
        case .parked: "pause.fill"
        case .completed: "checkmark"
        case .abandoned: "xmark"
        }
    }

    func color(accent: ProjectAccent) -> Color {
        switch self {
        case .active: accent.color
        case .waiting: WorkstateTheme.warning
        case .parked: WorkstateTheme.secondaryLabel
        case .completed: WorkstateTheme.success
        case .abandoned: WorkstateTheme.danger
        }
    }
}

extension RelationKind {
    var symbol: String {
        switch self {
        case .workTransferred: "arrow.turn.up.right"
        case .sharesContext: "link"
        case .dependsOn: "arrow.right"
        case .spawnedFrom: "arrow.triangle.branch"
        }
    }
}

extension EvidenceStatus {
    var displayName: String {
        switch self {
        case .observed: "已观察"
        case .inferred: "推断"
        case .confirmed: "已确认"
        case .superseded: "已替代"
        case .prohibited: "禁止"
        }
    }

    var color: Color {
        switch self {
        case .observed: WorkstateTheme.observed
        case .inferred: WorkstateTheme.warning
        case .confirmed: WorkstateTheme.success
        case .superseded: WorkstateTheme.secondaryLabel
        case .prohibited: WorkstateTheme.danger
        }
    }
}

extension LoopStage {
    var displayName: String {
        switch self {
        case .intake: "接手"
        case .reconstruction: "上下文恢复"
        case .audit: "真实审计"
        case .modeling: "状态建模"
        case .confirmation: "确认"
        case .implementation: "实现"
        case .verification: "验证"
        case .acceptance: "验收"
        case .integration: "集成"
        case .completed: "完成"
        }
    }
}

extension EventKind {
    var symbol: String {
        switch self {
        case .projectStarted: "flag.fill"
        case .taskStarted: "arrow.triangle.branch"
        case .contextUpdate: "text.book.closed"
        case .investigation: "magnifyingglass"
        case .decision: "checkmark.seal"
        case .implementation: "hammer"
        case .verification: "checkmark.circle"
        case .accepted: "person.crop.circle.badge.checkmark"
        case .integrated: "arrow.merge"
        case .operational: "terminal"
        case .interruption: "pause.circle"
        case .resumed: "arrow.clockwise"
        case .handedOff: "arrow.turn.up.right"
        case .completed: "flag.checkered"
        }
    }
}

extension DeliveryStage {
    var displayName: String {
        switch self {
        case .unchanged: "未改动"
        case .changed: "已修改"
        case .checked: "检查通过"
        case .rendered: "已运行"
        case .userAccepted: "用户已接受"
        case .integrated: "已集成"
        case .published: "已发布"
        }
    }
}

enum ActivityAge {
    case recent
    case cooling
    case stale

    init(lastActivityAt: Date, now: Date = Date()) {
        let days = now.timeIntervalSince(lastActivityAt) / 86_400
        if days < 3 {
            self = .recent
        } else if days < 21 {
            self = .cooling
        } else {
            self = .stale
        }
    }

    var borderDash: [CGFloat] {
        switch self {
        case .recent, .cooling: []
        case .stale: [4, 3]
        }
    }
}

enum WorkstateDateText {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if abs(date.timeIntervalSince(now)) < 60 {
            return "刚刚"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func compact(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
