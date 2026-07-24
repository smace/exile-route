import AppKit
import Carbon
import Foundation

enum HotKeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case previous, next, expand, overlay, interact

    var title: String {
        switch self {
        case .previous: "Previous step"
        case .next: "Next step"
        case .expand: "Compact / expanded"
        case .overlay: "Overlay visibility"
        case .interact: "Interaction mode"
        }
    }

    var identifier: UInt32 {
        UInt32(Self.allCases.firstIndex(of: self)! + 1)
    }

    static func from(identifier: UInt32) -> HotKeyAction? {
        guard identifier > 0, Int(identifier) <= allCases.count else { return nil }
        return allCases[Int(identifier) - 1]
    }
}

enum HotKeyModifierPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case controlOption
    case controlCommand
    case optionCommand
    case controlShift
    case optionShift
    case commandShift
    case controlOptionCommand
    case controlOptionShift
    case controlCommandShift
    case optionCommandShift
    case controlOptionCommandShift

    var carbonValue: UInt32 {
        switch self {
        case .controlOption: UInt32(controlKey | optionKey)
        case .controlCommand: UInt32(controlKey | cmdKey)
        case .optionCommand: UInt32(optionKey | cmdKey)
        case .controlShift: UInt32(controlKey | shiftKey)
        case .optionShift: UInt32(optionKey | shiftKey)
        case .commandShift: UInt32(cmdKey | shiftKey)
        case .controlOptionCommand: UInt32(controlKey | optionKey | cmdKey)
        case .controlOptionShift: UInt32(controlKey | optionKey | shiftKey)
        case .controlCommandShift: UInt32(controlKey | cmdKey | shiftKey)
        case .optionCommandShift: UInt32(optionKey | cmdKey | shiftKey)
        case .controlOptionCommandShift: UInt32(controlKey | optionKey | cmdKey | shiftKey)
        }
    }

    var display: String {
        switch self {
        case .controlOption: "⌃⌥"
        case .controlCommand: "⌃⌘"
        case .optionCommand: "⌥⌘"
        case .controlShift: "⌃⇧"
        case .optionShift: "⌥⇧"
        case .commandShift: "⌘⇧"
        case .controlOptionCommand: "⌃⌥⌘"
        case .controlOptionShift: "⌃⌥⇧"
        case .controlCommandShift: "⌃⌘⇧"
        case .optionCommandShift: "⌥⌘⇧"
        case .controlOptionCommandShift: "⌃⌥⌘⇧"
        }
    }

    init?(eventModifiers: NSEvent.ModifierFlags) {
        let modifiers = eventModifiers.intersection([.control, .option, .command, .shift])
        switch modifiers {
        case [.control, .option]: self = .controlOption
        case [.control, .command]: self = .controlCommand
        case [.option, .command]: self = .optionCommand
        case [.control, .shift]: self = .controlShift
        case [.option, .shift]: self = .optionShift
        case [.command, .shift]: self = .commandShift
        case [.control, .option, .command]: self = .controlOptionCommand
        case [.control, .option, .shift]: self = .controlOptionShift
        case [.control, .command, .shift]: self = .controlCommandShift
        case [.option, .command, .shift]: self = .optionCommandShift
        case [.control, .option, .command, .shift]: self = .controlOptionCommandShift
        default: return nil
        }
    }
}

struct HotKeyDefinition: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: HotKeyModifierPreset

    var display: String { modifiers.display + (Self.keyOptions.first(where: { $0.code == keyCode })?.label ?? "?") }

    static let keyOptions: [(code: UInt32, label: String)] = [
        (UInt32(kVK_LeftArrow), "←"), (UInt32(kVK_RightArrow), "→"),
        (UInt32(kVK_UpArrow), "↑"), (UInt32(kVK_DownArrow), "↓"),
        (UInt32(kVK_Space), "Space"),
        (UInt32(kVK_ANSI_A), "A"), (UInt32(kVK_ANSI_B), "B"),
        (UInt32(kVK_ANSI_C), "C"), (UInt32(kVK_ANSI_D), "D"),
        (UInt32(kVK_ANSI_E), "E"), (UInt32(kVK_ANSI_F), "F"),
        (UInt32(kVK_ANSI_G), "G"), (UInt32(kVK_ANSI_H), "H"),
        (UInt32(kVK_ANSI_I), "I"), (UInt32(kVK_ANSI_J), "J"),
        (UInt32(kVK_ANSI_K), "K"), (UInt32(kVK_ANSI_L), "L"),
        (UInt32(kVK_ANSI_M), "M"), (UInt32(kVK_ANSI_N), "N"),
        (UInt32(kVK_ANSI_O), "O"), (UInt32(kVK_ANSI_P), "P"),
        (UInt32(kVK_ANSI_Q), "Q"), (UInt32(kVK_ANSI_R), "R"),
        (UInt32(kVK_ANSI_S), "S"), (UInt32(kVK_ANSI_T), "T"),
        (UInt32(kVK_ANSI_U), "U"), (UInt32(kVK_ANSI_V), "V"),
        (UInt32(kVK_ANSI_W), "W"), (UInt32(kVK_ANSI_X), "X"),
        (UInt32(kVK_ANSI_Y), "Y"), (UInt32(kVK_ANSI_Z), "Z"),
        (UInt32(kVK_ANSI_0), "0"), (UInt32(kVK_ANSI_1), "1"),
        (UInt32(kVK_ANSI_2), "2"), (UInt32(kVK_ANSI_3), "3"),
        (UInt32(kVK_ANSI_4), "4"), (UInt32(kVK_ANSI_5), "5"),
        (UInt32(kVK_ANSI_6), "6"), (UInt32(kVK_ANSI_7), "7"),
        (UInt32(kVK_ANSI_8), "8"), (UInt32(kVK_ANSI_9), "9"),
        (UInt32(kVK_F1), "F1"), (UInt32(kVK_F2), "F2"),
        (UInt32(kVK_F3), "F3"), (UInt32(kVK_F4), "F4"),
        (UInt32(kVK_F5), "F5"), (UInt32(kVK_F6), "F6"),
        (UInt32(kVK_F7), "F7"), (UInt32(kVK_F8), "F8"),
        (UInt32(kVK_F9), "F9"), (UInt32(kVK_F10), "F10"),
        (UInt32(kVK_F11), "F11"), (UInt32(kVK_F12), "F12")
    ]

    static func supports(keyCode: UInt32) -> Bool {
        keyOptions.contains(where: { $0.code == keyCode })
    }

    static let defaults: [HotKeyAction: HotKeyDefinition] = [
        .previous: HotKeyDefinition(keyCode: UInt32(kVK_LeftArrow), modifiers: .controlOption),
        .next: HotKeyDefinition(keyCode: UInt32(kVK_RightArrow), modifiers: .controlOption),
        .expand: HotKeyDefinition(keyCode: UInt32(kVK_Space), modifiers: .controlOption),
        .overlay: HotKeyDefinition(keyCode: UInt32(kVK_ANSI_O), modifiers: .controlOption),
        .interact: HotKeyDefinition(keyCode: UInt32(kVK_ANSI_I), modifiers: .controlOption)
    ]

    static func sanitized(
        _ definitions: [HotKeyAction: HotKeyDefinition]
    ) -> [HotKeyAction: HotKeyDefinition] {
        var result = defaults
        var claimed = Set(defaults.values)

        for action in HotKeyAction.allCases {
            guard let candidate = definitions[action],
                  candidate != defaults[action],
                  supports(keyCode: candidate.keyCode),
                  !claimed.contains(candidate),
                  let defaultDefinition = defaults[action] else { continue }
            claimed.remove(defaultDefinition)
            result[action] = candidate
            claimed.insert(candidate)
        }
        return result
    }
}
