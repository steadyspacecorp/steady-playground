import AppKit

/// Persists the user-chosen text color in UserDefaults as an `#RRGGBB` string.
enum ColorStore {
    private static let key = "textColorHex"

    static func load() -> NSColor {
        guard let hex = UserDefaults.standard.string(forKey: key),
              let color = NSColor(hex: hex) else {
            return .white
        }
        return color
    }

    static func save(_ color: NSColor) {
        UserDefaults.standard.set(color.hexString, forKey: key)
    }
}

extension NSColor {
    /// `#RRGGBB` in sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
