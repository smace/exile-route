import AppKit

@MainActor
final class GeForceFocusMonitor {
    static let bundleIdentifier = "com.nvidia.gfnpc.mall"
    private let model: AppModel
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.update(app) }
        }
    }

    private func update(_ application: NSRunningApplication?) {
        model.isGeForceNowActive = application?.bundleIdentifier == Self.bundleIdentifier
    }
}
