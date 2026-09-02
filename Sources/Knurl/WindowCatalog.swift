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
    fileprivate var element: AXUIElement

    static func == (lhs: DeskWindow, rhs: DeskWindow) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.title == rhs.title
    }
}

@MainActor
@Observable
final class WindowCatalog {
    var enabled = Preferences.windowManagerEnabled
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var displays: [DeskDisplay] = []
    private(set) var windows: [DeskWindow] = []
    private var lastArrangement: [(element: AXUIElement, frame: CGRect)] = []
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
        windows = Self.scan(displays: displays, primaryHeight: Self.primaryHeight)
        if selectedID == nil || windows.contains(where: { $0.id == selectedID }) == false {
            selectedID = windows.first?.id
        }
    }

    func move(_ id: String, to frame: CGRect) {
        guard enabled, trusted, let window = windows.first(where: { $0.id == id }) else { return }
        rememberIfNeeded()
        Self.setFrame(window.element, appKit: frame, primaryHeight: Self.primaryHeight)
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
        let target = display
            ?? self.display(for: selected)
            ?? self.display(for: windows.first)
            ?? displays.first
        guard let target else { return }
        rememberIfNeeded()
        let ordered = orderedWindows(on: target)
        let frames = WorkspaceMath.frames(for: preset, visible: target.visible, count: ordered.count)
        for (window, frame) in zip(ordered, frames) where frame != .null {
            Self.setFrame(window.element, appKit: frame, primaryHeight: Self.primaryHeight)
        }
        lastPreset = preset
        refresh()
    }

    func restore() {
        guard !lastArrangement.isEmpty else { return }
        for item in lastArrangement {
            Self.setFrame(item.element, appKit: item.frame, primaryHeight: Self.primaryHeight)
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

    func display(for window: DeskWindow?) -> DeskDisplay? {
        guard let window else { return nil }
        return displays.first { $0.id == window.displayID } ?? displays.first
    }

    private func orderedWindows(on display: DeskDisplay) -> [DeskWindow] {
        var pool = windows.filter { $0.displayID == display.id }
        if pool.isEmpty { pool = windows }
        if let selected, let index = pool.firstIndex(where: { $0.id == selected.id }) {
            pool.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
        return pool
    }

    private func rememberIfNeeded() {
        if lastArrangement.isEmpty {
            lastArrangement = windows.map { ($0.element, $0.frame) }
        }
    }

    private func displayID(containing frame: CGRect) -> String {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.visible.contains(point) || $0.frame.contains(point) }?.id
            ?? displays.first?.id
            ?? "display-0"
    }

    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func scan(displays: [DeskDisplay], primaryHeight: CGFloat) -> [DeskWindow] {
        var result: [DeskWindow] = []
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != selfPID }
            .sorted { lhs, rhs in
                if lhs.processIdentifier == frontPID { return true }
                if rhs.processIdentifier == frontPID { return false }
                return (lhs.localizedName ?? "") < (rhs.localizedName ?? "")
            }
        for app in apps {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let axWindows = value as? [AXUIElement]
            else { continue }
            for window in axWindows {
                guard isStandard(window),
                      let axFrame = axFrame(of: window)
                else { continue }
                let frame = WorkspaceMath.appKitFrame(from: axFrame, primaryHeight: primaryHeight)
                let title = string(window, kAXTitleAttribute as CFString) ?? ""
                let point = CGPoint(x: frame.midX, y: frame.midY)
                let display = displays.first { $0.visible.contains(point) || $0.frame.contains(point) }
                    ?? displays.first
                result.append(
                    DeskWindow(
                        id: identity(pid: app.processIdentifier, element: window),
                        pid: app.processIdentifier,
                        appName: app.localizedName ?? "App",
                        title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                        frame: frame,
                        displayID: display?.id ?? "display-0",
                        element: window
                    )
                )
            }
        }
        return result
    }

    private static func setFrame(_ element: AXUIElement, appKit: CGRect, primaryHeight: CGFloat) {
        let ax = WorkspaceMath.axFrame(from: appKit, primaryHeight: primaryHeight)
        var origin = ax.origin
        var size = ax.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        }
        if let axSize = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axSize)
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private static func identity(pid: pid_t, element: AXUIElement) -> String {
        if let identifier = string(element, kAXIdentifierAttribute as CFString), !identifier.isEmpty {
            return "\(pid).id.\(identifier)"
        }
        let pointer = Unmanaged.passUnretained(element).toOpaque()
        return "\(pid).ax.\(Int(bitPattern: pointer))"
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        let role = string(window, kAXRoleAttribute as CFString)
        guard role == kAXWindowRole as String else { return false }
        if let subrole = string(window, kAXSubroleAttribute as CFString) {
            return subrole == kAXStandardWindowSubrole as String
        }
        return true
    }

    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        let position = unsafeBitCast(positionValue, to: AXValue.self)
        let axSize = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(axSize, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
