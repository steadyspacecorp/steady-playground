import SwiftUI

/// Observable state the desktop card renders from.
@MainActor
final class IntentionsModel: ObservableObject {
    @Published var day: DayIntentions?
    @Published var errorText: String?
    @Published var hasToken: Bool = Keychain.token?.isEmpty == false
    @Published var lastUpdated: Date?

    /// User-chosen text color (menu bar → Text Color…), defaulting to white.
    @Published var nsTextColor: NSColor = ColorStore.load()

    /// User-chosen text size; multiplies every glyph size in the card.
    @Published var textSize: TextSize = TextSizeStore.load()
    var scale: CGFloat { textSize.scale }

    var textColor: Color { Color(nsColor: nsTextColor) }
    var secondaryColor: Color { Color(nsColor: nsTextColor).opacity(0.78) }

    /// A faint shadow that contrasts with the chosen color, just to seat the
    /// glyphs against busy wallpapers.
    var shadowColor: Color {
        let c = nsTextColor.usingColorSpace(.sRGB) ?? nsTextColor
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.5 ? .black.opacity(0.45) : .white.opacity(0.45)
    }
}

/// The floating desktop card. Lives inside a translucent material panel so the
/// text stays readable against any wallpaper, in both light and dark mode.
struct IntentionsView: View {
    @ObservedObject var model: IntentionsModel

    private var bullets: [MarkdownLine] {
        MarkdownLine.parse(model.day?.intentions ?? "")
    }

    var body: some View {
        let scale = model.scale
        VStack(alignment: .leading, spacing: 26 * scale) {
            if !model.hasToken {
                placeholder("Set your Steady token from the menu bar to begin.",
                            systemImage: "key.fill")
            } else if let error = model.errorText {
                placeholder(error, systemImage: "exclamationmark.triangle.fill")
            } else if model.day == nil {
                placeholder("No check-in for today yet.",
                            systemImage: "moon.zzz.fill")
            } else if bullets.isEmpty {
                placeholder("No intentions written for today.",
                            systemImage: "text.append")
            } else {
                VStack(alignment: .leading, spacing: 20 * scale) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, line in
                        line.view(scale: scale)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(width: 620 * scale, alignment: .leading)
        // Render straight onto the wallpaper — no panel. Color is derived from
        // the wallpaper for contrast, so the shadow is only a faint seat.
        .foregroundStyle(model.textColor)
        .shadow(color: model.shadowColor, radius: 4, x: 0, y: 1)
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.system(size: 26 * model.scale))
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(model.secondaryColor)
        .padding(.vertical, 4)
    }
}

/// One rendered line of the intentions markdown: a bullet or a plain paragraph,
/// with inline formatting (links, bold, code) handled by `AttributedString`.
struct MarkdownLine {
    let isBullet: Bool
    let attributed: AttributedString

    @ViewBuilder
    func view(scale: CGFloat) -> some View {
        if isBullet {
            let pointSize: CGFloat = 32 * scale
            HStack(alignment: .firstTextBaseline, spacing: 18 * scale) {
                Circle()
                    .frame(width: 9 * scale, height: 9 * scale)
                    .alignmentGuide(.firstTextBaseline) { d in
                        // Lift the bullet so its center sits at the optical
                        // midline of the first line of text (roughly half the
                        // cap-height above the baseline) instead of resting
                        // on the baseline.
                        d[VerticalAlignment.center] + pointSize * 0.33
                    }
                Text(attributed)
                    .font(.system(size: pointSize, weight: .medium))
                    .lineSpacing(6 * scale)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(attributed)
                .font(.system(size: 32 * scale, weight: .semibold))
                .lineSpacing(6 * scale)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Splits markdown into lines, detecting `-`/`*`/`•` bullets, and renders
    /// inline markup per line.
    static func parse(_ markdown: String) -> [MarkdownLine] {
        markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { raw in
                var text = stripImages(raw)
                var isBullet = false
                for prefix in ["- ", "* ", "• ", "+ "] {
                    if text.hasPrefix(prefix) {
                        text = String(text.dropFirst(prefix.count))
                        isBullet = true
                        break
                    }
                }
                let options = AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
                var attributed = (try? AttributedString(markdown: text, options: options))
                    ?? AttributedString(text)
                // The card is non-interactive (clicks pass through) and we don't
                // want SwiftUI's blue link styling. Drop the link attribute so
                // the URL text inherits the chosen foreground color.
                attributed.link = nil
                return MarkdownLine(isBullet: isBullet, attributed: attributed)
            }
    }

    /// Removes `![alt](url)` image markdown, keeping the alt text if present.
    /// We never want images on the desktop card.
    private static func stripImages(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^)]*\)"#) else {
            return s
        }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
    }
}
