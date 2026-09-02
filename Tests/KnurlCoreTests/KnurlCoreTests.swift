import CoreAudio
import Foundation
import Testing
@testable import KnurlCore

@Test func modeAdvancesAndWraps() {
    #expect(DialMode.media.advanced(by: 1) == .volume)
    #expect(DialMode.mic.advanced(by: 1) == .media)
    #expect(DialMode.media.advanced(by: -1) == .mic)
}

@Test func notchSitsInTheHousing() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let left = CGRect(x: 0, y: 944, width: 640, height: 38)
    let right = CGRect(x: 872, y: 944, width: 640, height: 38)
    let housing = NotchMath.housingFrame(
        screen: screen,
        visible: visible,
        leftAux: left,
        rightAux: right
    )
    #expect(housing?.minX == 640)
    #expect(housing?.width == 232)
    #expect(housing?.minY == 944)
    #expect(housing?.height == 38)
    #expect(NotchMath.housingFrame(screen: screen, visible: visible, leftAux: nil, rightAux: nil) == nil)
    if let housing {
        let expanded = NotchMath.expandedFrame(housing: housing, visible: visible)
        #expect(abs(expanded.midX - housing.midX) < 1)
        #expect(expanded.maxY == housing.maxY)
        #expect(expanded.height > housing.height)
        #expect(expanded.minY < housing.minY)
        let housed = NotchMath.housingInExpanded(housing: housing, expanded: expanded)
        #expect(housed.height == housing.height)
        #expect(housed.width == housing.width)
        let flow = NotchMath.expandedFrame(
            housing: housing,
            visible: visible,
            shelf: NotchMath.flowShelfHeight
        )
        #expect(flow.maxY == housing.maxY)
        #expect(flow.height > expanded.height)
        #expect(flow.height - housing.height == NotchMath.shelfGap + NotchMath.flowShelfHeight)
    }
}

@Test func sixHubPagesAreTheWorkstation() {
    #expect(HubPage.allCases.map(\.title) == [
        "Home", "Tools", "Workspace", "Flow", "System", "Sessions",
    ])
}

@Test func workspaceSnapsAreDeterministic() {
    let visible = CGRect(x: 0, y: 0, width: 1800, height: 1000)
    let left = WorkspaceMath.snap(.leftHalf, in: visible)
    #expect(left.width == 900)
    #expect(left.height == 1000)
    let stack = WorkspaceMath.frames(for: .agentStack, visible: visible, count: 3)
    #expect(stack.count == 3)
    #expect(abs(stack[0].width - 1080) < 0.5)
    #expect(abs(stack[1].width - 720) < 0.5)
    let review = WorkspaceMath.frames(for: .review, visible: visible, count: 3)
    #expect(review[2].minY == visible.minY)
    #expect(review[0].maxY == visible.maxY)
}

@Test func deskTimerCountsDownAndFinishes() {
    var timer = DeskTimer(duration: 90, remaining: 90)
    #expect(abs(timer.crownProgress - 90 / DeskTimer.maxDuration) < 0.001)
    timer.start(at: Date(timeIntervalSince1970: 0))
    #expect(timer.running)
    #expect(timer.whisper == "01:30")
    let finished = timer.tick(now: Date(timeIntervalSince1970: 90))
    #expect(finished)
    #expect(!timer.running)
    #expect(timer.whisper == nil)
    var live = DeskTimer(duration: 60, remaining: 60)
    live.start(at: Date(timeIntervalSince1970: 10))
    let draggedOff = live.setCrown(0, now: Date(timeIntervalSince1970: 20))
    #expect(draggedOff)
    #expect(!live.running)
    var paused = DeskTimer(duration: 50 * 60, remaining: 50 * 60)
    paused.start(at: Date(timeIntervalSince1970: 0))
    let mid = paused.pause(at: Date(timeIntervalSince1970: 20 * 60))
    #expect(!mid)
    #expect(paused.isArmed)
    #expect(abs(paused.crownProgress - 0.6) < 0.01)
    let nudged = paused.setCrown(0.4, now: Date(timeIntervalSince1970: 20 * 60))
    #expect(!nudged)
    #expect(abs(paused.remaining - 20 * 60) < 0.5)
    var expired = DeskTimer(duration: 60, remaining: 60)
    expired.start(at: Date(timeIntervalSince1970: 0))
    let timedOut = expired.pause(at: Date(timeIntervalSince1970: 60))
    #expect(timedOut)
}

@Test func notchWhisperPrefersFlowOverTimerAndMusic() {
    let whisper = NotchWhisper.pick(
        listening: true,
        destination: "Cursor",
        attention: "Claude Code",
        thermalException: false,
        batteryPercent: 71,
        powerMode: "Balanced",
        workspaceFlash: nil,
        musicTitle: "Let It Happen",
        elapsed: "01:12",
        timerRemaining: "24:10"
    )
    #expect(whisper == .flow(destination: "Cursor"))
    #expect(whisper.line == "→ Cursor")
    #expect(whisper.detail == "→ Cursor")
}

@Test func notchWhisperPrefersTimerOverMusic() {
    let whisper = NotchWhisper.pick(
        listening: false,
        destination: "Cursor",
        attention: nil,
        thermalException: false,
        batteryPercent: 71,
        powerMode: "Balanced",
        workspaceFlash: nil,
        musicTitle: "Let It Happen",
        elapsed: "01:12",
        timerRemaining: "24:10"
    )
    #expect(whisper == .timer(remaining: "24:10"))
    #expect(whisper.detail == "Hour")
}

@Test func notchWhisperPrefersAttentionOverMusic() {
    let whisper = NotchWhisper.pick(
        listening: false,
        destination: "Cursor",
        attention: "Claude Code",
        thermalException: false,
        batteryPercent: 71,
        powerMode: "Balanced",
        workspaceFlash: nil,
        musicTitle: "Let It Happen",
        elapsed: "01:12"
    )
    #expect(whisper == .attention(name: "Claude Code"))
    #expect(whisper.line.contains("needs you"))
}

@Test func menuBarIslandPrefersFlowThenAttentionThenMusic() {
    let flow = MenuBarLive.snapshot(
        listening: true,
        attention: "Claude Code",
        musicTitle: "Let It Happen",
        musicPlaying: true,
        outputName: "AirPods"
    )
    #expect(flow.line == "Flow")
    let attention = MenuBarLive.snapshot(
        listening: false,
        attention: "Claude Code",
        musicTitle: "Let It Happen",
        musicPlaying: true,
        outputName: "AirPods"
    )
    #expect(attention.line == "Claude Code")
    let hour = MenuBarLive.snapshot(
        listening: false,
        attention: "Claude Code",
        musicTitle: "Let It Happen",
        musicPlaying: true,
        outputName: "AirPods",
        timerRemaining: "24:10"
    )
    #expect(hour.line == "24:10")
    #expect(hour.detail == "Hour")
    let music = MenuBarLive.snapshot(
        listening: false,
        attention: nil,
        musicTitle: "Let It Happen",
        musicPlaying: true,
        outputName: "AirPods"
    )
    #expect(music.line == "Let It Happen")
    #expect(music.pillWidth > 28)
    #expect(music.pillWidth <= 176)
}

@Test func speakerDetentsMapAroundTheRing() {
    #expect(DialMath.detentIndex(progress: 0, count: 4) == 0)
    #expect(DialMath.detentIndex(progress: 1, count: 4) == 3)
    #expect(DialMath.detentIndex(progress: 0.5, count: 3) == 1)
    #expect(DialMath.detentProgress(index: 0, count: 1) == 0.5)
    #expect(abs(DialMath.detentProgress(index: 2, count: 3) - 1) < 0.001)
}

@Test func sessionClockFormatsHours() {
    #expect(DialMath.sessionClock(74) == "01:14")
    #expect(DialMath.sessionClock(3723) == "1:02:03")
}

@Test func appKitAndAXFramesRoundTrip() {
    let primaryHeight: CGFloat = 982
    let cocoa = CGRect(x: 0, y: 0, width: 756, height: 944)
    let ax = WorkspaceMath.axFrame(from: cocoa, primaryHeight: primaryHeight)
    #expect(abs(ax.minY - (982 - 944)) < 0.5)
    #expect(WorkspaceMath.appKitFrame(from: ax, primaryHeight: primaryHeight) == cocoa)
}

@Test func powerModesStayKnurlOwned() {
    #expect(PowerMode.allCases.map(\.title) == ["Battery", "Balanced", "Performance"])
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
    #expect(DialMode.mic.hint.contains("Flow"))
    #expect(DialMode.brightness.hint.contains("built-in"))
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

@Test func outputRosterRanksHeadphonesThenHomePod() {
    let airpods = AudioDevice(id: 2, uid: "bt", name: "AirPods Pro", transport: .bluetooth)
    let mac = AudioDevice(id: 1, uid: "mac", name: "MacBook Speakers", transport: .builtIn)
    let pod = AudioDevice(id: 3, uid: "ap", name: "Kitchen", transport: .airPlay)
    #expect(AudioOutputs.ranked([mac, pod, airpods]).map(\.uid) == ["bt", "ap", "mac"])
}

@Test func outputRosterAlwaysContainsTheCurrentDevice() {
    let route = AudioOutputs()
    guard let current = route.current else { return }
    #expect(route.devices().contains { $0.uid == current.uid })
}

@Test func outputDeviceRoundTripOnThisMac() {
    let route = AudioOutputs()
    let devices = route.devices()
    guard let original = route.current, !devices.isEmpty else { return }
    print("output roster: " + devices.map { "\($0.transport.rawValue):\($0.name)" }.joined(separator: " | "))
    defer { route.select(original) }
    if let other = devices.first(where: { $0.id != original.id }) {
        #expect(route.select(other))
        #expect(route.current?.uid == other.uid)
        #expect(route.select(original))
        #expect(route.current?.uid == original.uid)
    } else {
        route.cycle(by: 1)
        #expect(route.current != nil)
    }
}

@Test func outputDialCyclesEverySpeakerOnThisMac() {
    let route = AudioOutputs()
    let devices = route.devices()
    guard let original = route.current, devices.count > 1 else { return }
    defer { route.select(original) }
    for device in devices {
        #expect(route.select(device))
        #expect(route.current?.uid == device.uid)
    }
}

@Test func transportTypesHaveHumanNames() {
    #expect(AudioTransport.from(kAudioDeviceTransportTypeBluetooth) == .bluetooth)
    #expect(AudioTransport.from(kAudioDeviceTransportTypeAirPlay) == .airPlay)
    #expect(AudioTransport.from(kAudioDeviceTransportTypeHDMI) == .hdmi)
    #expect(AudioTransport.from(kAudioDeviceTransportTypeBuiltIn).title == "Built-in")
    #expect(AudioTransport.bluetooth.symbol == "headphones")
    #expect(AudioTransport.airPlay.symbol == "homepod.fill")
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
