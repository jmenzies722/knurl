#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation

public struct SystemVolume: Sendable {
    public init() {}

    public var level: Float {
        get {
            readScalar(Self.virtualMain) ?? readChannelAverage() ?? 0
        }
        nonmutating set {
            let clamped = min(1, max(0, newValue))
            writeScalar(Self.virtualMain, value: clamped)
            writeChannels(clamped)
        }
    }

    public var isMuted: Bool {
        get { readMute(element: kAudioObjectPropertyElementMain) || readMute(element: 1) }
        nonmutating set {
            writeMute(newValue, element: kAudioObjectPropertyElementMain)
            writeMute(newValue, element: 1)
            writeMute(newValue, element: 2)
        }
    }

    public var hasDevice: Bool {
        defaultOutputDevice() != kAudioObjectUnknown
    }

    private static let virtualMain = AudioObjectPropertySelector(
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    )
    private static let channelVolume = AudioObjectPropertySelector(
        kAudioDevicePropertyVolumeScalar
    )

    private func defaultOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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

    private func readScalar(_ selector: AudioObjectPropertySelector) -> Float? {
        readFloat(selector, element: kAudioObjectPropertyElementMain)
    }

    private func writeScalar(_ selector: AudioObjectPropertySelector, value: Float) {
        writeFloat(selector, element: kAudioObjectPropertyElementMain, value: value)
    }

    private func readChannelAverage() -> Float? {
        let left = readFloat(Self.channelVolume, element: 1)
        let right = readFloat(Self.channelVolume, element: 2)
        switch (left, right) {
        case let (l?, r?): return (l + r) / 2
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    private func writeChannels(_ value: Float) {
        writeFloat(Self.channelVolume, element: 1, value: value)
        writeFloat(Self.channelVolume, element: 2, value: value)
    }

    private func readFloat(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Float? {
        let device = defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func writeFloat(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        value: Float
    ) {
        let device = defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        var next = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &next)
    }

    private func readMute(element: AudioObjectPropertyElement) -> Bool {
        let device = defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    private func writeMute(_ muted: Bool, element: AudioObjectPropertyElement) {
        let device = defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }
}
#endif
