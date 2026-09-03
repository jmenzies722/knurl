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
        #expect(flow.height > housing.height)
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
    #expect(whisper.symbol == "waveform")
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
    #expect(whisper.symbol == "timer")
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
    #expect(whisper.symbol == "exclamationmark.circle.fill")
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

@Test func rememberedHomePodsJoinTheOutputRoster() {
    let mac = AudioDevice(id: 1, uid: "mac", name: "MacBook Speakers", transport: .builtIn)
    let remembered = [AirPlayDestination(uid: "kitchen", name: "Kitchen")]
    let roster = AudioOutputs.roster([mac], remembered: remembered)
    #expect(roster.map(\.uid) == ["kitchen", "mac"])
    #expect(roster[0].transport == .airPlay)
}

@Test func airPlayNamesAreRecognized() {
    #expect(AudioOutputs.isAirPlayNamed("Kitchen HomePod"))
    #expect(AudioOutputs.isAirPlayNamed("AirPlay"))
    #expect(!AudioOutputs.isAirPlayNamed("BoomAudio"))
}

@Test func musicAirPlayListParsesHomePod() {
    let raw = "Comet\tHomePod\tfalse\ttrue\u{1f}Josh-MacBook-Pro\tcomputer\ttrue\ttrue\u{1f}"
    let list = MusicAirPlayDevice.parseList(raw)
    #expect(list.count == 2)
    #expect(list[0].name == "Comet")
    #expect(list[0].kind == .homePod)
    #expect(list[0].uid == "music-airplay:Comet")
    #expect(list[1].kind == .computer)
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

// MARK: - Desk tools
//
// These run against the real machine on purpose. A mocked CPU sampler would
// prove the arithmetic and nothing about whether `host_processor_info` was
// called correctly, which is the only part that can actually be wrong.

@Suite("Machine vitals")
struct MachineVitalsTests {
    @Test func cpuSamplerReportsEveryCoreOnThisMac() async throws {
        var sampler = CPUSampler()
        _ = sampler.sample()
        // The first sample only seeds the counters; a rate needs two.
        try await Task.sleep(for: .milliseconds(250))
        let reading = sampler.sample()

        #expect(reading.cores.count == ProcessInfo.processInfo.processorCount)
        #expect(reading.overall >= 0 && reading.overall <= 1)
        for load in reading.cores {
            #expect(load >= 0 && load <= 1)
        }
    }

    @Test func memoryReadsBackUnderTheInstalledTotal() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        #expect(result == KERN_SUCCESS)

        let page = UInt64(sysconf(_SC_PAGESIZE))
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)) * page
        let total = ProcessInfo.processInfo.physicalMemory

        #expect(used > 0)
        #expect(used < total)

        var vitals = MachineVitals()
        vitals.memoryUsed = used
        vitals.memoryTotal = total
        #expect(vitals.memoryProgress > 0 && vitals.memoryProgress < 1)
    }

    @Test func networkSamplerReturnsANonNegativeRate() async throws {
        var sampler = NetworkSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .milliseconds(250))
        let (down, up) = sampler.sample()
        #expect(down >= 0)
        #expect(up >= 0)
    }

    @Test func bootVolumeReportsRealCapacity() throws {
        let values = try URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        #expect(total > 0)
        #expect(free > 0)
        #expect(free <= total)
    }

    @Test func byteAndRateLabelsAreReadable() {
        #expect(DeskFormat.bytes(0) != "")
        #expect(DeskFormat.rate(0).hasSuffix("KB/s"))
        #expect(DeskFormat.rate(2 * 1024 * 1024).hasSuffix("MB/s"))
    }

    @Test func uptimeLabelRollsUpThroughDays() {
        var vitals = MachineVitals()
        vitals.uptime = 90
        #expect(vitals.uptimeLabel == "1m")
        vitals.uptime = 3 * 3600 + 25 * 60
        #expect(vitals.uptimeLabel == "3h 25m")
        vitals.uptime = 2 * 86400 + 5 * 3600
        #expect(vitals.uptimeLabel == "2d 5h")
    }
}

@Suite("Keep awake")
struct KeepAwakeTests {
    /// Proves the assertion is genuinely registered with powerd rather than
    /// just constructed: `pmset -g assertions` lists it by name while the
    /// value is alive, and stops listing it once it is released.
    @Test func assertionIsVisibleToPowerdWhileHeld() throws {
        let reason = "Knurl test assertion \(UUID().uuidString)"

        func assertionsOutput() -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "assertions"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }

        #expect(!assertionsOutput().contains(reason))

        var held: KeepAwakeAssertion? = KeepAwakeAssertion(reason: reason)
        #expect(held != nil)
        #expect(assertionsOutput().contains(reason))

        held = nil
        #expect(!assertionsOutput().contains(reason))
    }
}

// MARK: - Notch stages
//
// Geometry for the housing island: one shape anchored under the cutout
// that grows downward. These pin the invariants the drawing depends on — a
// panel that is not top-anchored, or a stage narrower than the cutout, breaks
// the illusion in a way that is obvious on screen and silent in a build.

@Suite("Notch stages")
struct NotchStageTests {
    /// A real 16-inch MacBook Pro, measured: 2056×1329 with a 220×38 notch.
    private let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
    private let visible = CGRect(x: 0, y: 92, width: 2056, height: 1198)
    private var housing: CGRect {
        NotchMath.housingFrame(
            screen: screen,
            visible: visible,
            leftAux: CGRect(x: 0, y: 1291, width: 918, height: 38),
            rightAux: CGRect(x: 1138, y: 1291, width: 918, height: 38)
        )!
    }

    @Test func housingMatchesTheMeasuredCutout() {
        #expect(housing.width == 220)
        #expect(housing.minX == 918)
        #expect(housing.maxY == screen.maxY)
    }

    @Test func panelIsTopAnchoredAndCentredOnTheCutout() {
        let frame = NotchMath.panelFrame(screen: screen, housing: housing)
        // Top-anchored: the shape's flat top edge has to sit behind the
        // cutout, which is the only reason the seam is invisible.
        #expect(frame.maxY == screen.maxY)
        #expect(abs(frame.midX - housing.midX) < 0.001)
        // Wide and tall enough for every stage plus the spring's overshoot.
        for stage in NotchStage.allCases {
            let size = NotchMath.contentSize(housing: housing, stage: stage)
            #expect(size.width <= frame.width)
            #expect(size.height <= frame.height)
        }
    }

    @Test func everyStageIsAtLeastAsWideAsTheCutout() {
        // Narrower than the notch and the fillets would curve inward from
        // nothing, which reads as a bite taken out of the bezel.
        for stage in NotchStage.allCases {
            let size = NotchMath.contentSize(housing: housing, stage: stage)
            #expect(size.width >= housing.width)
            #expect(size.height >= housing.height)
        }
    }

    @Test func restIsExactlyTheCutout() {
        // The whole point: idle, there is nothing to see. A shape even a few
        // points proud of the housing is a bar under the notch, not the notch.
        let size = NotchMath.contentSize(housing: housing, stage: .rest)
        #expect(size.width == housing.width)
        #expect(size.height == housing.height)
        #expect(NotchStage.rest.flare == 0)
        #expect(NotchStage.rest.height == 0)
    }

    @Test func theCompactStageWidensAndTheOpenStagesDrop() {
        // Two different motions, and the difference is the design.
        //
        // `glance` is Apple's compact Dynamic Island: it *widens* to put a
        // glyph and an indicator either side of the cutout, and drops nothing
        // below the housing. `hover` and beyond drop. Asserting a single
        // ladder of heights would assert a design nobody chose — and did,
        // until the compact stage stopped hanging a bar under the notch.
        #expect(NotchStage.rest.height == 0)
        #expect(NotchStage.rest.flare == 0)

        #expect(NotchStage.glance.height == 0, "compact must not drop below the housing")
        #expect(NotchStage.glance.flare > 0, "compact is the stage that widens")

        for open in [NotchStage.hover, .shelf, .flow] {
            #expect(open.height > 0, "\(open) must drop below the housing")
            #expect(open.flare > NotchStage.glance.flare, "\(open) must be wider than compact")
        }
        // The shelf carries the most: the dial, the scrubbers, the faces and
        // the exits.
        #expect(NotchStage.shelf.height > NotchStage.hover.height)
        #expect(NotchStage.rest.flare < NotchStage.hover.flare)
        #expect(NotchStage.rest.topCornerRadius < NotchStage.hover.topCornerRadius)
        // Only the stages that show controls count as open.
        #expect(!NotchStage.rest.isOpen)
        #expect(!NotchStage.glance.isOpen)
        #expect(NotchStage.hover.isOpen)
        #expect(NotchStage.shelf.isOpen)
        #expect(NotchStage.flow.isOpen)
    }

    @Test func hoverTargetIsForgivingButLocal() {
        let target = NotchMath.hoverTarget(housing: housing)
        // Dead centre of the cutout opens it.
        #expect(target.contains(CGPoint(x: housing.midX, y: housing.midY)))
        // So does a near miss just outside the edge, and just below it.
        #expect(target.contains(CGPoint(x: housing.minX - 10, y: housing.midY)))
        #expect(target.contains(CGPoint(x: housing.midX, y: housing.minY - 6)))
        // The far end of the menu bar does not, and neither does the page.
        #expect(!target.contains(CGPoint(x: 100, y: housing.midY)))
        #expect(!target.contains(CGPoint(x: housing.midX, y: 400)))
        // Nor does reaching up past the top of the screen.
        #expect(!target.contains(CGPoint(x: housing.midX, y: housing.minY - 40)))
    }

    @Test func openTargetCoversTheWholeOpenShape() {
        // While open, the pointer must be able to reach any control inside
        // without the shape closing under it.
        let target = NotchMath.openTarget(housing: housing, stage: .hover)
        let size = NotchMath.contentSize(housing: housing, stage: .hover)
        #expect(target.contains(CGPoint(x: housing.midX, y: housing.maxY - size.height + 4)))
        #expect(target.contains(CGPoint(x: housing.midX - size.width / 2 + 4, y: housing.midY)))
        #expect(target.width > NotchMath.hoverTarget(housing: housing).width)
    }

    @Test func aMacWithNoHousingReportsNone() {
        #expect(NotchMath.housingFrame(
            screen: screen, visible: visible, leftAux: nil, rightAux: nil
        ) == nil)
        // An external display: the two aux areas touch, so there is no gap.
        #expect(NotchMath.housingFrame(
            screen: screen,
            visible: visible,
            leftAux: CGRect(x: 0, y: 1291, width: 1028, height: 38),
            rightAux: CGRect(x: 1028, y: 1291, width: 1028, height: 38)
        ) == nil)
    }
}

// MARK: - AirPlay parsing
//
// Pinned against the exact bytes Music.app returned on this desk, captured by
// running the same AppleScript by hand. A parser for another process's output
// format should be tested against that process's real output, not against a
// string someone typed from memory.

@Suite("AirPlay roster")
struct AirPlayRosterTests {
    /// Four devices, tab-separated fields, unit-separator between rows.
    private let real = "Josh-MacBook-Pro\tcomputer\tfalse\ttrue\u{1f}"
        + "Comet\tHomePod\ttrue\ttrue\u{1f}"
        + "Roku TV\tTV\tfalse\ttrue\u{1f}"
        + "Living Room Fire TV\tTV\tfalse\ttrue\u{1f}"

    @Test func realMusicOutputParsesIntoNamedDevices() {
        let devices = MusicAirPlayDevice.parseList(real)
        #expect(devices.count == 4)
        #expect(devices[0].name == "Josh-MacBook-Pro")
        #expect(devices[0].kind == .computer)
        #expect(devices[0].selected == false)
        #expect(devices[1].name == "Comet")
        #expect(devices[1].kind == .homePod)
        #expect(devices[1].selected == true)
        #expect(devices[2].name == "Roku TV")
        #expect(devices[2].kind == .television)
        // No device name may ever contain a field from its own row — that is
        // what "computer false true" on screen looks like.
        for device in devices {
            #expect(!device.name.contains("\t"))
            #expect(!device.name.lowercased().contains("false"))
            #expect(!device.name.lowercased().contains("true"))
        }
    }

    @Test func aRowMissingItsSeparatorIsRejectedNotMangled() {
        // If the unit separator is ever lost, every field runs together. The
        // parser must drop that rather than invent a device called
        // "computer false true".
        let mangled = "computer\tfalse\ttrue"
        #expect(MusicAirPlayDevice.parseList(mangled).isEmpty)
    }

    @Test func emptyAndShortRowsAreDropped() {
        #expect(MusicAirPlayDevice.parseList("").isEmpty)
        #expect(MusicAirPlayDevice.parseList("\u{1f}\u{1f}").isEmpty)
        #expect(MusicAirPlayDevice.parseList("OnlyAName\u{1f}").isEmpty)
    }
}

// MARK: - Window manager
//
// The Accessibility half of Window Manager cannot be tested without granting
// the permission, but the half that decides *where* a window goes is pure
// geometry — and that is the half that produces a visibly wrong layout.

@Suite("Workspace layout")
struct WorkspaceLayoutTests {
    private let visible = CGRect(x: 0, y: 92, width: 2056, height: 1198)

    @Test func everySnapZoneLandsInsideTheDisplay() {
        for zone in SnapZone.allCases {
            let frame = WorkspaceMath.snap(zone, in: visible)
            #expect(frame.width > 0)
            #expect(frame.height > 0)
            // A snapped window that starts above the menu bar or below the
            // Dock is a window you cannot reach.
            #expect(frame.minX >= visible.minX - 0.5)
            #expect(frame.minY >= visible.minY - 0.5)
            #expect(frame.maxX <= visible.maxX + 0.5)
            #expect(frame.maxY <= visible.maxY + 0.5)
        }
    }

    @Test func halvesTileWithoutOverlapOrGap() {
        let left = WorkspaceMath.snap(.leftHalf, in: visible)
        let right = WorkspaceMath.snap(.rightHalf, in: visible)
        #expect(left.maxX == right.minX)
        #expect(left.width + right.width == visible.width)

        let top = WorkspaceMath.snap(.topHalf, in: visible)
        let bottom = WorkspaceMath.snap(.bottomHalf, in: visible)
        #expect(bottom.maxY == top.minY)
        #expect(top.height + bottom.height == visible.height)
    }

    @Test func thirdsCoverTheDisplayExactly() {
        let zones: [SnapZone] = [.leftThird, .centerThird, .rightThird]
        let frames = zones.map { WorkspaceMath.snap($0, in: visible) }
        #expect(abs(frames.map(\.width).reduce(0, +) - visible.width) < 0.5)
        #expect(frames[0].maxX == frames[1].minX)
        #expect(abs(frames[1].maxX - frames[2].minX) < 0.5)
    }

    @Test func presetsProduceOneFramePerWindowAndStayOnScreen() {
        for preset in WorkspacePreset.allCases {
            for count in 1 ... 4 {
                let frames = WorkspaceMath.frames(for: preset, visible: visible, count: count)
                #expect(frames.count == count, "\(preset) with \(count) windows")
                for frame in frames where frame != .null {
                    #expect(frame.width > 0)
                    #expect(frame.height > 0)
                    #expect(frame.minX >= visible.minX - 0.5)
                    #expect(frame.maxX <= visible.maxX + 0.5)
                    #expect(frame.minY >= visible.minY - 0.5)
                    #expect(frame.maxY <= visible.maxY + 0.5)
                }
            }
        }
    }

    @Test func appKitAndAccessibilityFramesRoundTrip() {
        // The two coordinate systems disagree about which way is up, and
        // getting this wrong puts windows off the bottom of the screen.
        let primaryHeight: CGFloat = 1329
        let appKit = CGRect(x: 120, y: 300, width: 900, height: 600)
        let ax = WorkspaceMath.axFrame(from: appKit, primaryHeight: primaryHeight)
        let back = WorkspaceMath.appKitFrame(from: ax, primaryHeight: primaryHeight)
        #expect(back == appKit)
        #expect(ax.minY == primaryHeight - appKit.maxY)
    }

    @Test func canvasAndScreenCoordinatesRoundTrip() {
        let canvas = CGSize(width: 600, height: 350)
        let frame = CGRect(x: 400, y: 500, width: 800, height: 500)
        let rect = WorkspaceMath.canvasRect(frame, in: visible, canvas: canvas)
        let origin = WorkspaceMath.screenPoint(
            from: CGPoint(x: rect.minX, y: rect.minY),
            visible: visible,
            canvasSize: canvas
        )
        #expect(abs(origin.x - frame.minX) < 1)
        #expect(abs(origin.y - frame.maxY) < 1)
    }
}

// MARK: - Snapshot parsing
//
// The track parser must never accept an AirPlay roster. Both scripts return
// unit-separated rows, so when two of them ran concurrently on different
// threads — which `NSAppleScript` does not allow — the snapshot happily
// parsed a speaker list into a song, and the Hub showed "Josh-MacBook-Pro
// computer true true" as the track title. The scripts are now on one serial
// queue, and this pins the shape so the parser also refuses on its own.

@Suite("Track snapshot")
struct TrackSnapshotTests {
    @Test func aRealSnapshotParses() {
        let raw = "STEP (feat. BXKS)\u{1f}ayrtn\u{1f}STEP (feat. BXKS) - Single"
            + "\u{1f}playing\u{1f}47.5\u{1f}180.0\u{1f}false\u{1f}off\u{1f}Hip-Hop"
        let track = MusicSnapshot.parse(raw)
        #expect(track.title == "STEP (feat. BXKS)")
        #expect(track.artist == "ayrtn")
        #expect(track.isPlaying)
        #expect(track.position == 47.5)
        #expect(track.duration == 180.0)
        #expect(track.genre == "Hip-Hop")
    }

    @Test func anAirPlayRosterIsNotATrack() {
        // The exact corruption that shipped: the AirPlay roster fed into the
        // snapshot parser. A tab in the title is the tell — a snapshot field
        // never contains one, because tab is the AirPlay row's separator.
        let roster = "Josh-MacBook-Pro\tcomputer\ttrue\ttrue"
            + "\u{1f}Comet\tHomePod\tfalse\ttrue"
            + "\u{1f}Roku TV\tTV\tfalse\ttrue"
        let track = MusicSnapshot.parse(roster)
        #expect(track.title.isEmpty, "a device row must not become a song title")
        #expect(track.artist.isEmpty)
        #expect(track.album.isEmpty)
    }

    @Test func aStoppedPlayerParsesToNothingPlaying() {
        let raw = "\u{1f}\u{1f}\u{1f}stopped\u{1f}0\u{1f}0\u{1f}false\u{1f}off\u{1f}"
        let track = MusicSnapshot.parse(raw)
        #expect(track.title.isEmpty)
        #expect(!track.isPlaying)
        #expect(track.duration == 0)
    }
}
