import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = CGSize(width: 560, height: 620)
    static let minimumSize = CGSize(width: 520, height: 500)

    init(model: AppModel, updater: ApplicationUpdater) {
        let rootView = SettingsView()
            .environmentObject(model)
            .environmentObject(updater)
            .frame(
                minWidth: Self.minimumSize.width,
                minHeight: Self.minimumSize.height
            )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Exile Route Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.contentSize)
        window.contentMinSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        let frameName = "ExileRouteSettingsWindow"
        let restoredFrame = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        if !restoredFrame {
            window.center()
        }

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showSettings() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
