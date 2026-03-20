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
        MenuBarExtra {
            RootScene(container: container, trayModel: trayModel)
                .frame(width: LayoutRules.defaultPanelWidth, height: LayoutRules.defaultPanelHeight)
        } label: {
            Image(nsImage: Self.statusBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Status Bar Icon

    /// Cached template image – built once, reused across body re-evaluations.
    private static let statusBarIcon: NSImage = makeStatusBarIcon()

    /// Draw the "staggered toggle" icon via Core Graphics and return it as a
    /// template NSImage. Three tracks with dots at left / center / right form
    /// a diagonal pattern — unique and legible at 18 pt.
    private static func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let trackH: CGFloat = 1.8
            let trackR: CGFloat = 0.9
            let trackX: CGFloat = 2
            let trackW: CGFloat = 14

            let dotR: CGFloat = 2.6
            let dotXPositions: [CGFloat] = [5, 9, 13]
            let yCenters: [CGFloat] = [4.4, 9.0, 13.6]

            // Tracks (semi-transparent)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.50).cgColor)
            for yc in yCenters {
                let trackRect = CGRect(
                    x: trackX, y: yc - trackH / 2,
                    width: trackW, height: trackH
                )
                let path = CGPath(
                    roundedRect: trackRect,
                    cornerWidth: trackR, cornerHeight: trackR,
                    transform: nil
                )
                ctx.addPath(path)
                ctx.fillPath()
            }

            // Dots (full opacity, staggered diagonally)
            ctx.setFillColor(NSColor.black.cgColor)
            for (i, yc) in yCenters.enumerated() {
                let cx = dotXPositions[i]
                let dotRect = CGRect(
                    x: cx - dotR, y: yc - dotR,
                    width: dotR * 2, height: dotR * 2
                )
                ctx.fillEllipse(in: dotRect)
            }

            return true
        }

        image.isTemplate = true
        return image
    }
}

@MainActor
private final class AIMenuAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No-op
    }
}
