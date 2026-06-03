import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IntentionsModel()
    private let client = SteadyClient()
    private var window: DesktopWindow!
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?

    private let pollInterval: TimeInterval = 180  // 3 minutes; cheap thanks to ETag

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = DesktopWindow(model: model)
        window.alphaValue = 0
        window.fadeIn()

        setUpStatusItem()
        installEditMenu()

        // Refresh after the Mac wakes from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshNow),
            name: NSWorkspace.didWakeNotification, object: nil)

        startPolling()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = menuBarImage()
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide", action: #selector(toggleWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Now", action: #selector(forceRefresh), keyEquivalent: "r")
        menu.addItem(buildPositionItem())
        menu.addItem(buildTextSizeItem())
        menu.addItem(withTitle: "Text Color…", action: #selector(pickColor), keyEquivalent: "")
        menu.addItem(withTitle: "Set Token…", action: #selector(setToken), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Steady Intentions", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    /// As a menu-bar agent we have no menu bar, but NSApplication still routes
    /// key equivalents (⌘C/⌘V/⌘X/⌘A) through the main menu — without it, paste
    /// into the token field does nothing. This installs a standard Edit menu.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleWindow() { window.toggle() }

    /// Loads the bundled SVG menu-bar icon as a template image (so AppKit
    /// tints it for light / dark / highlighted states). Falls back to an SF
    /// Symbol if the file is missing — useful when running via `swift run`.
    private func menuBarImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Steady Intentions"
            return image
        }
        return NSImage(systemSymbolName: "checklist", accessibilityDescription: "Steady Intentions")
    }

    private func buildPositionItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Position")
        for corner in WindowCorner.allCases {
            let child = NSMenuItem(title: corner.menuTitle,
                                   action: #selector(setCorner(_:)),
                                   keyEquivalent: "")
            child.target = self
            child.representedObject = corner.rawValue
            child.state = (corner == window.corner) ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    @objc private func setCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = WindowCorner(rawValue: raw) else { return }
        window.corner = corner
        CornerStore.save(corner)
        window.refreshLayout()
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    private func buildTextSizeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Text Size")
        for size in TextSize.allCases {
            let child = NSMenuItem(title: size.menuTitle,
                                   action: #selector(setTextSize(_:)),
                                   keyEquivalent: "")
            child.target = self
            child.representedObject = size.rawValue
            child.state = (size == model.textSize) ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    @objc private func setTextSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = TextSize(rawValue: raw) else { return }
        model.textSize = size
        TextSizeStore.save(size)
        window.refreshLayout()
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    @objc private func pickColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = model.nsTextColor
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        model.nsTextColor = sender.color
        ColorStore.save(sender.color)
        window.refreshLayout()
    }

    @objc private func setToken() {
        let alert = NSAlert()
        alert.messageText = "Steady Personal Access Token"
        alert.informativeText = "Paste a token that starts with steady_pat_. Stored securely in your Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "steady_pat_…"
        field.stringValue = Keychain.token ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Keychain.token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            model.hasToken = Keychain.token?.isEmpty == false
            model.errorText = nil
            forceRefresh()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        refreshNow()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    @objc private func refreshNow() {
        Task { await poll(force: false) }
    }

    @objc private func forceRefresh() {
        Task { await poll(force: true) }
    }

    private func poll(force: Bool) async {
        if force { await client.invalidate() }
        let result = await client.poll()
        switch result {
        case .unchanged:
            break
        case .updated(let day):
            let changed = day != model.day
            model.day = day
            model.errorText = nil
            model.lastUpdated = Date()
            if changed { window.refreshLayout() }
        case .failure(let error):
            if case SteadyError.missingToken = error {
                model.hasToken = false
            } else {
                model.errorText = error.localizedDescription
            }
            window.refreshLayout()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon
    app.run()
}
