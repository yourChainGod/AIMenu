import SwiftUI
import AppKit

@main
struct AIMenuApp: App {
    private let container: AppContainer
    @StateObject private var trayModel: TrayMenuModel
    @NSApplicationDelegateAdaptor(AIMenuAppDelegate.self) private var appDelegate

    init() {
        let container = AppContainer.liveOrCrash()
        self.container = container
        _trayModel = StateObject(wrappedValue: container.trayModel)
        Task { @MainActor in
            container.trayModel.startBackgroundRefresh()
        }
    }

    var body: some Scene {
        MenuBarExtra("AIMenu", systemImage: "drop.halffull") {
            RootScene(container: container, trayModel: trayModel)
                .frame(width: LayoutRules.defaultPanelWidth, height: LayoutRules.defaultPanelHeight)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private final class AIMenuAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No-op
    }
}
