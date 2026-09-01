import AppKit
import KnurlCore
import SwiftUI

@MainActor
final class StatusBar {
    static let shared = StatusBar()

    private var item: NSStatusItem?
    private var menu: NSMenu?
    private var lastTitle = ""

    private init() {}

    func attach(target: AnyObject, show: Selector, hub: Selector, settings: Selector, quit: Selector) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = crownImage()
            button.imagePosition = .imageOnly
            button.target = target
            button.action = #selector(AppDelegate.statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Knurl"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Knurl  \(HotkeyCenter.shared.chord)", action: show, keyEquivalent: "d")
        menu.addItem(withTitle: "Open Hub", action: hub, keyEquivalent: "h")
        menu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Knurl", action: quit, keyEquivalent: "q")
        menu.items.forEach { $0.target = target }
        self.item = item
        self.menu = menu
        applyCrown()
    }

    func handleClick() {
        guard let event = NSApp.currentEvent else {
            AppDelegate.shared?.state.summonFromMenuBar()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            item?.menu = menu
            item?.button?.performClick(nil)
            item?.menu = nil
            return
        }
        AppDelegate.shared?.state.summonFromMenuBar()
    }

    func refresh(_ state: DialState) {
        if let cover = state.music.cover, state.music.hasTrack {
            if state.music.title != lastTitle {
                lastTitle = state.music.title
            }
            item?.button?.image = rounded(cover)
            item?.button?.image?.isTemplate = false
            item?.button?.toolTip = [state.music.title, state.music.artist]
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
        } else {
            lastTitle = ""
            applyCrown()
        }
    }

    private func applyCrown() {
        item?.button?.image = crownImage()
        item?.button?.image?.isTemplate = true
        item?.button?.toolTip = "Knurl"
    }

    private func crownImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "dial.medium", accessibilityDescription: "Knurl")
        image?.isTemplate = true
        return image
    }

    private func rounded(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 18, height: 18)
        return copy
    }
}
