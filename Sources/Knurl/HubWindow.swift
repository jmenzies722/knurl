import AppKit
import Carbon.HIToolbox
import KnurlCore
import SwiftUI

final class HubPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.hideHub()
    }

    override func keyDown(with event: NSEvent) {
        if knurlNavigationKey(event) { super.keyDown(with: event); return }
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

/// Keys the Hub hands to the responder chain instead of the dial: whatever has
/// focus (sidebar list, crown) decides, which is how AppKit expects it to work.
func knurlNavigationKey(_ event: NSEvent) -> Bool {
    switch Int(event.keyCode) {
    case kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow, kVK_Tab: true
    default: false
    }
}

final class HubHostingView<Content: View>: NSHostingView<Content> {
    override func keyDown(with event: NSEvent) {
        if knurlNavigationKey(event) { super.keyDown(with: event); return }
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class HubWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = HubWindow()

    private var window: HubPanel?
    private var escapeMonitor: Any?
    private let musicID = NSToolbarItem.Identifier("knurl.music")

    private override init() {
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }

    // SwiftUI's sidebar list swallows Escape before it reaches the responder
    // chain, so the Hub watches for it ahead of the chain instead.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isEmpty else { return event }
            if AppDelegate.shared?.state.voice.isActive == true {
                AppDelegate.shared?.state.cancelTalk()
                return nil
            }
            if AppDelegate.shared?.state.wantsSettings == true {
                AppDelegate.shared?.state.dismissSettings()
                return nil
            }
            guard let self, let window = self.window else { return event }
            guard event.window === window || NSApp.keyWindow === window else { return event }
            AppDelegate.shared?.state.hideHub()
            return nil
        }
    }

    func attach(_ state: DialState, agents: AgentSessionManager) {
        installEscapeMonitor()
        let window = ensure()
        window.contentView = HubHostingView(rootView: HubView(state: state, agents: agents))
    }

    func show() {
        let window = ensure()
        installEscapeMonitor()
        restoreFrame(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        AppDelegate.shared?.state.hubVisible = true
    }

    func hide() {
        persistFrame()
        window?.orderOut(nil)
        AppDelegate.shared?.state.hubVisible = false
    }

    func resignKey() {
        window?.resignKey()
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }

    func windowWillClose(_ notification: Notification) {
        persistFrame()
        AppDelegate.shared?.state.hubVisible = false
        AppDelegate.shared?.state.noteHubClosed()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, musicID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, musicID]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case musicID:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Open Music"
            item.paletteLabel = "Open Music"
            item.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Open Music")
            item.target = self
            item.action = #selector(openMusic)
            return item
        default:
            return nil
        }
    }

    @objc private func openMusic() {
        AppDelegate.shared?.state.revealMusic()
    }

    private func ensure() -> HubPanel {
        if let window { return window }
        let created = HubPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = "Knurl"
        created.minSize = NSSize(width: 1040, height: 720)
        created.isReleasedWhenClosed = false
        created.titlebarAppearsTransparent = true
        created.titleVisibility = .hidden
        created.titlebarSeparatorStyle = .none
        // The Hub paints its own field edge to edge, so the window must not
        // paint one first — a stock window background shows as a pale band
        // behind the rail for the first frame of every resize.
        created.backgroundColor = NSColor(name: nil) { appearance in
            appearance.isDarkDesk ? KnurlPalette.hex(0x18181B) : KnurlPalette.hex(0xF2F3F6)
        }
        created.isOpaque = true
        created.delegate = self
        restoreFrame(created)
        window = created
        return created
    }

    private func restoreFrame(_ window: HubPanel) {
        guard let frame = Preferences.hubFrame, frame.width >= 1040, frame.height >= 720 else {
            if window.frame.origin == .zero {
                window.center()
            }
            return
        }
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if visible {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
    }

    private func persistFrame() {
        guard let window, window.isVisible else { return }
        Preferences.hubFrame = window.frame
    }
}
