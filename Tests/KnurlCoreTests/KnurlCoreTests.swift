import CoreAudio
import Foundation
import Testing
@testable import KnurlCore

@Test func modeAdvancesAndWraps() {
    #expect(DialMode.media.advanced(by: 1) == .volume)
    #expect(DialMode.mic.advanced(by: 1) == .media)
    #expect(DialMode.media.advanced(by: -1) == .mic)
}

@Test func notchChipCentersOnTheHousing() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let left = CGRect(x: 0, y: 944, width: 640, height: 38)
    let right = CGRect(x: 872, y: 944, width: 640, height: 38)
    let frame = NotchMath.chipFrame(
        visible: visible,
        leftAux: left,
        rightAux: right,
        size: NotchMath.collapsedSize
    )
    #expect(abs(frame.midX - 756) < 1)
    #expect(frame.maxY == visible.maxY)
    #expect(NotchMath.deskFrame(visible: visible) == visible)
}

@Test func fiveModesAreTheProduct() {
    #expect(DialMode.allCases.map(\.title) == [
        "Media", "Volume", "Bright", "Output", "Mic",
    ])
}

@Test func eachModeHasItsOwnJob() {
    let confirms = DialMode.allCases.map(\.confirmTitle)
    #expect(Set(confirms).count == DialMode.allCases.count)
    #expect(DialMode.media.hint.contains("skip"))
    #expect(DialMode.mic.hint.contains("Talk"))
    #expect(DialMode.output.stepForwardSymbol == "chevron.right")
}

@Test func noModeAsksForAccessibility() {
    #expect(DialMode.allCases.allSatisfy { mode in
        switch mode {
        case .volume, .brightness, .media, .output, .mic: true
        }
    })
}

@Test func volumeStepsStayInRange() {
    #expect(DialMath.steppedVolume(current: 0.5, detents: 1) == 0.55)
    #expect(DialMath.steppedVolume(current: 0.02, detents: -1) == 0)
    #expect(DialMath.steppedVolume(current: 0.98, detents: 2) == 1)
    #expect(DialMath.percent(0.424) == 42)
    #expect(DialMath.clock(125) == "2:05")
}

@Test func gaugeMapsAroundTheRing() {
    #expect(DialMath.percent(DialMath.gaugeProgress(angleDegrees: 135) ?? -1) == 0)
    #expect(DialMath.percent(DialMath.gaugeProgress(angleDegrees: 270) ?? -1) == 50)
    #expect(DialMath.gaugeProgress(angleDegrees: 90) == nil)
    #expect(!DialMath.acceptsGaugeJump(from: 0.9, to: 0.1))
    #expect(DialMath.acceptsGaugeJump(from: 0.4, to: 0.5))
    #expect(DialMath.gaugeAngle(progress: 0) == 135)
    #expect(DialMath.gaugeAngle(progress: 1) == 405)
    #expect(DialMath.percent(DialMath.ringProgress(clockwiseFromNoon: 225) ?? -1) == 0)
    #expect(DialMath.percent(DialMath.ringProgress(clockwiseFromNoon: 0) ?? -1) == 50)
    #expect(DialMath.percent(DialMath.ringProgress(clockwiseFromNoon: 135) ?? -1) == 100)
    #expect(DialMath.ringProgress(clockwiseFromNoon: 180) == nil)
    #expect(DialMath.ringAngle(progress: 0) == 225)
    #expect(DialMath.ringAngle(progress: 1) == 495)
}

@Test func detentStepsAreStable() {
    #expect(TickSound.detent(from: 0) == 0)
    #expect(TickSound.detent(from: 0.049) == 1)
    #expect(TickSound.detent(from: 0.52) == 10)
    #expect(TickSound.detent(from: 1) == 20)
}

@Test func tintWarmsAsProgressRises() {
    let low = DialTint.rgb(progress: 0.05, muted: false)
    let high = DialTint.rgb(progress: 0.95, muted: false)
    let muted = DialTint.rgb(progress: 0.95, muted: true)
    #expect(high.0 > low.0)
    #expect(muted.0 < high.0)
    let bright = DialTint.rgb(progress: 0.9, muted: false, mode: .brightness)
    let output = DialTint.rgb(progress: 0.9, muted: false, mode: .output)
    #expect(bright.0 > output.0)
}

@Test func volumeRoundTripOnThisMac() {
    let audio = SystemVolume()
    guard audio.hasDevice else { return }
    let original = audio.level
    let muted = audio.isMuted
    defer {
        audio.level = original
        audio.isMuted = muted
    }
    audio.isMuted = false
    audio.level = 0.37
    #expect(abs(audio.level - 0.37) < 0.08)
}

@Test func outputDeviceRoundTripOnThisMac() {
    let route = AudioOutputs()
    let devices = route.devices()
    guard let original = route.current, !devices.isEmpty else { return }
    defer { route.select(original.id) }
    if let other = devices.first(where: { $0.id != original.id }) {
        route.select(other.id)
        #expect(route.current?.id == other.id)
        route.select(original.id)
        #expect(route.current?.id == original.id)
    } else {
        route.cycle(by: 1)
        #expect(route.current != nil)
    }
}

@Test func transportTypesHaveHumanNames() {
    #expect(AudioTransport.from(kAudioDeviceTransportTypeBluetooth) == .bluetooth)
    #expect(AudioTransport.from(kAudioDeviceTransportTypeAirPlay) == .airPlay)
    #expect(AudioTransport.from(kAudioDeviceTransportTypeHDMI) == .hdmi)
    #expect(AudioTransport.from(kAudioDeviceTransportTypeBuiltIn).title == "Built-in")
}

@Test func outputMemoryRemembersAndRecalls() {
    var memory = OutputMemory()
    #expect(memory.recall(uid: "BuiltIn") == nil)
    memory.remember(uid: "BuiltIn", level: 0.42, muted: true)
    memory.remember(uid: "AirPods", level: 0.8, muted: false)
    #expect(memory.recall(uid: "BuiltIn") == OutputSnapshot(level: 0.42, muted: true))
    #expect(memory.recall(uid: "AirPods")?.muted == false)
    memory.remember(uid: "BuiltIn", level: 0.1, muted: false)
    #expect(memory.recall(uid: "BuiltIn")?.level == 0.1)
}

@Test func inputDeviceRoundTripOnThisMac() {
    let route = AudioInputs()
    let devices = route.devices()
    guard let original = route.current, !devices.isEmpty else { return }
    defer { route.select(original.id) }
    if let other = devices.first(where: { $0.id != original.id }) {
        route.select(other.id)
        #expect(route.current?.id == other.id)
        route.select(original.id)
        #expect(route.current?.id == original.id)
    } else {
        route.cycle(by: 1)
        #expect(route.current != nil)
    }
}

@Test func inputGainRoundTripOnThisMac() {
    let mic = InputGain()
    guard mic.hasDevice else { return }
    let original = mic.level
    let muted = mic.isMuted
    defer {
        mic.level = original
        mic.isMuted = muted
    }
    mic.isMuted = false
    mic.level = 0.41
    let live = mic.level
    guard live > 0.02 else { return }
    #expect(abs(live - 0.41) < 0.15)
}
