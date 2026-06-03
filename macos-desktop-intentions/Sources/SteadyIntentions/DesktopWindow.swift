import AppKit
import SwiftUI

/// A borderless, click-through window pinned to the desktop layer — it looks
/// like part of the wallpaper but is a window we fully control. Sits below all
/// app windows (so any fullscreen app naturally hides it) and above the
/// wallpaper.
final class DesktopWindow: NSPanel {
    private let hosting: NSHostingView<IntentionsView>
    private let model: IntentionsModel

    /// Scales with text size so the characters-per-line count stays roughly
    /// constant across Small / Medium / Large / Extra Large.
    private var cardWidth: CGFloat { 620 * model.scale }

    /// Which corner of the main screen the card pins to. Mutate from the
    /// menu-bar handler and call `refreshLayout()` to animate.
    var corner: WindowCorner = CornerStore.load()

    init(model: IntentionsModel) {
        self.model = model
        hosting = NSHostingView(rootView: IntentionsView(model: model))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true            // clicks pass through to the desktop
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        hosting.translatesAutoresizingMaskIntoConstraints = true
        contentView = hosting

        reposition()

        NotificationCenter.default.addObserver(
            self, selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// SwiftUI sizes itself; size the window to fit, then pin to the chosen
    /// corner of the main screen's visible area (which excludes the menu bar).
    @objc func reposition() {
        guard let screen = NSScreen.main else { return }
        let fitting = hosting.fittingSize
        let size = NSSize(width: cardWidth, height: max(fitting.height, 60))
        let visible = screen.visibleFrame
        let margin: CGFloat = 22
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = visible.minX + margin
            y = visible.maxY - size.height - margin
        case .topRight:
            x = visible.maxX - size.width - margin
            y = visible.maxY - size.height - margin
        case .bottomLeft:
            x = visible.minX + margin
            y = visible.minY + margin
        case .bottomRight:
            x = visible.maxX - size.width - margin
            y = visible.minY + margin
        }
        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    /// Snap the window to the new fitting size / corner. We intentionally don't
    /// animate the frame — a growing height as new content arrives looks like
    /// the card is "reacting", which works against the ambient wallpaper feel.
    func refreshLayout() {
        reposition()
    }

    func fadeIn() {
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            animator().alphaValue = 1
        }
    }

    func fadeOut(then: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            then?()
        })
    }

    var isShown: Bool { isVisible && alphaValue > 0.01 }

    func toggle() {
        if isShown { fadeOut() } else { alphaValue = 0; fadeIn() }
    }
}
