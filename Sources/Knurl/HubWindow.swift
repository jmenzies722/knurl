import AppKit
import SwiftUI

final class HubPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.hideHub()
    }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

final class HubHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class HubWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = HubWindow()

    private var window: HubPanel?
    private let musicID = NSToolbarItem.Identifier("knurl.music")
    private let settingsID = NSToolbarItem.Identifier("knurl.settings")

    private override init() {
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }

    func attach(_ state: DialState) {
        let window = ensure()
        window.contentView = HubHostingView(rootView: HubView(state: state))
    }

    func show() {
        let window = ensure()
        restoreFrame(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
    }

    func hide() {
        persistFrame()
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }

    func windowWillClose(_ notification: Notification) {
        persistFrame()
        AppDelegate.shared?.state.noteHubClosed()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, musicID, settingsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, musicID, settingsID]
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
        case settingsID:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(openSettings)
            return item
        default:
            return nil
        }
    }

    @objc private func openMusic() {
        AppDelegate.shared?.state.revealMusic()
    }

    @objc private func openSettings() {
        AppDelegate.shared?.openSettings()
    }

    private func ensure() -> HubPanel {
        if let window { return window }
        let created = HubPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        created.title = "Knurl"
        created.minSize = NSSize(width: 980, height: 700)
        created.isReleasedWhenClosed = false
        created.titlebarAppearsTransparent = true
        created.titleVisibility = .visible
        created.titlebarSeparatorStyle = .none
        created.backgroundColor = NSColor.windowBackgroundColor
        created.delegate = self
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("KnurlHub"))
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        created.toolbar = toolbar
        created.toolbarStyle = .unified
        restoreFrame(created)
        window = created
        return created
    }

    private func restoreFrame(_ window: HubPanel) {
        guard let frame = Preferences.hubFrame, frame.width >= 960, frame.height >= 680 else {
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
