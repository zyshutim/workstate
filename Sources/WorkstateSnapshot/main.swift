import AppKit
import SwiftUI
import WorkstateCore
import WorkstateUI

@main
struct WorkstateSnapshot {
    @MainActor
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let mode = arguments.first ?? "event"
        let output = arguments.dropFirst().first ?? "/tmp/workstate-\(mode).png"
        let appearanceName = arguments.dropFirst(2).first ?? "light"
        let sourceName = arguments.dropFirst(3).first ?? "bootstrap"
        let projectID = arguments.dropFirst(4).first ?? "reframe-multicam"
        let focusedProjectID = arguments.dropFirst(5).first
        guard let appearance = SnapshotAppearance(rawValue: appearanceName) else {
            throw SnapshotError.invalidAppearance(appearanceName)
        }
        guard let source = SnapshotSource(rawValue: sourceName) else {
            throw SnapshotError.invalidSource(sourceName)
        }
        NSApplication.shared.appearance = NSAppearance(named: appearance.appKitName)

        let temporaryRoot = source == .bootstrap
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("workstate-snapshot-\(UUID().uuidString)", isDirectory: true)
            : nil
        defer {
            if let temporaryRoot {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
        }
        let repository = temporaryRoot.map {
            WorkstateRepository(paths: WorkstatePaths(root: $0))
        } ?? WorkstateRepository()
        if source == .bootstrap {
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
        } else {
            try repository.ensureInitialized()
        }
        let model = WorkstateViewModel(repository: repository)

        if mode != "graph" && mode != "projects" && mode != "reviews" {
            model.selectProject(projectID)
            if (mode == "event" || mode == "detail"), projectID == "reframe-multicam" {
                model.selectEvent("mc-preview-model")
            }
            if mode == "context" {
                model.isContextExpanded = true
            }
        }
        if mode == "reviews" {
            model.isReviewInboxPresented = true
            model.selectedReviewID = model.pendingReviews.first?.id
        }

        let view = WorkstateRootView(model: model)
            .frame(width: model.preferredWidth, height: model.preferredHeight)
            .environment(\.colorScheme, appearance.colorScheme)
            .workstateSnapshotRendering()
            .workstateSnapshotFocusedProject(focusedProjectID)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: model.preferredWidth, height: model.preferredHeight)

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
        print(output)
    }
}

private enum SnapshotError: LocalizedError {
    case renderFailed
    case invalidAppearance(String)
    case invalidSource(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            "Could not render Workstate snapshot"
        case let .invalidAppearance(value):
            "Unsupported appearance '\(value)'; expected light or dark"
        case let .invalidSource(value):
            "Unsupported source '\(value)'; expected bootstrap or live"
        }
    }
}

private enum SnapshotSource: String {
    case bootstrap
    case live
}

private enum SnapshotAppearance: String {
    case light
    case dark

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
