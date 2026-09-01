#if os(macOS)
import CoreAudio
import Foundation

public enum AudioTransport: String, Sendable, Equatable {
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
        allDeviceIDs().compactMap { id in
            guard isAlive(id),
                  canBeDefault(id, scope: kAudioDevicePropertyScopeOutput),
                  channelCount(id, scope: kAudioDevicePropertyScopeOutput) > 0
            else { return nil }
            return AudioDevice(
                id: id,
                uid: uid(of: id) ?? "id-\(id)",
                name: name(of: id) ?? "Output \(id)",
                transport: AudioTransport.from(transportType(id))
            )
        }
    }

    public var current: AudioDevice? {
        let id = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard id != kAudioObjectUnknown else { return nil }
        return AudioDevice(
            id: id,
            uid: uid(of: id) ?? "id-\(id)",
            name: name(of: id) ?? "Output",
            transport: AudioTransport.from(transportType(id))
        )
    }

    public func select(_ id: AudioDeviceID) {
        setDefault(kAudioHardwarePropertyDefaultOutputDevice, id)
    }

    public func cycle(by delta: Int) {
        let list = devices()
        guard !list.isEmpty else { return }
        let currentID = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let index = list.firstIndex(where: { $0.id == currentID }) ?? 0
        let count = list.count
        let next = ((index + delta) % count + count) % count
        select(list[next].id)
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

private func setDefault(_ selector: AudioObjectPropertySelector, _ device: AudioDeviceID) {
    var next = device
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        size,
        &next
    )
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
