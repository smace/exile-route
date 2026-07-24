import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    let definition: HotKeyDefinition
    let accessibilityLabel: String
    let onRecord: (HotKeyDefinition) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecord: onRecord)
    }

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.onRecord = context.coordinator.onRecord
        button.definition = definition
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
        context.coordinator.onRecord = onRecord
        button.onRecord = context.coordinator.onRecord
        button.definition = definition
        button.setAccessibilityLabel(accessibilityLabel)
        button.refreshTitle()
    }

    final class Coordinator {
        var onRecord: (HotKeyDefinition) -> Bool

        init(onRecord: @escaping (HotKeyDefinition) -> Bool) {
            self.onRecord = onRecord
        }
    }
}

final class HotKeyRecorderButton: NSButton {
    var definition = HotKeyDefinition.defaults[.previous]!
    var onRecord: ((HotKeyDefinition) -> Bool)?
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        contentTintColor = NSColor(Theme.ivory)
        focusRingType = .exterior
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }
        guard let modifiers = HotKeyModifierPreset(eventModifiers: event.modifierFlags),
              HotKeyDefinition.supports(keyCode: UInt32(event.keyCode)) else {
            NSSound.beep()
            title = "Use 2+ modifiers"
            return
        }

        let candidate = HotKeyDefinition(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard onRecord?(candidate) == true else {
            NSSound.beep()
            return
        }
        definition = candidate
        isRecording = false
        window?.makeFirstResponder(nil)
        refreshTitle()
    }

    func beginRecording() {
        isRecording = true
        title = "Press shortcut…"
        toolTip = "Press Escape to cancel"
        window?.makeFirstResponder(self)
    }

    func cancelRecording() {
        isRecording = false
        refreshTitle()
    }

    func refreshTitle() {
        guard !isRecording else { return }
        title = definition.display
        toolTip = "Click, then press a key with at least two modifiers"
        setAccessibilityValue(definition.display)
    }
}
