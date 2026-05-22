import AppKit
import AVFoundation
import SwiftUI

@main
struct DigestAnnouncerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, AVSpeechSynthesizerDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let synthesizer = AVSpeechSynthesizer()
    private var hostingController: NSHostingController<PopoverView>!
    private var state: PopoverView.LoadState = .loading {
        didSet { rebuildPopoverContent() }
    }
    private var isSpeaking: Bool = false {
        didSet { rebuildPopoverContent() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        synthesizer.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = menuBarImage()
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 320)
        popover.behavior = .transient
        popover.delegate = self
        hostingController = NSHostingController(rootView: makeView())
        popover.contentViewController = hostingController
    }

    private func menuBarImage() -> NSImage {
        for ext in ["svg", "png"] {
            if let path = Bundle.main.path(forResource: "MenuBarIcon", ofType: ext),
               let img = NSImage(contentsOfFile: path) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = (ext == "svg")
                img.accessibilityDescription = "Steady Digest"
                return img
            }
        }
        return NSImage(systemSymbolName: "newspaper", accessibilityDescription: "Steady Digest")
            ?? NSImage()
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        state = .loading
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        fetchAndAnnounce()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(menuRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Set Token…", action: #selector(menuSetToken), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        let toggleSpeechItem = NSMenuItem(title: speechEnabled ? "Disable Speech" : "Enable Speech",
                                          action: #selector(menuToggleSpeech), keyEquivalent: "")
        menu.addItem(toggleSpeechItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items { item.target = self.responderFor(item) }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu after a tick so left-click goes back to popover behavior
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func responderFor(_ item: NSMenuItem) -> AnyObject? {
        if item.action == #selector(NSApplication.terminate(_:)) { return NSApp }
        return self
    }

    // MARK: - Menu actions

    @objc private func menuRefresh() {
        togglePopoverIfClosed()
        fetchAndAnnounce()
    }

    @objc private func menuSetToken() {
        promptForToken()
    }

    @objc private func menuToggleSpeech() {
        speechEnabled.toggle()
        if !speechEnabled { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func togglePopoverIfClosed() {
        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        state = .loading
    }

    // MARK: - Settings

    private var speechEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "SpeechEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "SpeechEnabled") }
    }

    private func promptForToken() {
        let alert = NSAlert()
        alert.messageText = "Steady access token"
        alert.informativeText = "Paste a personal access token from runsteady.com. It will be stored in this app's UserDefaults."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = TokenStore.token ?? ""
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            TokenStore.token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Fetch + speak

    private func fetchAndAnnounce() {
        if TokenStore.token == nil || TokenStore.token?.isEmpty == true {
            state = .error("No access token set. Right-click the menu bar icon → Set Token…")
            return
        }

        let client = DigestClient(tokenProvider: { TokenStore.token })
        client.fetchLatest { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let entry):
                    self.state = .entry(entry)
                    if self.speechEnabled {
                        self.speak(entry)
                    }
                case .failure(let err):
                    self.state = .error(err.errorDescription ?? "Unknown error")
                }
            }
        }
    }

    private func speak(_ entry: DigestEntry) {
        synthesizer.stopSpeaking(at: .immediate)
        let parts: [String] = [
            entry.resource?.person?.name.map { "\($0) reports:" },
            entry.resource?.title,
            entry.resource?.body.map(stripMarkdown),
        ].compactMap { $0 }
        let text = parts.joined(separator: ". ")
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func stripMarkdown(_ s: String) -> String {
        var out = s
        // [text](url) → text
        let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#)
        out = link.stringByReplacingMatches(
            in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1"
        )
        let lines = out.split(whereSeparator: \.isNewline).map { line -> String in
            var l = line.trimmingCharacters(in: .whitespaces)
            for p in ["- ", "* ", "+ "] where l.hasPrefix(p) { l = String(l.dropFirst(p.count)) }
            return l
        }
        return lines.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - View binding

    private func rebuildPopoverContent() {
        hostingController.rootView = makeView()
    }

    private func makeView() -> PopoverView {
        PopoverView(
            state: state,
            onRefresh: { [weak self] in self?.fetchAndAnnounce() },
            onStopSpeaking: { [weak self] in
                self?.synthesizer.stopSpeaking(at: .immediate)
                self?.isSpeaking = false
            },
            onOpenURL: { url in NSWorkspace.shared.open(url) },
            isSpeaking: isSpeaking
        )
    }
}
