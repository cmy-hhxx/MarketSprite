import Foundation

enum ShortcutModifierOption: String, Codable, CaseIterable, Identifiable {
    case commandOption
    case commandShift
    case controlOption
    case controlShift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandOption: "⌘⌥"
        case .commandShift: "⌘⇧"
        case .controlOption: "⌃⌥"
        case .controlShift: "⌃⇧"
        }
    }
}

enum ShortcutKeyOption: String, Codable, CaseIterable, Identifiable {
    case s = "S"
    case p = "P"
    case h = "H"
    case k = "K"
    case d = "D"
    case f = "F"
    case space = "Space"

    var id: String { rawValue }
    var displayName: String { self == .space ? tr("空格") : rawValue }
}

extension Notification.Name {
    static let marketSpriteShortcutChanged = Notification.Name(
        "marketSprite.shortcutChanged"
    )
}
