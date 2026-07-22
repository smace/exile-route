import Carbon
import Combine
import Foundation

@MainActor
final class GlobalHotKeyManager {
    private let model: AppModel
    private var references: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        installHandler()
        registerAll(model.hotKeys)
        model.$hotKeys.dropFirst().sink { [weak self] definitions in
            self?.registerAll(definitions)
        }.store(in: &cancellables)
    }

    private func registerAll(_ definitions: [HotKeyAction: HotKeyDefinition]) {
        references.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        for action in HotKeyAction.allCases {
            guard let definition = definitions[action] else { continue }
            register(action, definition: definition)
        }
    }

    private func register(_ action: HotKeyAction, definition: HotKeyDefinition) {
        let signature = OSType(0x45585254) // EXRT
        var reference: EventHotKeyRef?
        RegisterEventHotKey(
            definition.keyCode,
            definition.modifiers.carbonValue,
            EventHotKeyID(signature: signature, id: action.identifier),
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
                Task { @MainActor in manager.perform(HotKeyAction.from(identifier: hotKey.id)) }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handler
        )
    }

    private func perform(_ action: HotKeyAction?) {
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
