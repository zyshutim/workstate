import AppKit
import SwiftUI
import WorkstateUI

@main
struct WorkstateMenuBarApp: App {
    @StateObject private var model = WorkstateViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            WorkstateRootView(model: model)
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .accessibilityLabel("工作状态")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("停止服务并退出") {
                    model.stopServiceAndExit()
                }
                .keyboardShortcut("q")
            }
        }
    }
}
