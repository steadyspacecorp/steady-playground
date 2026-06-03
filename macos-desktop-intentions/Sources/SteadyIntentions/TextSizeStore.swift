import Foundation

/// Discrete text sizes selectable from the menu bar. The current design's
/// sizes are the `.medium` baseline; the other cases just scale them.
enum TextSize: String, CaseIterable {
    case small, medium, large, extraLarge

    var menuTitle: String {
        switch self {
        case .small:      return "Small"
        case .medium:     return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small:      return 0.75
        case .medium:     return 1.0
        case .large:      return 1.25
        case .extraLarge: return 1.5
        }
    }
}

enum TextSizeStore {
    private static let key = "textSize"

    static func load() -> TextSize {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let size = TextSize(rawValue: raw) else {
            return .medium
        }
        return size
    }

    static func save(_ size: TextSize) {
        UserDefaults.standard.set(size.rawValue, forKey: key)
    }
}
