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

enum HotKeyModifierPreset: String, Codable, CaseIterable, Sendable {
    case controlOption
    case controlCommand
    case optionCommand
    case controlShift

    var carbonValue: UInt32 {
        switch self {
        case .controlOption: UInt32(controlKey | optionKey)
        case .controlCommand: UInt32(controlKey | cmdKey)
        case .optionCommand: UInt32(optionKey | cmdKey)
        case .controlShift: UInt32(controlKey | shiftKey)
        }
    }

    var display: String {
        switch self {
        case .controlOption: "⌃⌥"
        case .controlCommand: "⌃⌘"
        case .optionCommand: "⌥⌘"
        case .controlShift: "⌃⇧"
        }
    }
}

struct HotKeyDefinition: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: HotKeyModifierPreset

    var display: String { modifiers.display + (Self.keyOptions.first(where: { $0.code == keyCode })?.label ?? "?") }

    static let keyOptions: [(code: UInt32, label: String)] = [
        (UInt32(kVK_LeftArrow), "←"), (UInt32(kVK_RightArrow), "→"),
        (UInt32(kVK_UpArrow), "↑"), (UInt32(kVK_DownArrow), "↓"),
        (UInt32(kVK_Space), "Space"),
        (UInt32(kVK_ANSI_A), "A"), (UInt32(kVK_ANSI_E), "E"),
        (UInt32(kVK_ANSI_I), "I"), (UInt32(kVK_ANSI_O), "O"),
        (UInt32(kVK_ANSI_P), "P"), (UInt32(kVK_ANSI_R), "R"),
        (UInt32(kVK_ANSI_S), "S"), (UInt32(kVK_ANSI_V), "V")
    ]

    static let defaults: [HotKeyAction: HotKeyDefinition] = [
        .previous: HotKeyDefinition(keyCode: UInt32(kVK_LeftArrow), modifiers: .controlOption),
        .next: HotKeyDefinition(keyCode: UInt32(kVK_RightArrow), modifiers: .controlOption),
        .expand: HotKeyDefinition(keyCode: UInt32(kVK_Space), modifiers: .controlOption),
        .overlay: HotKeyDefinition(keyCode: UInt32(kVK_ANSI_O), modifiers: .controlOption),
        .interact: HotKeyDefinition(keyCode: UInt32(kVK_ANSI_I), modifiers: .controlOption)
    ]
}
