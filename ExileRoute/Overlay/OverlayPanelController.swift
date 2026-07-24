import AppKit
import Combine
import SwiftUI

final class OverlayPanel: NSPanel {
    var interactionEnabled = false
    override var canBecomeKey: Bool { interactionEnabled }
    override var canBecomeMain: Bool { false }
}

struct OverlayPlacement {
    static let trailingInset: CGFloat = 24
    static let ocrGap: CGFloat = 12

    static func defaultOrigin(
        visibleFrame: CGRect,
        panelSize: CGSize,
        ocrCrop: NormalizedRect
    ) -> CGPoint {
        let topInset = ocrBottomInset(visibleFrame: visibleFrame, ocrCrop: ocrCrop)
        return constrainedOrigin(
            CGPoint(
                x: visibleFrame.maxX - trailingInset - panelSize.width,
                y: visibleFrame.maxY - topInset - panelSize.height
            ),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
    }

    static func ocrBottomInset(visibleFrame: CGRect, ocrCrop: NormalizedRect) -> CGFloat {
        let cropBottomFromTop = 1 - min(max(CGFloat(ocrCrop.y), 0), 1)
        return visibleFrame.height * cropBottomFromTop + ocrGap
    }

    static func resizedOrigin(currentFrame: CGRect, newSize: CGSize) -> CGPoint {
        CGPoint(
            x: currentFrame.maxX - newSize.width,
            y: currentFrame.maxY - newSize.height
        )
    }

    static func shouldAnimateResize(
        hasCompletedInitialResize: Bool,
        isPanelVisible: Bool
    ) -> Bool {
        hasCompletedInitialResize && isPanelVisible
    }

    static func completesInitialResize(currentSize: CGSize, newSize: CGSize) -> Bool {
        currentSize != newSize
    }

    static func constrainedOrigin(
        _ origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }
}

@MainActor
final class OverlayPanelController {
    private let model: AppModel
    private let panel: OverlayPanel
    private var cancellables: Set<AnyCancellable> = []
    private var hasCompletedInitialResize = false

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

        Publishers.CombineLatest(model.$isExpanded.removeDuplicates(), model.$compactOverlayHeight.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded, compactHeight in
                self?.resize(expanded: expanded, compactHeight: compactHeight)
            }
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

    private func resize(expanded: Bool, compactHeight: CGFloat) {
        let oldFrame = panel.frame
        let size = expanded ? NSSize(width: 460, height: 560) : NSSize(width: 390, height: compactHeight)
        let proposed = OverlayPlacement.resizedOrigin(currentFrame: oldFrame, newSize: size)
        let origin = constrainedOrigin(proposed, size: size, screen: panel.screen ?? NSScreen.main)
        let shouldAnimate = OverlayPlacement.shouldAnimateResize(
            hasCompletedInitialResize: hasCompletedInitialResize,
            isPanelVisible: panel.isVisible
        )
        let completesInitialResize = OverlayPlacement.completesInitialResize(
            currentSize: oldFrame.size,
            newSize: size
        )
        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true,
            animate: shouldAnimate
        )
        if completesInitialResize {
            hasCompletedInitialResize = true
        }
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
            let proposed = OverlayPlacement.resizedOrigin(currentFrame: stored, newSize: size)
            let origin = constrainedOrigin(proposed, size: size, screen: screen)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        } else {
            let size = panel.frame.size
            let origin = OverlayPlacement.defaultOrigin(
                visibleFrame: visible,
                panelSize: size,
                ocrCrop: model.ocrCrop
            )
            let frame = NSRect(origin: origin, size: size)
            panel.setFrame(frame, display: false)
            model.saveOverlayFrame(frame, for: id)
        }
    }

    private func savePosition() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        model.saveOverlayFrame(panel.frame, for: screenIdentifier(screen))
    }

    private func constrainedOrigin(_ origin: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        guard let visible = screen?.visibleFrame else { return origin }
        return OverlayPlacement.constrainedOrigin(origin, panelSize: size, visibleFrame: visible)
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "display-\(number?.uint32Value ?? 0)"
    }
}
