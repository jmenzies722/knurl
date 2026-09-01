import AppKit
import Carbon
import KnurlCore
import KnurlLink
import Observation

@MainActor
@Observable
final class DialState {
    var isPresented = false
    var isNotchExpanded = false
    var control: DialMode = .volume
    var mode: DialMode = Preferences.lastMode
    var message: String?
    var volumePercent = 0
    var brightnessPercent = 70
    var micPercent = 70
    var isMuted = false
    var isMicMuted = false
    var outputName = "Output"
    var outputKind = "Output"
    var outputUID = ""
    var outputDevices: [AudioDevice] = []
    var inputName = "Mic"
    var hotkeyError: String?
    var angle = DialMath.gaugeAngle(progress: 0)
    var tickSound: TickSound = Preferences.sound
    var hapticOn = Preferences.haptic
    let music = NowPlaying()
    let voice = Voice()

    private var lastDetent = -1
    private var scrollCarry = 0.0
    private var previousOutput: AudioDevice?
    private var lastOutputUID: String?
    private var lastObservedLevel: Float = 0
    private var lastObservedMute = false
    private var outputMemory = Preferences.outputMemory
    private let volume = SystemVolume()
    private let outputs = AudioOutputs()
    private let inputs = AudioInputs()
    private let mic = InputGain()
    private var sessionTask: Task<Void, Never>?
    private var editor: NSRunningApplication?

    var volumeProgress: Double { Double(volumePercent) / 100 }

    var controlProgress: Double {
        switch control {
        case .brightness: Double(brightnessPercent) / 100
        case .mic: Double(micPercent) / 100
        case .output: 0.5
        case .media: music.displayedPlayhead()
        case .volume: volumeProgress
        }
    }

    var controlAngle: Double { DialMath.ringAngle(progress: controlProgress) }

    var controlReadout: String {
        switch control {
        case .volume: isMuted ? "Muted" : "\(volumePercent)"
        case .brightness: "\(brightnessPercent)"
        case .mic: isMicMuted ? "Muted" : "\(micPercent)"
        case .output: outputName
        case .media: music.canSeek ? music.timeLabel : music.cardTitle
        }
    }

    var controlTitle: String {
        control == .media ? music.cardTitle : control.title
    }

    var usesRingGauge: Bool {
        control.isGauge || control == .media
    }

    var volumeAngle: Double { DialMath.ringAngle(progress: volumeProgress) }

    var progress: Double {
        switch mode {
        case .volume: volumeProgress
        case .brightness: Double(brightnessPercent) / 100
        case .media: music.playhead
        case .output: 0.5
        case .mic: Double(micPercent) / 100
        }
    }

    var readout: String {
        switch mode {
        case .volume: isMuted ? "Muted" : "\(volumePercent)"
        case .brightness: "\(brightnessPercent)"
        case .media: music.hasTrack ? music.title : "Music"
        case .output: outputName
        case .mic: isMicMuted ? "Muted" : "\(micPercent)"
        }
    }

    var faceLabel: String {
        switch mode {
        case .media: music.artist.isEmpty ? mode.title : music.artist
        case .output: "Output"
        default: mode.title
        }
    }

    func park() {
        isPresented = false
        music.prepare()
        HUDPanel.shared.parkCollapsed()
    }

    func show() {
        rememberEditor()
        refreshMeters()
        message = nil
        isPresented = true
        HUDPanel.shared.show()
        startMeters()
        music.prepare()
    }

    func summon() {
        if isPresented {
            HUDPanel.shared.makeKey()
            return
        }
        show()
    }

    func collapsedPlay() {
        Task {
            await music.toggle()
            message = music.message
        }
    }

    func summonFromMenuBar() {
        if music.hasTrack {
            select(.media, remember: false)
        }
        summon()
    }

    func startSession() {
        lastOutputUID = outputs.current?.uid
        OutputWatch.shared.start { [weak self] in
            self?.handleRouteChange()
        }
        sessionTask?.cancel()
        sessionTask = Task { @MainActor in
            while !Task.isCancelled {
                rememberCurrentVolume()
                music.refresh()
                refreshMeters()
                StatusBar.shared.refresh(self)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func dismiss() {
        if voice.isActive {
            endTalk()
        }
        isPresented = false
        if !isNotchExpanded, !HubWindow.shared.isVisible {
            stopMeters()
        }
        HUDPanel.shared.parkCollapsed()
        restoreEditor()
    }

    func expandNotch() {
        rememberEditor()
        startMeters()
        isNotchExpanded = true
        NotchPanel.shared.expand()
    }

    func collapseNotch() {
        if voice.isActive {
            endTalk()
        }
        isNotchExpanded = false
        NotchPanel.shared.collapse()
        restoreEditor()
        if !isPresented {
            stopMeters()
        }
    }

    func presentHub() {
        expandNotch()
    }

    func hideHub() {
        collapseNotch()
        HubWindow.shared.hide()
    }

    func beginTalk(presentHUD: Bool = true) {
        rememberEditor()
        if isMicMuted {
            toggleMic()
        }
        if control != .mic {
            selectControl(.mic)
        }
        if presentHUD {
            if isPresented {
                HUDPanel.shared.makeKey()
            } else {
                show()
            }
        }
        Task { await voice.start(editor: editor) }
    }

    func endTalk() {
        Task { await voice.stop() }
    }

    func adoptSystemMeters() {
        refreshMeters()
        if mode == .brightness {
            message = "Brightness \(brightnessPercent)"
        }
    }

    func handleSystemDefined(_ event: NSEvent) {
        guard event.subtype == NSEvent.EventSubtype(rawValue: 8) else { return }
        let key = (event.data1 & 0xFFFF0000) >> 16
        let down = ((event.data1 & 0x0000FF00) >> 8) == 0x0A
        guard down else { return }
        switch key {
        case 0, 1, 7:
            refreshMeters()
            if mode == .volume { message = isMuted ? "Muted" : "Volume \(volumePercent)" }
        case 2, 3:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                adoptSystemMeters()
            }
        default:
            break
        }
    }

    enum KeyEscape {
        case dismissHUD
        case hideHub
    }

    @discardableResult
    func handleKey(_ event: NSEvent, escape: KeyEscape = .dismissHUD) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.control) || mods.contains(.command) {
            return false
        }
        switch event.keyCode {
        case UInt16(kVK_Escape):
            switch escape {
            case .dismissHUD:
                dismiss()
            case .hideHub:
                hideHub()
            }
        case UInt16(kVK_Space), UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            confirmDial()
        case UInt16(kVK_LeftArrow), UInt16(kVK_ANSI_LeftBracket), UInt16(kVK_DownArrow), UInt16(kVK_ANSI_Minus):
            rotateControl(-1)
        case UInt16(kVK_RightArrow), UInt16(kVK_ANSI_RightBracket), UInt16(kVK_UpArrow), UInt16(kVK_ANSI_Equal), UInt16(kVK_ANSI_KeypadPlus):
            rotateControl(1)
        case UInt16(kVK_Tab):
            cycleControl(event.modifierFlags.contains(.shift) ? -1 : 1)
        case UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_Keypad1):
            selectControl(.media)
        case UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_Keypad2):
            selectControl(.volume)
        case UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_Keypad3):
            selectControl(.brightness)
        case UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_Keypad4):
            selectControl(.output)
        case UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_Keypad5):
            selectControl(.mic)
        default:
            return false
        }
        return true
    }

    func handleScroll(_ event: NSEvent) {
        guard isPresented else { return }
        if event.phase == .began { scrollCarry = 0 }
        guard event.momentumPhase.isEmpty else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        scrollCarry += dy
        if control == .media, !music.canSeek {
            if scrollCarry <= -28 { scrollCarry = 0; rotateControl(1) }
            else if scrollCarry >= 28 { scrollCarry = 0; rotateControl(-1) }
            return
        }
        if usesRingGauge {
            let applied = scrollCarry
            scrollCarry = 0
            guard abs(applied) > 0.01 else { return }
            let scale = event.hasPreciseScrollingDeltas ? 480.0 : 18.0
            applyControl(controlProgress - applied / scale)
            return
        }
        if scrollCarry <= -28 { scrollCarry = 0; rotateControl(1) }
        else if scrollCarry >= 28 { scrollCarry = 0; rotateControl(-1) }
    }

    func setSound(_ sound: TickSound) {
        tickSound = sound
        Preferences.sound = sound
        DialTick.play(force: true)
    }

    func setHaptic(_ on: Bool) {
        hapticOn = on
        Preferences.haptic = on
        if on { DialTick.play(force: true) }
    }

    func nudge(_ detents: Int) {
        if control != .volume {
            control = .volume
            mode = .volume
            Preferences.lastMode = .volume
        }
        if isPresented {
            HUDPanel.shared.makeKey()
        } else {
            show()
        }
        applyVolume(detents)
    }

    func selectOutput(_ device: AudioDevice) {
        rememberOutput()
        outputs.select(device.id)
        handleRouteChange()
        DialTick.play()
    }

    func turnDial(at location: CGPoint, size: CGSize) {
        let dx = location.x - size.width / 2
        let dy = location.y - size.height / 2
        let degrees = atan2(dx, -dy) * 180 / .pi
        guard let next = DialMath.ringProgress(clockwiseFromNoon: degrees) else { return }
        if control == .media, !music.canSeek { return }
        guard DialMath.acceptsGaugeJump(from: controlProgress, to: next) else { return }
        applyControl(next)
    }

    func selectControl(_ next: DialMode) {
        if control == .mic, next != .mic, voice.isActive {
            endTalk()
        }
        control = next
        mode = next
        Preferences.lastMode = next
        if next == .media {
            Task { await music.authorizeIfNeeded() }
        }
        DialTick.play()
    }

    func playSource(_ id: String) {
        Task {
            await music.playSource(id)
            message = music.message
        }
        DialTick.play()
    }

    func toggleShuffle() {
        music.toggleShuffle()
        DialTick.play()
    }

    func cycleRepeat() {
        music.cycleRepeat()
        DialTick.play()
    }

    func revealMusic() {
        music.revealMusic()
    }

    func cycleControl(_ delta: Int) {
        selectControl(control.advanced(by: delta))
    }

    func confirmDial() {
        switch control {
        case .volume: toggleMute()
        case .brightness: setRoomBrightness(0.5)
        case .mic: toggleMic()
        case .output: swapSpeaker()
        case .media: collapsedPlay()
        }
    }

    func rotateControl(_ detents: Int) {
        switch control {
        case .volume: applyVolume(detents)
        case .brightness:
            DisplayBrightness.step(detents)
            refreshMeters()
        case .mic: applyMic(detents)
        case .output: cycleSpeaker(detents)
        case .media: skip(detents > 0 ? 1 : -1)
        }
    }

    func applyControl(_ value: Double) {
        switch control {
        case .volume: setRoomVolume(value)
        case .brightness: setRoomBrightness(value)
        case .mic: setRoomMic(value)
        case .output:
            if value > 0.62 { cycleSpeaker(1) }
            else if value < 0.38 { cycleSpeaker(-1) }
        case .media:
            music.seek(to: value)
        }
    }

    func cycleInput(_ detents: Int) {
        inputs.cycle(by: detents)
        refreshMeters()
        DialTick.play()
    }

    func setRoomVolume(_ value: Double) {
        let clamped = DialMath.clampVolume(value)
        if volume.isMuted { volume.isMuted = false }
        volume.level = Float(clamped)
        refreshMeters()
        rememberCurrentVolume()
        let detent = TickSound.detent(from: clamped)
        if detent != lastDetent {
            lastDetent = detent
            DialTick.play()
        }
    }

    func setRoomBrightness(_ value: Double) {
        let clamped = DialMath.clampVolume(value)
        if !DisplayBrightness.set(clamped) {
            let steps = TickSound.detent(from: clamped) - lastDetent
            if steps != 0 { DisplayBrightness.step(steps) }
        }
        refreshMeters()
    }

    func setRoomMic(_ value: Double) {
        let clamped = DialMath.clampVolume(value)
        if mic.isMuted { mic.isMuted = false }
        mic.level = Float(clamped)
        refreshMeters()
    }

    func toggleMute() {
        volume.isMuted.toggle()
        refreshMeters()
        rememberCurrentVolume()
        DialTick.play()
    }

    func toggleMic() {
        mic.isMuted.toggle()
        refreshMeters()
        DialTick.play()
    }

    func cycleSpeaker(_ detents: Int) {
        rememberOutput()
        outputs.cycle(by: detents)
        handleRouteChange()
        DialTick.play()
    }

    func swapSpeaker() {
        swapOutput()
        DialTick.play()
    }

    func setGauge(_ value: Double, track: Bool = false) {
        if !track {
            guard DialMath.acceptsGaugeJump(from: progress, to: value) else { return }
        }
        let clamped = DialMath.clampVolume(value)
        let detent = TickSound.detent(from: clamped)
        switch mode {
        case .volume:
            if volume.isMuted { volume.isMuted = false }
            volume.level = Float(clamped)
            volumePercent = DialMath.percent(clamped)
            isMuted = false
            message = "Volume \(volumePercent)"
        case .brightness:
            if !DisplayBrightness.set(clamped) {
                let steps = detent - lastDetent
                if steps != 0 { DisplayBrightness.step(steps) }
            }
            brightnessPercent = DialMath.percent(DisplayBrightness.read() ?? clamped)
            message = "Brightness \(brightnessPercent)"
        case .mic:
            if mic.isMuted { mic.isMuted = false }
            mic.level = Float(clamped)
            micPercent = DialMath.percent(clamped)
            isMicMuted = false
            message = "Mic \(micPercent)"
        default:
            break
        }
        syncAngle()
        if detent != lastDetent {
            lastDetent = detent
            DialTick.play()
        }
    }

    func rotate(_ detents: Int) {
        guard detents != 0 else { return }
        switch mode {
        case .volume:
            applyVolume(detents)
        case .brightness:
            DisplayBrightness.step(detents)
            brightnessPercent = DialMath.percent(DisplayBrightness.read() ?? DisplayBrightness.estimate)
            message = "Brightness \(brightnessPercent)"
        case .media:
            skip(detents > 0 ? 1 : -1)
        case .output:
            rememberOutput()
            outputs.cycle(by: detents)
            handleRouteChange()
            message = outputName
        case .mic:
            applyMic(detents)
        }
        lastDetent = TickSound.detent(from: progress)
        syncAngle()
        DialTick.play()
    }

    func confirm() {
        switch mode {
        case .volume:
            volume.isMuted.toggle()
            refreshMeters()
            rememberCurrentVolume()
            message = isMuted ? "Muted" : "Unmuted"
        case .brightness:
            if !DisplayBrightness.set(0.5) {
                let steps = TickSound.detent(from: 0.5) - TickSound.detent(from: progress)
                if steps != 0 { DisplayBrightness.step(steps) }
            }
            brightnessPercent = DialMath.percent(DisplayBrightness.read() ?? 0.5)
            message = "Halfway"
        case .media:
            Task {
                await music.toggle()
                message = music.message ?? (music.isPlaying ? "Playing \(music.title)" : "Paused")
            }
        case .output:
            swapOutput()
        case .mic:
            mic.isMuted.toggle()
            refreshMeters()
            message = isMicMuted ? "Mic muted" : "Mic live"
        }
        syncAngle()
        DialTick.play()
    }

    func skip(_ direction: Int) {
        Task {
            await music.skip(direction)
            message = music.message
        }
        DialTick.play()
    }

    func select(_ mode: DialMode, remember: Bool = true) {
        self.mode = mode
        if remember { Preferences.lastMode = mode }
        refreshMeters()
        message = mode.hint
        if mode == .media {
            music.prepare()
            message = music.message ?? mode.hint
        }
        syncAngle()
        DialTick.play()
    }

    func cycleMode(_ delta: Int) {
        select(mode.advanced(by: delta))
    }

    func applyCrown(_ request: CrownRequest) {
        if !isPresented { show() }
        switch request.action {
        case .rotate:
            rotate(request.detents ?? 1)
        case .confirm:
            confirm()
        case .select:
            if let raw = request.mode, let next = DialMode(rawValue: raw) {
                select(next)
            }
        case .hello:
            break
        }
        CrownServer.shared.broadcast()
    }

    func crownHello() -> CrownHello {
        CrownHello(
            host: ProcessInfo.processInfo.hostName,
            mode: mode.rawValue,
            readout: readout,
            progress: progress,
            target: faceLabel
        )
    }

    func openMusicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyVolume(_ detents: Int) {
        let before = volume.level
        if volume.isMuted {
            volume.isMuted = false
        }
        let next = DialMath.steppedVolume(current: Double(before), detents: detents)
        volume.level = Float(next)
        if abs(volume.level - before) < 0.01 {
            if detents > 0 { HardwareKeys.soundUp() } else { HardwareKeys.soundDown() }
        }
        refreshMeters()
        rememberCurrentVolume()
        message = isMuted ? "Muted — click the dial." : "Volume \(volumePercent)"
    }

    private func applyMic(_ detents: Int) {
        if mic.isMuted { mic.isMuted = false }
        let next = DialMath.steppedVolume(current: Double(mic.level), detents: detents)
        mic.level = Float(next)
        refreshMeters()
        message = isMicMuted ? "Mic muted" : "Mic \(micPercent)"
    }

    private func rememberOutput() {
        if previousOutput == nil {
            previousOutput = outputs.current
        }
    }

    private func swapOutput() {
        let current = outputs.current
        if let previousOutput, previousOutput.id != current?.id {
            outputs.select(previousOutput.id)
            self.previousOutput = current
        } else {
            rememberOutput()
            outputs.cycle(by: 1)
        }
        handleRouteChange()
        message = outputName
    }

    private var meterTask: Task<Void, Never>?

    private func startMeters() {
        DisplayBrightness.watch()
        meterTask?.cancel()
        meterTask = Task { @MainActor in
            while !Task.isCancelled, isPresented {
                refreshMeters()
                try? await Task.sleep(for: .milliseconds(280))
            }
        }
    }

    private func stopMeters() {
        meterTask?.cancel()
        meterTask = nil
        DisplayBrightness.unwatch()
    }

    private func refreshMeters() {
        volumePercent = DialMath.percent(Double(volume.level))
        isMuted = volume.isMuted
        if let live = DisplayBrightness.read() {
            DisplayBrightness.estimate = live
            brightnessPercent = DialMath.percent(live)
        }
        outputName = outputs.current?.name ?? "No output"
        outputKind = outputs.current?.transport.title ?? "Output"
        outputUID = outputs.current?.uid ?? ""
        outputDevices = outputs.devices()
        inputName = inputs.current?.name ?? mic.deviceName
        micPercent = DialMath.percent(Double(mic.level))
        isMicMuted = mic.isMuted
        music.refresh()
        lastDetent = TickSound.detent(from: progress)
        syncAngle()
        rememberCurrentVolume()
        StatusBar.shared.refresh(self)
    }

    private func rememberCurrentVolume() {
        guard let uid = outputs.current?.uid else { return }
        if let lastOutputUID, lastOutputUID != uid {
            return
        }
        lastObservedLevel = volume.level
        lastObservedMute = volume.isMuted
        lastOutputUID = uid
        let before = outputMemory.recall(uid: uid)
        outputMemory.remember(uid: uid, level: lastObservedLevel, muted: lastObservedMute)
        if outputMemory.recall(uid: uid) != before {
            Preferences.outputMemory = outputMemory
        }
    }

    private func handleRouteChange() {
        let next = outputs.current?.uid
        if let lastOutputUID, lastOutputUID != next {
            outputMemory.remember(uid: lastOutputUID, level: lastObservedLevel, muted: lastObservedMute)
            Preferences.outputMemory = outputMemory
        }
        lastOutputUID = next
        if let next, let snapshot = outputMemory.recall(uid: next) {
            volume.level = snapshot.level
            volume.isMuted = snapshot.muted
        }
        refreshMeters()
        outputName = outputs.current?.name ?? "No output"
        if isPresented, mode == .output {
            message = outputName
        }
    }

    private func rememberEditor() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            editor = front
        }
    }

    private func restoreEditor() {
        editor?.activate()
    }

    private func syncAngle() {
        angle = DialMath.gaugeAngle(progress: progress)
    }
}
