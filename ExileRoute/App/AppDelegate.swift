import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var overlayController: OverlayPanelController?
    private var statusBarController: StatusBarController?
    private var focusMonitor: GeForceFocusMonitor?
    private var hotKeyManager: GlobalHotKeyManager?
    private var ocrCoordinator: OCRCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayController = OverlayPanelController(model: model)
        statusBarController = StatusBarController(model: model)
        focusMonitor = GeForceFocusMonitor(model: model)
        hotKeyManager = GlobalHotKeyManager(model: model)
        ocrCoordinator = OCRCoordinator(model: model)
    }
}
