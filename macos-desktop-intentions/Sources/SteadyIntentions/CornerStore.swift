import Foundation

/// Which screen corner the card anchors to. Persisted in UserDefaults.
enum WindowCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var menuTitle: String {
        switch self {
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum CornerStore {
    private static let key = "windowCorner"

    static func load() -> WindowCorner {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let corner = WindowCorner(rawValue: raw) else {
            return .topLeft
        }
        return corner
    }

    static func save(_ corner: WindowCorner) {
        UserDefaults.standard.set(corner.rawValue, forKey: key)
    }
}
