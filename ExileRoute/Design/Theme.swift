import SwiftUI
import AppKit

enum Theme {
    static let obsidian = Color(hex: 0x0B0D0F)
    static let smokedSurface = Color(hex: 0x15181B)
    static let brass = Color(hex: 0xB79258)
    static let agedGold = Color(hex: 0xD2B06A)
    static let ivory = Color(hex: 0xE7DDC7)
    static let ember = Color(hex: 0xC65D37)
    static let waypointCyan = Color(hex: 0x6FA9A6)
    static let danger = Color(hex: 0xA9463D)
    static let muted = Color(hex: 0x978B78)
    static let strengthGem = Color(hex: 0xC85A52)
    static let dexterityGem = Color(hex: 0x58A86B)
    static let intelligenceGem = Color(hex: 0x5B8EC9)

    static func gemColor(for primaryAttribute: String) -> Color {
        switch primaryAttribute.lowercased() {
        case "strength": strengthGem
        case "dexterity": dexterityGem
        case "intelligence": intelligenceGem
        default: agedGold
        }
    }

    static func titleFont(size: CGFloat) -> Font {
        .custom("Cinzel", size: size, relativeTo: .title)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
