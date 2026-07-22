import AppKit
import Combine
import SwiftUI

final class OverlayPanel: NSPanel {
    var interactionEnabled = false
    override var canBecomeKey: Bool { interactionEnabled }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController {
    private let model: AppModel
    private let panel: OverlayPanel
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 210),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        bind()
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: OverlayView().environmentObject(model))
        restorePosition()
    }

    private func bind() {
        Publishers.CombineLatest(model.$isGeForceNowActive, model.$forceVisible)
            .receive(on: RunLoop.main)
            .sink { [weak self] active, forced in self?.setVisible(active || forced) }
            .store(in: &cancellables)

        model.$isExpanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in self?.resize(expanded: expanded) }
            .store(in: &cancellables)

        model.$isInteractionEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                panel.interactionEnabled = enabled
                panel.ignoresMouseEvents = !enabled
                if enabled { panel.orderFrontRegardless() } else { savePosition() }
            }
            .store(in: &cancellables)
    }

    private func resize(expanded: Bool) {
        let oldFrame = panel.frame
        let size = expanded ? NSSize(width: 460, height: 560) : NSSize(width: 390, height: 210)
        let proposed = NSPoint(x: oldFrame.maxX - size.width, y: oldFrame.maxY - size.height)
        let origin = constrainedOrigin(proposed, size: size, screen: panel.screen ?? NSScreen.main)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }

    private func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() }
        else if !model.isInteractionEnabled { panel.orderOut(nil) }
    }

    private func restorePosition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let id = screenIdentifier(screen)
        if let stored = model.overlayFrame(for: id) {
            let size = panel.frame.size
            let origin = constrainedOrigin(stored.origin, size: size, screen: screen)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        } else {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 410, y: visible.maxY - 240))
        }
    }

    private func savePosition() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        model.saveOverlayFrame(panel.frame, for: screenIdentifier(screen))
    }

    private func constrainedOrigin(_ origin: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        guard let visible = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "display-\(number?.uint32Value ?? 0)"
    }
}
