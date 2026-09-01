import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics
import KnurlCore

/// Built-in brightness. IODisplayConnect is gone on Apple Silicon, so the live
/// path is DisplayServices (same service the keyboard keys use). Loaded by
/// symbol so we do not link the private framework.
enum DisplayBrightness {
    private static let estimateKey = "knurl.brightness.estimate"

    static var estimate: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: estimateKey) as? Double
            return DialMath.clampVolume(stored ?? read() ?? 0.7)
        }
        set {
            UserDefaults.standard.set(DialMath.clampVolume(newValue), forKey: estimateKey)
        }
    }

    static func read() -> Double? {
        if let id = builtinDisplay(), let get = Symbols.get {
            var value: Float = 0
            if get(id, &value) == 0 {
                return DialMath.clampVolume(Double(value))
            }
        }
        if let io = ioRead(), io > 0.02 { return io }
        return nil
    }

    @discardableResult
    static func set(_ value: Double) -> Bool {
        let clamped = Float(DialMath.clampVolume(value))
        if let id = builtinDisplay(), let set = Symbols.set, set(id, clamped) == 0 {
            estimate = Double(clamped)
            return true
        }
        if ioSet(clamped) {
            estimate = Double(clamped)
            return true
        }
        return false
    }

    static func step(_ detents: Int) {
        guard detents != 0 else { return }
        if set(DialMath.steppedVolume(current: read() ?? estimate, detents: detents)) {
            return
        }
        for _ in 0 ..< abs(detents) {
            if detents > 0 { HardwareKeys.brightnessUp() } else { HardwareKeys.brightnessDown() }
        }
        estimate = DialMath.steppedVolume(current: estimate, detents: detents)
    }

    static func watch() {
        guard let id = builtinDisplay(), let register = Symbols.register else { return }
        _ = register(id, 1, knurlBrightnessChanged)
    }

    static func unwatch() {
        if let id = builtinDisplay(), let unregister = Symbols.unregister {
            _ = unregister(id, 1)
        }
    }

    private static func builtinDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayIsBuiltin($0) != 0 } ?? ids.first
    }

    private static func ioRead() -> Double? {
        forEachDisplay { service in
            var brightness: Float = 0
            let status = IODisplayGetFloatParameter(service, 0, "brightness" as CFString, &brightness)
            return status == KERN_SUCCESS ? Double(brightness) : nil
        }
    }

    private static func ioSet(_ value: Float) -> Bool {
        forEachDisplay { service in
            let status = IODisplaySetFloatParameter(service, 0, "brightness" as CFString, value)
            return status == KERN_SUCCESS ? true : nil
        } ?? false
    }

    private static func forEachDisplay<T>(_ work: (io_service_t) -> T?) -> T? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let value = work(service) { return value }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private enum Symbols {
        nonisolated(unsafe) static let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        )

        nonisolated(unsafe) static let get = load(Get.self, "DisplayServicesGetBrightness")
        nonisolated(unsafe) static let set = load(Set.self, "DisplayServicesSetBrightness")
        nonisolated(unsafe) static let register = load(Register.self, "DisplayServicesRegisterForBrightnessChangeNotifications")
        nonisolated(unsafe) static let unregister = load(Unregister.self, "DisplayServicesUnregisterForBrightnessChangeNotifications")

        private static func load<T>(_ type: T.Type, _ name: String) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }

        typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
        typealias Register = @convention(c) (CGDirectDisplayID, UInt32, Change) -> Int32
        typealias Unregister = @convention(c) (CGDirectDisplayID, UInt32) -> Int32
        typealias Change = @convention(c) (
            UnsafeMutableRawPointer?,
            CGDirectDisplayID,
            UnsafeMutableRawPointer?,
            UnsafeRawPointer?,
            UnsafeRawPointer?
        ) -> Void
    }
}

private func knurlBrightnessChanged(
    _ passthrough: UnsafeMutableRawPointer?,
    _ display: CGDirectDisplayID,
    _ name: UnsafeMutableRawPointer?,
    _ sender: UnsafeRawPointer?,
    _ info: UnsafeRawPointer?
) {
    _ = passthrough
    _ = display
    _ = name
    _ = sender
    _ = info
    Task { @MainActor in
        AppDelegate.shared?.state.adoptSystemMeters()
    }
}
