import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    enum Action: UInt32, CaseIterable {
        case previous = 1
        case next = 2
        case expand = 3
        case overlay = 4
        case interact = 5
    }

    private let model: AppModel
    private var references: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    init(model: AppModel) {
        self.model = model
        installHandler()
        register(.previous, keyCode: UInt32(kVK_LeftArrow))
        register(.next, keyCode: UInt32(kVK_RightArrow))
        register(.expand, keyCode: UInt32(kVK_Space))
        register(.overlay, keyCode: UInt32(kVK_ANSI_O))
        register(.interact, keyCode: UInt32(kVK_ANSI_I))
    }

    private func register(_ action: Action, keyCode: UInt32) {
        let signature = OSType(0x45585254) // EXRT
        var reference: EventHotKeyRef?
        RegisterEventHotKey(
            keyCode,
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: signature, id: action.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        references.append(reference)
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKey = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKey
                )
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.perform(Action(rawValue: hotKey.id)) }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handler
        )
    }

    private func perform(_ action: Action?) {
        switch action {
        case .previous: model.movePrevious()
        case .next: model.moveNext()
        case .expand: model.toggleExpanded()
        case .overlay: model.toggleOverlay()
        case .interact: model.toggleInteraction()
        case nil: break
        }
    }
}
