import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var overlayController: OverlayPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var statusBarController: StatusBarController?
    private var focusMonitor: GeForceFocusMonitor?
    private var hotKeyManager: GlobalHotKeyManager?
    private var ocrCoordinator: OCRCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayController = OverlayPanelController(model: model)
        let settingsWindowController = SettingsWindowController(model: model)
        self.settingsWindowController = settingsWindowController
        statusBarController = StatusBarController(
            model: model,
            openSettings: { [weak self] in
                self?.showSettings()
            }
        )
        focusMonitor = GeForceFocusMonitor(model: model)
        hotKeyManager = GlobalHotKeyManager(model: model)
        ocrCoordinator = OCRCoordinator(model: model)
        if ProcessInfo.processInfo.environment["EXILE_ROUTE_SETTINGS_PREVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--settings-preview") {
            settingsWindowController.showSettings()
        }
    }

    func showSettings() {
        settingsWindowController?.showSettings()
    }
}
