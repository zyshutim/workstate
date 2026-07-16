import SwiftUI
import WorkstateUI

@main
struct WorkstatePreviewApp: App {
    @StateObject private var model = WorkstateViewModel()

    var body: some Scene {
        WindowGroup("Workstate Preview") {
            WorkstateRootView(model: model)
        }
        .defaultSize(width: 600, height: 680)
    }
}
