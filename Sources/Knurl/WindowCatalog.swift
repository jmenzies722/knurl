import AppKit
import ApplicationServices
import KnurlCore
import Observation

struct DeskDisplay: Identifiable, Equatable {
    var id: String
    var name: String
    var frame: CGRect
    var visible: CGRect
}

struct DeskWindow: Identifiable, Equatable {
    var id: String
    var pid: pid_t
    var appName: String
    var title: String
    var frame: CGRect
    var displayID: String
}

@MainActor
@Observable
final class WindowCatalog {
    var enabled = Preferences.windowManagerEnabled
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var displays: [DeskDisplay] = []
    private(set) var windows: [DeskWindow] = []
    private(set) var lastArrangement: [String: CGRect] = [:]
    private(set) var lastPreset: WorkspacePreset?
    var selectedID: String?
    var status: String?

    func setEnabled(_ on: Bool) {
        enabled = on
        Preferences.windowManagerEnabled = on
        if on {
            trusted = AXIsProcessTrustedWithOptions(
                ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            )
            if trusted {
                refresh()
                status = nil
            } else {
                status = "Allow Knurl in System Settings → Privacy & Security → Accessibility."
            }
        } else {
            windows = []
            status = nil
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        displays = NSScreen.screens.enumerated().map { index, screen in
            DeskDisplay(
                id: "display-\(index)",
                name: screen.localizedName,
                frame: screen.frame,
                visible: screen.visibleFrame
            )
        }
        guard enabled else {
            windows = []
            trusted = AXIsProcessTrusted()
            return
        }
        trusted = AXIsProcessTrusted()
        guard trusted else {
            windows = []
            return
        }
        windows = Self.scan(displays: displays)
        if selectedID == nil {
            selectedID = windows.first?.id
        }
    }

    func move(_ id: String, to frame: CGRect) {
        guard enabled, trusted, let window = windows.first(where: { $0.id == id }) else { return }
        rememberIfNeeded()
        Self.apply(pid: window.pid, title: window.title, frame: frame)
        if let index = windows.firstIndex(where: { $0.id == id }) {
            windows[index].frame = frame
            windows[index].displayID = displayID(containing: frame)
        }
    }

    func snap(_ zone: SnapZone) {
        guard let window = selected ?? windows.first else { return }
        let visible = display(for: window)?.visible ?? NSScreen.main?.visibleFrame ?? .zero
        move(window.id, to: WorkspaceMath.snap(zone, in: visible))
    }

    func apply(_ preset: WorkspacePreset, on display: DeskDisplay? = nil) {
        refresh()
        let target = display ?? displays.first
        guard let target else { return }
        rememberIfNeeded()
        let candidates = windows.filter { $0.displayID == target.id }
        let ordered = candidates.isEmpty ? windows : candidates
        let frames = WorkspaceMath.frames(for: preset, visible: target.visible, count: ordered.count)
        for (window, frame) in zip(ordered, frames) where frame != .null {
            Self.apply(pid: window.pid, title: window.title, frame: frame)
        }
        lastPreset = preset
        refresh()
    }

    func restore() {
        guard !lastArrangement.isEmpty else { return }
        for window in windows {
            if let frame = lastArrangement[window.id] {
                Self.apply(pid: window.pid, title: window.title, frame: frame)
            }
        }
        lastPreset = nil
        refresh()
    }

    func moveSelected(to display: DeskDisplay) {
        guard let window = selected else { return }
        var frame = window.frame
        frame.origin.x = display.visible.minX + 24
        frame.origin.y = display.visible.minY + 24
        frame.size.width = min(frame.width, display.visible.width - 48)
        frame.size.height = min(frame.height, display.visible.height - 48)
        move(window.id, to: frame)
    }

    var selected: DeskWindow? {
        windows.first { $0.id == selectedID } ?? windows.first
    }

    func display(for window: DeskWindow) -> DeskDisplay? {
        displays.first { $0.id == window.displayID } ?? displays.first
    }

    private func rememberIfNeeded() {
        if lastArrangement.isEmpty {
            lastArrangement = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        }
    }

    private func displayID(containing frame: CGRect) -> String {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.visible.contains(point) || $0.frame.contains(point) }?.id
            ?? displays.first?.id
            ?? "display-0"
    }

    private static func scan(displays: [DeskDisplay]) -> [DeskWindow] {
        var result: [DeskWindow] = []
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
        for app in apps {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement]
            else { continue }
            for (index, window) in windows.enumerated() {
                guard isStandard(window),
                      let frame = frame(of: window)
                else { continue }
                let title = string(window, kAXTitleAttribute as CFString) ?? ""
                let point = CGPoint(x: frame.midX, y: frame.midY)
                let display = displays.first { $0.visible.contains(point) || $0.frame.contains(point) }
                    ?? displays.first
                result.append(
                    DeskWindow(
                        id: "\(app.processIdentifier).\(index).\(title)",
                        pid: app.processIdentifier,
                        appName: app.localizedName ?? "App",
                        title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                        frame: frame,
                        displayID: display?.id ?? "display-0"
                    )
                )
            }
        }
        return result
    }

    private static func apply(pid: pid_t, title: String, frame: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return }
        let match = windows.first { string($0, kAXTitleAttribute as CFString) == title } ?? windows.first
        guard let match else { return }
        var origin = frame.origin
        var size = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(match, kAXPositionAttribute as CFString, position)
        }
        if let axSize = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(match, kAXSizeAttribute as CFString, axSize)
        }
        AXUIElementPerformAction(match, kAXRaiseAction as CFString)
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        let role = string(window, kAXRoleAttribute as CFString)
        guard role == kAXWindowRole as String else { return false }
        if let subrole = string(window, kAXSubroleAttribute as CFString) {
            return subrole == kAXStandardWindowSubrole as String
        }
        return true
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
