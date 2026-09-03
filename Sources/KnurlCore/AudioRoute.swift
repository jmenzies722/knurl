#if os(macOS)
import CoreAudio
import Foundation

public enum AudioTransport: String, Sendable, Equatable, Hashable {
    case builtIn
    case bluetooth
    case airPlay
    case hdmi
    case displayPort
    case usb
    case thunderbolt
    case virtual
    case unknown

    public var title: String {
        switch self {
        case .builtIn: "Built-in"
        case .bluetooth: "Bluetooth"
        case .airPlay: "AirPlay"
        case .hdmi: "HDMI"
        case .displayPort: "Display"
        case .usb: "USB"
        case .thunderbolt: "Thunderbolt"
        case .virtual: "Virtual"
        case .unknown: "Output"
        }
    }

    public var symbol: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "headphones"
        case .airPlay: "homepod.fill"
        case .hdmi, .displayPort: "tv"
        case .usb, .thunderbolt: "hifispeaker.fill"
        case .virtual: "waveform"
        case .unknown: "speaker.wave.2.fill"
        }
    }

    public static func from(_ code: UInt32) -> AudioTransport {
        switch code {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: .virtual
        default: .unknown
        }
    }
}

public struct AudioDevice: Sendable, Equatable, Identifiable {
    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var transport: AudioTransport

    public init(id: AudioDeviceID, uid: String, name: String, transport: AudioTransport = .unknown) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}

public struct AudioOutputs: Sendable {
    public init() {}

    public func devices() -> [AudioDevice] {
        var seen = Set<String>()
        var list: [AudioDevice] = []
        for id in allDeviceIDs() {
            guard let device = outputDevice(id), seen.insert(device.uid).inserted else { continue }
            list.append(device)
        }
        if let current, seen.insert(current.uid).inserted {
            list.append(current)
        }
        return Self.ranked(list)
    }

    /// Live Core Audio devices plus HomePods the user has already used.
    public static func roster(_ live: [AudioDevice], remembered: [AirPlayDestination]) -> [AudioDevice] {
        var list = live
        var seen = Set(list.map(\.uid))
        for dest in remembered where seen.insert(dest.uid).inserted {
            list.append(AudioDevice(id: 0, uid: dest.uid, name: dest.name, transport: .airPlay))
        }
        return ranked(list)
    }

    public static func isAirPlayNamed(_ name: String) -> Bool {
        let folded = name.lowercased()
        return folded.contains("airplay") || folded.contains("homepod")
    }

    /// Bluetooth and AirPlay first so the Output crown lands on AirPods / HomePods.
    public static func ranked(_ devices: [AudioDevice]) -> [AudioDevice] {
        let order: [AudioTransport] = [
            .bluetooth, .airPlay, .builtIn, .hdmi, .displayPort, .usb, .thunderbolt, .virtual, .unknown,
        ]
        return devices.sorted { a, b in
            let left = order.firstIndex(of: a.transport) ?? order.count
            let right = order.firstIndex(of: b.transport) ?? order.count
            if left != right { return left < right }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public var current: AudioDevice? {
        let id = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard id != kAudioObjectUnknown else { return nil }
        let named = name(of: id) ?? "Output"
        let transport = AudioTransport.from(transportType(id))
        return AudioDevice(
            id: id,
            uid: uid(of: id) ?? "id-\(id)",
            name: named,
            transport: transport == .airPlay || Self.isAirPlayNamed(named) ? .airPlay : transport
        )
    }

    @discardableResult
    public func select(_ device: AudioDevice) -> Bool {
        if let resolved = deviceID(forUID: device.uid) {
            return select(resolved)
        }
        guard device.id != 0, device.id != kAudioObjectUnknown else { return false }
        return select(device.id)
    }

    @discardableResult
    public func select(_ id: AudioDeviceID) -> Bool {
        guard id != kAudioObjectUnknown else { return false }
        let outputOK = setDefault(kAudioHardwarePropertyDefaultOutputDevice, id)
        let systemOK = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, id)
        let now = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        if now == id { return true }
        // AirPlay often remaps onto a sibling device after the set succeeds.
        if outputOK || systemOK, let current, current.uid == uid(of: id) {
            return true
        }
        return false
    }

    private func outputDevice(_ id: AudioDeviceID) -> AudioDevice? {
        let transport = AudioTransport.from(transportType(id))
        let named = name(of: id) ?? ""
        let airPlay = transport == .airPlay || Self.isAirPlayNamed(named)
        if !isAlive(id), !airPlay { return nil }
        if channelCount(id, scope: kAudioDevicePropertyScopeOutput) == 0, !airPlay {
            return nil
        }
        if transport == .virtual, !airPlay { return nil }
        let defaultable =
            canBeDefault(id, scope: kAudioDevicePropertyScopeOutput)
            || canBeDefaultSystem(id)
        if !defaultable, transport != .bluetooth, !airPlay {
            return nil
        }
        return AudioDevice(
            id: id,
            uid: uid(of: id) ?? "id-\(id)",
            name: named.isEmpty ? "Output \(id)" : named,
            transport: airPlay ? .airPlay : transport
        )
    }

    public func cycle(by delta: Int) {
        let list = devices()
        guard !list.isEmpty else { return }
        let currentID = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let index = list.firstIndex(where: { $0.id == currentID }) ?? 0
        let count = list.count
        let next = ((index + delta) % count + count) % count
        select(list[next])
    }
}

public struct AudioInputs: Sendable {
    public init() {}

    public func devices() -> [AudioDevice] {
        allDeviceIDs().compactMap { id in
            guard isAlive(id),
                  canBeDefault(id, scope: kAudioDevicePropertyScopeInput),
                  channelCount(id, scope: kAudioDevicePropertyScopeInput) > 0
            else { return nil }
            return AudioDevice(
                id: id,
                uid: uid(of: id) ?? "id-\(id)",
                name: name(of: id) ?? "Input \(id)",
                transport: AudioTransport.from(transportType(id))
            )
        }
    }

    public var current: AudioDevice? {
        let id = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard id != kAudioObjectUnknown else { return nil }
        return AudioDevice(
            id: id,
            uid: uid(of: id) ?? "id-\(id)",
            name: name(of: id) ?? "Mic",
            transport: AudioTransport.from(transportType(id))
        )
    }

    public func select(_ id: AudioDeviceID) {
        setDefault(kAudioHardwarePropertyDefaultInputDevice, id)
    }

    public func cycle(by delta: Int) {
        let list = devices()
        guard !list.isEmpty else { return }
        let currentID = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let index = list.firstIndex(where: { $0.id == currentID }) ?? 0
        let count = list.count
        let next = ((index + delta) % count + count) % count
        select(list[next].id)
    }
}

public struct InputGain: Sendable {
    public init() {}

    public var level: Float {
        get { readScalar() ?? 0 }
        nonmutating set { writeScalar(min(1, max(0, newValue))) }
    }

    public var isMuted: Bool {
        get { readMute() }
        nonmutating set { writeMute(newValue) }
    }

    public var hasDevice: Bool {
        defaultDevice(kAudioHardwarePropertyDefaultInputDevice) != kAudioObjectUnknown
    }

    /// Built-in mics often have a volume scalar. USB / virtual inputs often
    /// do not — reading those as 0 made the Mic ring snap dead.
    public var hasScalar: Bool { readScalar() != nil }

    public var deviceName: String {
        let id = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        return name(of: id) ?? "Mic"
    }

    private func readScalar() -> Float? {
        let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard device != kAudioObjectUnknown else { return nil }
        if let main = readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return main
        }
        let left = readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: 1)
        let right = readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: 2)
        switch (left, right) {
        case let (l?, r?): return (l + r) / 2
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    private func writeScalar(_ value: Float) {
        let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard device != kAudioObjectUnknown else { return }
        writeFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain, value: value)
        writeFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: 1, value: value)
        writeFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: 2, value: value)
    }

    private func readMute() -> Bool {
        let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard device != kAudioObjectUnknown else { return false }
        return readUInt(device, selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain) == 1
            || readUInt(device, selector: kAudioDevicePropertyMute, element: 1) == 1
    }

    private func writeMute(_ muted: Bool) {
        let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard device != kAudioObjectUnknown else { return }
        writeUInt(device, selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain, value: muted ? 1 : 0)
        writeUInt(device, selector: kAudioDevicePropertyMute, element: 1, value: muted ? 1 : 0)
        writeUInt(device, selector: kAudioDevicePropertyMute, element: 2, value: muted ? 1 : 0)
    }

    private func readFloat(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func writeFloat(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        value: Float
    ) {
        var next = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &next)
    }

    private func readUInt(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func writeUInt(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        value: UInt32
    ) {
        var next = value
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &next)
    }
}

private func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &device
    )
    return status == noErr ? device : kAudioObjectUnknown
}

@discardableResult
private func setDefault(_ selector: AudioObjectPropertySelector, _ device: AudioDeviceID) -> Bool {
    var next = device
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        size,
        &next
    ) == noErr
}

private func deviceID(forUID uid: String) -> AudioDeviceID? {
    var identifier = uid as CFString
    var id = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = withUnsafePointer(to: &identifier) { qualifier in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<CFString>.size),
            qualifier,
            &size,
            &id
        )
    }
    guard status == noErr, id != kAudioObjectUnknown else { return nil }
    return id
}

private func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size
    ) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &devices
    )
    return status == noErr ? devices.filter { $0 != kAudioObjectUnknown } : []
}

private func uid(of id: AudioDeviceID) -> String? {
    stringProperty(id, kAudioDevicePropertyDeviceUID)
}

private func name(of id: AudioDeviceID) -> String? {
    stringProperty(id, kAudioObjectPropertyName)
}

private func transportType(_ id: AudioDeviceID) -> UInt32 {
    uintProperty(id, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal) ?? 0
}

private func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    guard id != kAudioObjectUnknown else { return nil }
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) { pointer in
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
    }
    return status == noErr ? (name as String) : nil
}

private func isAlive(_ id: AudioDeviceID) -> Bool {
    uintProperty(id, kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal) == 1
}

private func canBeDefault(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    uintProperty(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: scope) == 1
}

private func canBeDefaultSystem(_ id: AudioDeviceID) -> Bool {
    uintProperty(
        id,
        kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
        scope: kAudioDevicePropertyScopeOutput
    ) == 1
}

private func uintProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope
) -> UInt32? {
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

private func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
        return 0
    }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
}
#endif
