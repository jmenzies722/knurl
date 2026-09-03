import AppKit
import Carbon
import KnurlCore
import KnurlLink
import Observation
import ServiceManagement

@MainActor
@Observable
final class DialState {
    var isPresented = false
    var isNotchExpanded = false
    var notchHovered = false
    var notchPeeking = false
    /// Real window visibility, not intent. Everything with a timeline reads
    /// this through `\.knurlOnScreen` so a hidden surface costs nothing.
    var hubVisible = false
    var hudVisible = false
    private var notchPeek: Task<Void, Never>?

    /// How much of the notch is showing. Derived rather than stored so the
    /// panel, the shape and the content can never disagree about which stage
    /// they are drawing — the bug that made the first version flicker.
    var notchStage: NotchStage {
        if voice.isActive { return .flow }
        if isNotchExpanded { return .shelf }
        if notchHovered || notchPeeking { return .hover }
        // Only show a line when there is genuinely something to report.
        // Idle, the notch is the notch.
        if desk.timer.running || music.isPlaying || !desk.attention.isEmpty {
            return .glance
        }
        return .rest
    }
    var notchHousing = CGRect.zero
    var notchExpanded = CGRect.zero
    var control: DialMode = Preferences.lastMode
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
    var harnessName = "Mac"
    var wantsSettings = false
    var pillHovered = false
    /// The pill morphs between its controls and the six Hub pages rather than
    /// spawning a second navigator window.
    var pillShowsPages = false
    /// Non-nil when the dial menu is showing a tool's crown instead of a face.
    var activeTool: DeskTool?
    var hubOrder: [HubPage] = Preferences.hubOrder {
        didSet { Preferences.hubOrder = hubOrder }
    }
    var launchesAtLogin = LoginItem.isEnabled
    var showsMenuBarItem = Preferences.menuBarItem
    var loginItemError: String?
    var inputUID = ""
    var inputDevices: [AudioDevice] = []
    var roomDimmed = false
    private var hourOwnsDim = false
    let music = NowPlaying()
    let voice = Voice()
    let desk = DeskContext()

    var hubPage: HubPage {
        get { desk.page }
        set { desk.page = newValue }
    }

    private var lastDetent = -1
    private var scrollCarry = 0.0
    private var previousOutput: AudioDevice?
    private var lastOutputUID: String?
    private var brightnessBeforeDim: Double?
    private var lastObservedLevel: Float = 0
    private var lastObservedMute = false
    private var outputMemory = Preferences.outputMemory
    private var airPlayMemory = Preferences.airPlayMemory
    private var pendingAirPlay: AudioDevice?
    private var outputSweep: Double?
    private var airPlayConnectTask: Task<Void, Never>?
    private var airPlayConnectGeneration = 0
    private var airPlayConnecting = false
    private var outputSettleTask: Task<Void, Never>?
    private var musicAirPlay: [MusicAirPlayDevice] = []
    private var lastAirPlayPull = Date.distantPast
    private var airPlayPull: Task<Void, Never>?
    private let volume = SystemVolume()
    private let outputs = AudioOutputs()
    private let inputs = AudioInputs()
    private let mic = InputGain()
    private var sessionTask: Task<Void, Never>?
    private var editor: NSRunningApplication?
    private var lastCrownSignature = ""
    private var lastCrownPush = Date.distantPast
    private var outputRosterFrozen = false
    private var outputFrozenAt: Date?

    var volumeProgress: Double { Double(volumePercent) / 100 }

    /// One short line describing the current face, for the parked pill.
    var collapsedLine: String {
        switch control {
        case .volume: isMuted ? "Muted" : "\(volumePercent)"
        case .brightness: "\(brightnessPercent)"
        case .mic: isMicMuted ? "Muted" : "\(micPercent)"
        case .output: outputName
        case .media: music.hasTrack ? music.title : "Nothing playing"
        }
    }

    var controlProgress: Double {
        switch control {
        case .brightness: Double(brightnessPercent) / 100
        case .mic: Double(micPercent) / 100
        case .output: outputProgress
        case .media: music.displayedPlayhead()
        case .volume: volumeProgress
        }
    }

    var outputIndex: Int {
        outputDevices.firstIndex(where: { $0.uid == outputUID }) ?? 0
    }

    var outputProgress: Double {
        if let outputSweep { return outputSweep }
        return DialMath.detentProgress(index: outputIndex, count: outputDevices.count)
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
        control.isGauge || control == .media || control == .output
    }

    var volumeAngle: Double { DialMath.ringAngle(progress: volumeProgress) }

    var progress: Double {
        switch mode {
        case .volume: volumeProgress
        case .brightness: Double(brightnessPercent) / 100
        case .media: music.playhead
        case .output: outputProgress
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

    /// Cold start, and every dismissal.
    func park() {
        music.prepare()
        parkSurface()
    }

    /// Where this Mac parks: the notch if it has a housing, the pill above the
    /// Dock if it does not.
    ///
    /// Every path that parks goes through here. `dismiss()` used to call
    /// `HUDPanel.parkCollapsed()` directly, which is why the pill kept
    /// reappearing over the Dock on a notched Mac — one code path respected
    /// the notch and the other did not.
    func parkSurface() {
        isPresented = false
        if hasNotchHousing {
            HUDPanel.shared.hide()
        } else {
            HUDPanel.shared.parkCollapsed()
        }
    }

    /// Show the dial on whichever surface this Mac parks on.
    ///
    /// A turn on the iPhone crown, or a menu-bar summon, should light the
    /// notch on a notched Mac rather than throwing a panel over the Dock.
    /// `show()` is still the right answer where there is no housing.
    func revealDial() {
        if hasNotchHousing {
            peekNotch()
        } else {
            show()
        }
    }

    /// Open the notch for a moment, then let it settle back on its own.
    ///
    /// Tracked separately from `notchHovered` so it cannot fight the pointer:
    /// the hover monitor owns that flag, and a peek expiring must not close a
    /// notch the pointer is still sitting in.
    func peekNotch(for seconds: Double = 2.4) {
        notchPeeking = true
        notchPeek?.cancel()
        notchPeek = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notchPeeking = false
        }
    }

    func show() {
        if !voice.isActive {
            rememberEditor()
        }
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

    func noteCrownClient() {
        startMeters()
    }

    func startSession() {
        lastOutputUID = outputs.current?.uid
        desk.start()
        voice.deliver = { [weak self] text in
            await self?.landFlow(text)
        }
        adoptHarness()
        OutputWatch.shared.start { [weak self] in
            self?.handleRouteChange()
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppDelegate.shared?.state.adoptHarness()
            }
        }
        sessionTask?.cancel()
        sessionTask = Task { @MainActor in
            while !Task.isCancelled {
                rememberCurrentVolume()
                music.attentive = isPresented
                    || HubWindow.shared.isVisible
                    || notchStage.isOpen
                if music.needsPoll { music.refresh() }
                refreshMeters()
                tickHour()
                StatusBar.shared.refresh(self)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func dismiss() {
        if voice.isActive {
            cancelTalk()
        }
        if !HubWindow.shared.isVisible {
            stopMeters()
        }
        parkSurface()
        restoreEditor()
    }

    func toggleNotch() {
        if isNotchExpanded {
            collapseNotch()
        } else {
            expandNotch()
        }
    }

    func expandNotch(flow: Bool = false) {
        isNotchExpanded = true
        NotchPanel.shared.expand(flow: flow || voice.isActive)
    }

    func collapseNotch() {
        isNotchExpanded = false
        NotchPanel.shared.collapse()
    }

    func presentHub() {
        if !voice.isActive {
            rememberEditor()
        }
        if hasNotchHousing {
            collapseNotch()
        }
        startMeters()
        HubWindow.shared.show()
    }

    func dismissSettings() {
        wantsSettings = false
    }

    func hideHub() {
        wantsSettings = false
        HubWindow.shared.hide()
        noteHubClosed()
    }

    func noteHubClosed() {
        wantsSettings = false
        if isPresented {
            HUDPanel.shared.makeKey()
        } else {
            restoreEditor()
            stopMeters()
        }
    }

    var swapLabel: String {
        if let previousOutput, previousOutput.uid != outputUID {
            return "Swap to \(previousOutput.name)"
        }
        return "Swap"
    }

    var talkDestination: String {
        "Words land in \(harnessName)"
    }

    var outputMemoryLine: String? {
        guard let uid = outputs.current?.uid, let snapshot = outputMemory.recall(uid: uid) else {
            return nil
        }
        if snapshot.muted {
            return "Remembered muted for this speaker"
        }
        return "Remembered \(DialMath.percent(Double(snapshot.level)))% for this speaker"
    }

    func selectInput(_ device: AudioDevice) {
        inputs.select(device.id)
        refreshMeters()
        DialTick.play()
    }

    func setShowsMenuBarItem(_ on: Bool) {
        showsMenuBarItem = on
        Preferences.menuBarItem = on
        StatusBar.shared.setVisible(on)
    }

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            launchesAtLogin = LoginItem.isEnabled
            loginItemError = LoginItem.isEnabled || !on
                ? nil
                : "Allow Knurl under System Settings → General → Login Items."
        } catch {
            launchesAtLogin = LoginItem.isEnabled
            switch SMAppService.mainApp.status {
            case .requiresApproval:
                loginItemError = "Allow Knurl under System Settings → General → Login Items."
            case .notFound:
                loginItemError = "Launch at Login needs the packaged Knurl.app."
            default:
                loginItemError = error.localizedDescription
            }
        }
    }

    enum FlowOrigin {
        case hud
        case notch
    }

    private(set) var flowOrigin: FlowOrigin?
    private var flowCollapseTask: Task<Void, Never>?

    var hasNotchHousing: Bool { NotchPanel.shared.hasHousing }

    func beginTalkFromHotkey() {
        beginTalk(presentHUD: !hasNotchHousing)
    }

    func beginTalk(presentHUD: Bool = true) {
        if voice.isActive { return }
        rememberEditor()
        if isMicMuted {
            toggleMic()
        }
        flowCollapseTask?.cancel()
        if presentHUD, control != .mic {
            selectControl(.mic)
        }
        flowOrigin = presentHUD ? .hud : .notch
        if presentHUD {
            if isPresented {
                HUDPanel.shared.makeKey()
            } else {
                show()
            }
        } else if hasNotchHousing {
            expandNotch(flow: true)
            NotchPanel.shared.watchFlowEscape()
        }
        desk.noteFlowStart()
        Task { await voice.start(editor: editor) }
    }

    func endTalk() {
        if voice.discarded { return }
        let origin = flowOrigin
        Task {
            await voice.stop()
            desk.noteFlowEnd(characters: voice.lastTranscript.count)
            settleFlowDetent(origin)
        }
    }

    func toggleTalk(presentHUD: Bool = true) {
        if voice.isActive {
            endTalk()
        } else {
            beginTalk(presentHUD: presentHUD)
        }
    }

    func cancelTalk() {
        voice.beginCancel()
        Task {
            await voice.cancel()
            flowOrigin = nil
            NotchPanel.shared.ignoreEscape()
            if hasNotchHousing {
                collapseNotch()
            }
        }
    }

    func escapeNotch() {
        if voice.isActive {
            cancelTalk()
        } else {
            collapseNotch()
        }
    }

    private func settleFlowDetent(_ origin: FlowOrigin?) {
        flowOrigin = nil
        NotchPanel.shared.ignoreEscape()
        guard origin == .notch, hasNotchHousing, isNotchExpanded else { return }
        flowCollapseTask?.cancel()
        flowCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !voice.isActive else { return }
            collapseNotch()
        }
    }

    func resendTalk() {
        voice.resend()
    }

    func jumpToHarness() {
        restoreEditor()
    }

    /// Wispr-style handoff: leave Knurl, activate the dest, paste at the caret.
    /// Never posts ⌘V into Knurl itself — that is the “paste bar” miss.
    func landFlow(_ text: String) async {
        guard !voice.discarded else { return }
        HUDPanel.shared.resignForTarget()
        HubWindow.shared.resignKey()
        if isPresented {
            park()
        }
        let dest = editor
        let knurl = Bundle.main.bundleIdentifier
        guard let dest, dest.bundleIdentifier != knurl else {
            voice.message = "No editor to land in — your words are on the clipboard, press ⌘V."
            return
        }
        dest.activate()
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == dest.processIdentifier {
                break
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(50))
        guard !voice.discarded else { return }
        // Never claim it landed when macOS will not let it land.
        guard Voice.canPaste else {
            voice.message = "Knurl needs Accessibility to paste. Your words are on the clipboard — press ⌘V."
            return
        }
        voice.postPaste()
        voice.message = "Landed in \(harnessName)"
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
            if voice.isActive {
                cancelTalk()
                return true
            }
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
        if activeTool == .hour {
            let applied = scrollCarry
            scrollCarry = 0
            guard abs(applied) > 0.01 else { return }
            let scale = event.hasPreciseScrollingDeltas ? 480.0 : 18.0
            turnTool(DialMath.clampVolume(toolProgress - applied / scale))
            return
        }
        if activeTool != nil {
            if scrollCarry <= -28 { scrollCarry = 0; rotateTool(1) }
            else if scrollCarry >= 28 { scrollCarry = 0; rotateTool(-1) }
            return
        }
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
            applyControl(controlProgress - applied / scale, settleOutput: true)
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

    func pickOutput(_ device: AudioDevice) {
        outputSweep = nil
        selectOutput(device, commit: true)
    }

    func selectOutput(_ device: AudioDevice, commit: Bool = true) {
        rememberOutput()
        previewOutput(device)
        if isMusicAirPlay(device) {
            if commit {
                scheduleMusicAirPlay(device)
            } else {
                pendingAirPlay = device
            }
            DialTick.play()
            return
        }
        cancelAirPlayConnect()
        pendingAirPlay = nil
        if outputs.select(device) {
            if MusicApp.isOpen {
                MusicApp.selectComputerAirPlay()
            }
            handleRouteChange()
        }
        DialTick.play()
    }

    private func isMusicAirPlay(_ device: AudioDevice) -> Bool {
        device.uid.hasPrefix(MusicAirPlayDevice.uidPrefix)
            || (device.transport == .airPlay && device.id == 0)
    }

    private func previewOutput(_ device: AudioDevice) {
        outputName = device.name
        if isMusicAirPlay(device) {
            outputKind = "HomePod"
            outputUID = device.uid.hasPrefix(MusicAirPlayDevice.uidPrefix)
                ? device.uid
                : MusicAirPlayDevice.uidPrefix + device.name
        } else {
            outputKind = device.transport.title
            outputUID = device.uid
        }
    }

    private func cancelAirPlayConnect() {
        airPlayConnectGeneration += 1
        airPlayConnectTask?.cancel()
        airPlayConnectTask = nil
        airPlayConnecting = false
    }

    private func scheduleMusicAirPlay(_ device: AudioDevice) {
        pendingAirPlay = nil
        cancelAirPlayConnect()
        freezeOutputRoster()
        airPlayConnecting = true
        airPlayConnectGeneration += 1
        let generation = airPlayConnectGeneration
        airPlayConnectTask = Task {
            defer {
                if generation == airPlayConnectGeneration {
                    airPlayConnectTask = nil
                    airPlayConnecting = false
                }
            }
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await connectMusicAirPlay(device)
        }
    }

    private func connectMusicAirPlay(_ device: AudioDevice) async {
        await MusicApp.ensureOpen()
        guard !Task.isCancelled else { return }
        pullMusicAirPlay(force: true)
        guard MusicApp.selectAirPlay(device.name) else {
            guard !Task.isCancelled else { return }
            message = MusicApp.lastError ?? "Couldn’t reach \(device.name)"
            thawOutputRoster()
            AirPlayGate.shared.present()
            refreshMeters()
            return
        }
        guard !Task.isCancelled else { return }
        rememberAirPlay(device)
        MusicApp.setAirPlayVolume(device.name, percent: volumePercent)
        previewOutput(device)
        outputUID = MusicAirPlayDevice.uidPrefix + device.name
        outputKind = "HomePod"
        message = device.name
        pullMusicAirPlay(force: true)
        if musicAirPlay.contains(where: { $0.selected && $0.kind != .computer && $0.name == device.name }) {
            thawOutputRoster()
        }
        adoptOutputDevices(outputRoster())
    }

    func setOutputProgress(_ value: Double, settle: Bool = false) {
        freezeOutputRoster()
        outputSweep = DialMath.clampVolume(value)
        let roster = outputDevices.isEmpty ? outputRoster() : outputDevices
        if outputDevices.isEmpty { outputDevices = roster }
        let index = DialMath.detentIndex(progress: outputSweep ?? value, count: roster.count)
        guard roster.indices.contains(index) else { return }
        if roster[index].uid != outputUID {
            selectOutput(roster[index], commit: true)
        }
        if settle {
            scheduleOutputSettle()
        }
    }

    func finishOutputTurn() {
        outputSettleTask?.cancel()
        outputSweep = nil
        if let pending = pendingAirPlay {
            pendingAirPlay = nil
            selectOutput(pending, commit: true)
            return
        }
        if airPlayConnecting {
            return
        }
        thawOutputRoster()
        refreshMeters()
    }

    private func freezeOutputRoster() {
        if !outputRosterFrozen {
            outputFrozenAt = Date()
        }
        outputRosterFrozen = true
    }

    private func thawOutputRoster() {
        outputRosterFrozen = false
        outputFrozenAt = nil
    }

    private func scheduleOutputSettle() {
        outputSettleTask?.cancel()
        outputSettleTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            finishOutputTurn()
        }
    }

    func turnDial(at location: CGPoint, size: CGSize) {
        let dx = location.x - size.width / 2
        let dy = location.y - size.height / 2
        let degrees = atan2(dx, -dy) * 180 / .pi
        guard let next = DialMath.ringProgress(clockwiseFromNoon: degrees) else { return }
        if activeTool != nil {
            turnTool(next)
            return
        }
        if control == .media, !music.canSeek { return }
        applyControl(next, settleOutput: false)
    }

    func selectControl(_ next: DialMode) {
        activeTool = nil
        if control == .mic, next != .mic, flowOrigin == .hud {
            endTalk()
        }
        control = next
        mode = next
        Preferences.lastMode = next
        if next == .media {
            Task { await music.authorizeIfNeeded() }
        }
        if next == .output {
            pullMusicAirPlay(force: true)
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
        if activeTool != nil {
            confirmTool()
            return
        }
        switch control {
        case .volume: toggleMute()
        case .brightness: setRoomBrightness(0.5)
        case .mic: toggleMic()
        case .output: swapSpeaker()
        case .media: collapsedPlay()
        }
    }

    func rotateControl(_ detents: Int) {
        // A tool owns the crown while it is up. Without this, scroll and the
        // arrow keys kept driving the face underneath, so scrubbing the Hour
        // also moved volume or brightness.
        if activeTool != nil {
            rotateTool(detents)
            return
        }
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

    func applyControl(_ value: Double, settleOutput: Bool = true) {
        switch control {
        case .volume: setRoomVolume(value)
        case .brightness: setRoomBrightness(value)
        case .mic: setRoomMic(value)
        case .output:
            setOutputProgress(value, settle: settleOutput)
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
        if outputUID.hasPrefix(MusicAirPlayDevice.uidPrefix) {
            let name = String(outputUID.dropFirst(MusicAirPlayDevice.uidPrefix.count))
            MusicApp.setAirPlayVolume(name, percent: DialMath.percent(clamped))
        }
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
        micPercent = DialMath.percent(clamped)
        isMicMuted = false
        if mic.hasScalar {
            refreshMeters()
        }
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
        outputSweep = nil
        let roster = outputDevices.isEmpty ? outputRoster() : outputDevices
        guard !roster.isEmpty else { return }
        if outputDevices.isEmpty { outputDevices = roster }
        let count = roster.count
        let next = ((outputIndex + detents) % count + count) % count
        selectOutput(roster[next], commit: true)
    }

    func swapSpeaker() {
        swapOutput()
    }

    func tickHour() {
        if desk.timer.tick(now: Date()) {
            finishHour()
        }
    }

    func selectTool(_ tool: DeskTool?) {
        activeTool = tool
        DialTick.play()
    }

    /// Turning or clicking the crown of whichever tool is showing. Keeps the
    /// tool switch in one place so a new tool only adds cases here.
    func turnTool(_ value: Double) {
        switch activeTool {
        case .hour:
            setHourCrown(value)
        case .power:
            let modes = PowerMode.allCases
            let index = min(modes.count - 1, max(0, Int(value * Double(modes.count - 1) + 0.5)))
            if desk.powerMode != modes[index] {
                desk.powerMode = modes[index]
                DialTick.play()
            }
        case nil:
            break
        }
    }

    /// One detent of the active tool's crown, for scroll and arrow keys.
    func rotateTool(_ detents: Int) {
        switch activeTool {
        case .hour:
            setHourDuration(desk.timer.duration + Double(detents) * 60)
        case .power:
            let modes = PowerMode.allCases
            guard let index = modes.firstIndex(of: desk.powerMode) else { return }
            let next = min(modes.count - 1, max(0, index + detents))
            if modes[next] != desk.powerMode {
                desk.powerMode = modes[next]
                DialTick.play()
            }
        case nil:
            break
        }
    }

    func confirmTool() {
        switch activeTool {
        case .hour: toggleHour()
        case .power: rotateTool(1)
        case nil: break
        }
    }

    var toolReadout: String {
        switch activeTool {
        case .hour: desk.timer.readout
        case .power: desk.powerMode.title
        case nil: ""
        }
    }

    var toolCaption: String {
        switch activeTool {
        case .hour: desk.timer.running ? "Running" : "Set"
        case .power: "\(desk.power.snapshot.percentLabel) · \(desk.power.snapshot.chargeLabel)"
        case nil: ""
        }
    }

    var toolSymbol: String {
        switch activeTool {
        case .hour:
            desk.timer.running ? "pause.fill" : "play.fill"
        case .power:
            switch desk.powerMode {
            case .battery: "leaf.fill"
            case .balanced: "bolt.fill"
            case .performance: "bolt.horizontal.fill"
            }
        case nil:
            "circle"
        }
    }

    var toolProgress: Double {
        switch activeTool {
        case .hour:
            return desk.timer.crownProgress
        case .power:
            let modes = PowerMode.allCases
            let index = modes.firstIndex(of: desk.powerMode) ?? 0
            return Double(index) / Double(max(modes.count - 1, 1))
        case nil:
            return 0
        }
    }

    func setHourCrown(_ value: Double) {
        if desk.timer.setCrown(value) {
            finishHour()
        }
    }

    func setHourDuration(_ seconds: TimeInterval) {
        desk.timer.setDuration(seconds)
        if hourOwnsDim, !desk.timer.running {
            restoreHourDim()
        }
    }

    func toggleHour() {
        if desk.timer.running {
            if desk.timer.pause() {
                finishHour()
            }
        } else {
            desk.timer.start()
            desk.noteTimerStarted()
            DialTick.play()
        }
    }

    func startTheHour() {
        desk.timer.setDuration(50 * 60)
        desk.timer.start()
        desk.noteTimerStarted()
        hourOwnsDim = true
        setRoomDim(true)
        DialTick.play()
    }

    func resetHour() {
        desk.timer.reset()
        restoreHourDim()
    }

    func finishHour() {
        restoreHourDim()
        desk.timer.reset()
        DialTick.play()
        desk.noteTimerEnded()
        message = "Hour done"
    }

    private func restoreHourDim() {
        if hourOwnsDim {
            hourOwnsDim = false
            if roomDimmed {
                setRoomDim(false)
            }
        }
    }

    func setRoomDim(_ on: Bool) {
        if on {
            if !roomDimmed {
                brightnessBeforeDim = Double(brightnessPercent) / 100
            }
            roomDimmed = true
            setRoomBrightness(0.18)
        } else {
            hourOwnsDim = false
            roomDimmed = false
            if let prior = brightnessBeforeDim {
                setRoomBrightness(prior)
            }
            brightnessBeforeDim = nil
        }
    }

    func toggleRoomDim() {
        setRoomDim(!roomDimmed)
    }

    var menuBarLive: MenuBarLive {
        MenuBarLive.snapshot(
            listening: voice.isActive,
            attention: desk.attention.first?.provider.title,
            musicTitle: music.hasTrack ? music.title : nil,
            musicPlaying: music.isPlaying,
            outputName: outputName,
            timerRemaining: desk.timer.whisper,
            destination: harnessName
        )
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
            cycleSpeaker(detents)
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
        switch request.action {
        case .talkStart:
            beginTalk(presentHUD: false)
        case .talkEnd:
            endTalk()
        case .talkCancel:
            cancelTalk()
        default:
            if !isPresented, !HubWindow.shared.isVisible { revealDial() }
            applyCrownControl(request)
        }
        CrownServer.shared.broadcast()
    }

    private func applyCrownControl(_ request: CrownRequest) {
        switch request.action {
        case .rotate:
            if let progress = request.progress {
                if activeTool != nil {
                    turnTool(progress)
                } else {
                    applyControl(progress)
                }
            } else {
                rotateControl(request.detents ?? 1)
            }
        case .confirm:
            confirmDial()
        case .select:
            if let raw = request.mode, let next = DialMode(rawValue: raw) {
                selectControl(next)
            }
        case .hello, .talkStart, .talkEnd, .talkCancel:
            break
        case .skip:
            skip(request.detents ?? 1)
        case .shuffle:
            toggleShuffle()
        case .repeat:
            cycleRepeat()
        case .pick:
            if let name = request.name, !name.isEmpty {
                pickCrown(name)
            }
        }
    }

    private func pickCrown(_ name: String) {
        switch control {
        case .media:
            playSource(name)
        case .output:
            if let device = outputDevices.first(where: { $0.uid == name }) {
                selectOutput(device)
            }
        case .mic:
            if let device = inputDevices.first(where: { $0.uid == name }) {
                selectInput(device)
            }
        default:
            break
        }
    }

    private var cachedCoverTitle = ""
    private var cachedCover: (key: String, jpeg: Data)?

    func coverJPEG() -> (key: String, jpeg: Data)? {
        guard control == .media else { return nil }
        let title = music.title
        if title == cachedCoverTitle { return cachedCover }
        guard let image = music.cover ?? MusicApp.artwork() else {
            cachedCoverTitle = title
            cachedCover = nil
            return nil
        }
        let made = CoverJPEG.make(from: image)
        cachedCoverTitle = title
        cachedCover = made
        return made
    }

    func crownHello() -> CrownHello {
        let media = control == .media
        return CrownHello(
            host: ProcessInfo.processInfo.hostName,
            mode: control.rawValue,
            readout: controlReadout,
            progress: controlProgress,
            target: media
                ? (music.artist.isEmpty ? control.title : music.artist)
                : control.title,
            muted: (control == .volume && isMuted) || (control == .mic && isMicMuted),
            playing: music.isPlaying,
            duration: music.canSeek ? music.duration : nil,
            title: media ? music.cardTitle : nil,
            album: media && !music.album.isEmpty ? music.album : nil,
            genre: media && !music.genre.isEmpty ? music.genre : nil,
            shuffle: media ? music.shuffleOn : nil,
            repeat: media ? music.repeatMode.rawValue : nil,
            artKey: nil,
            art: nil,
            playlists: media
                ? Array(
                    music.sources.filter { $0.kind == .playlist }.map(\.title).prefix(32)
                ).map { String($0.prefix(40)) }
                : nil,
            devices: crownDevices,
            deviceUID: crownDeviceUID,
            destination: harnessName,
            listening: voice.isActive,
            preview: crownPreview
        )
    }

    private var crownPreview: String? {
        if !voice.preview.isEmpty { return voice.preview }
        if !voice.lastTranscript.isEmpty { return voice.lastTranscript }
        return nil
    }

    private var crownDevices: [CrownDevice]? {
        switch control {
        case .output:
            outputDevices.map { CrownDevice(id: $0.uid, name: $0.name, kind: $0.transport.title) }
        case .mic:
            inputDevices.map { CrownDevice(id: $0.uid, name: $0.name, kind: $0.transport.title) }
        default:
            nil
        }
    }

    private var crownDeviceUID: String? {
        switch control {
        case .output: outputUID.isEmpty ? nil : outputUID
        case .mic: inputUID.isEmpty ? nil : inputUID
        default: nil
        }
    }

    func openMusicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
            NSWorkspace.shared.open(url)
        }
    }

    func openBluetoothSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.settings.Bluetooth")
            || openSettingsPane("x-apple.systempreferences:com.apple.Bluetooth")
    }

    func openSoundSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.Sound-Settings.extension")
            || openSettingsPane("x-apple.systempreferences:com.apple.preference.sound")
    }

    @discardableResult
    private func openSettingsPane(_ spec: String) -> Bool {
        guard let url = URL(string: spec) else { return false }
        return NSWorkspace.shared.open(url)
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
            previousOutput = outputDevices.first(where: { $0.uid == outputUID }) ?? outputs.current
        }
    }

    private func swapOutput() {
        outputSweep = nil
        let roster = outputDevices.isEmpty ? outputRoster() : outputDevices
        let current = roster.first(where: { $0.uid == outputUID }) ?? outputs.current
        if let previousOutput, previousOutput.uid != current?.uid,
           roster.contains(where: { $0.uid == previousOutput.uid }) {
            let dest = previousOutput
            self.previousOutput = current
            selectOutput(dest, commit: true)
            message = outputName
            return
        }
        rememberOutput()
        cycleSpeaker(1)
        message = outputName
    }

    private var meterTask: Task<Void, Never>?

    /// The meters loop, which re-reads the hardware so the room stays true
    /// when something outside Knurl changes it.
    ///
    /// The rate is the point. 280 ms is right while a person is watching a
    /// dial move; it is wasteful when the only reason the loop is alive is a
    /// connected iPhone crown, which was making a parked Mac poll CoreAudio
    /// three times a second forever. Changes Knurl makes are pushed to the
    /// phone by `broadcast()` as they happen — this loop only exists to catch
    /// changes made somewhere else.
    private func startMeters() {
        DisplayBrightness.watch()
        meterTask?.cancel()
        meterTask = Task { @MainActor in
            while !Task.isCancelled {
                let watching = isPresented || HubWindow.shared.isVisible || notchStage.isOpen
                guard watching || CrownServer.shared.clientCount > 0 else { break }
                refreshMeters()
                try? await Task.sleep(for: .milliseconds(watching ? 280 : 1000))
            }
        }
    }

    private func stopMeters() {
        meterTask?.cancel()
        meterTask = nil
        DisplayBrightness.unwatch()
    }

    /// Writes only when the value actually differs.
    ///
    /// `@Observable` invalidates on *assignment*, not on change. The meters
    /// loop runs three and a half times a second while the Hub is open and
    /// re-assigned every one of these — including two device arrays rebuilt
    /// from CoreAudio each pass, which are never equal by identity. So every
    /// view reading any of them was torn down and rebuilt continuously while
    /// the Hub was simply sitting there: five crowns, their blurred blooms
    /// and their gradient arcs, several times a second, to display numbers
    /// that had not moved. Comparing first turns that into a redraw when
    /// something actually happened.
    private func set<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<DialState, Value>,
        _ next: Value
    ) {
        if self[keyPath: keyPath] != next {
            self[keyPath: keyPath] = next
        }
    }

    private func refreshMeters() {
        set(\.volumePercent, DialMath.percent(Double(volume.level)))
        set(\.isMuted, volume.isMuted)
        if let live = DisplayBrightness.read() {
            DisplayBrightness.estimate = live
            set(\.brightnessPercent, DialMath.percent(live))
        }
        if outputRosterFrozen {
            pullMusicAirPlay(force: true)
            if let pod = musicAirPlay.first(where: {
                $0.selected && $0.kind != .computer && $0.uid == outputUID
            }) {
                set(\.outputName, pod.name)
                set(\.outputKind, pod.kind.title)
                set(\.outputUID, pod.uid)
                if !airPlayConnecting {
                    thawOutputRoster()
                }
            } else if !airPlayConnecting,
                      let started = outputFrozenAt,
                      Date().timeIntervalSince(started) > 2 {
                thawOutputRoster()
                if let pod = musicAirPlay.first(where: { $0.selected && $0.kind != .computer }) {
                    set(\.outputName, pod.name)
                    set(\.outputKind, pod.kind.title)
                    set(\.outputUID, pod.uid)
                } else {
                    set(\.outputName, outputs.current?.name ?? "No output")
                    set(\.outputKind, outputs.current?.transport.title ?? "Output")
                    set(\.outputUID, outputs.current?.uid ?? "")
                }
            }
        } else {
            pullMusicAirPlay()
            if let pod = musicAirPlay.first(where: { $0.selected && $0.kind != .computer }) {
                set(\.outputName, pod.name)
                set(\.outputKind, pod.kind.title)
                set(\.outputUID, pod.uid)
            } else {
                set(\.outputName, outputs.current?.name ?? "No output")
                set(\.outputKind, outputs.current?.transport.title ?? "Output")
                set(\.outputUID, outputs.current?.uid ?? "")
            }
        }
        adoptOutputDevices(outputRoster())
        rememberAirPlay(outputs.current)
        if let pod = musicAirPlay.first(where: { $0.selected && $0.kind != .computer }) {
            rememberAirPlay(pod.asAudioDevice)
        }
        set(\.inputName, inputs.current?.name ?? mic.deviceName)
        set(\.inputUID, inputs.current?.uid ?? "")
        set(\.inputDevices, inputs.devices())
        if mic.hasScalar {
            set(\.micPercent, DialMath.percent(Double(mic.level)))
        }
        set(\.isMicMuted, mic.isMuted)
        music.refresh()
        if music.hasTrack {
            desk.noteMusic(music.title)
        }
        lastDetent = TickSound.detent(from: progress)
        syncAngle()
        rememberCurrentVolume()
        StatusBar.shared.refresh(self)
        publishCrownIfNeeded()
    }

    private func publishCrownIfNeeded() {
        let hello = crownHello()
        // The playhead is deliberately not in this signature. The phone
        // interpolates it from the last hello exactly as the Mac does, so
        // including it meant a fresh payload — and a fresh cover key lookup —
        // three times a second for the whole length of a track, purely to
        // move a needle the phone could already predict. Real changes push
        // instantly; drift is corrected on a slow heartbeat instead.
        let signature = "\(hello.mode)|\(hello.readout)|\(hello.muted ?? false)|\(hello.playing ?? false)|\(hello.title ?? "")|\(hello.shuffle ?? false)|\(hello.repeat ?? "")|\(hello.deviceUID ?? "")|\(hello.destination ?? "")|\(hello.listening ?? false)|\(hello.preview ?? "")"
        let heartbeatDue = Date().timeIntervalSince(lastCrownPush) > 2
        guard signature != lastCrownSignature || heartbeatDue else { return }
        lastCrownSignature = signature
        lastCrownPush = Date()
        CrownServer.shared.broadcast()
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

    private func outputRoster() -> [AudioDevice] {
        pullMusicAirPlay()
        let pods = musicAirPlay
            .filter { $0.kind != .computer }
            .map(\.asAudioDevice)
        return AudioOutputs.roster(outputs.devices() + pods, remembered: airPlayMemory.destinations)
    }

    /// Kicks the AirPlay roster read off the main thread and lets the answer
    /// land when it lands. It used to block here on an Apple Event; the roster
    /// is re-read every couple of seconds anyway, so a tick of latency costs
    /// nothing and a blocked main thread cost a visible stutter.
    private func pullMusicAirPlay(force: Bool = false) {
        if !force, Date().timeIntervalSince(lastAirPlayPull) < (music.attentive ? 2 : 5) { return }
        lastAirPlayPull = Date()
        guard airPlayPull == nil else { return }
        airPlayPull = Task { @MainActor [weak self] in
            let devices = await MusicApp.airPlayDevicesAsync()
            guard let self, !Task.isCancelled else { return }
            self.airPlayPull = nil
            self.musicAirPlay = devices
        }
    }

    private func rememberAirPlay(_ device: AudioDevice?) {
        guard let device else { return }
        guard device.transport == .airPlay || AudioOutputs.isAirPlayNamed(device.name) else { return }
        airPlayMemory.remember(uid: device.uid, name: device.name)
        Preferences.airPlayMemory = airPlayMemory
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
        if !outputRosterFrozen {
            outputName = outputs.current?.name ?? "No output"
            if isPresented, mode == .output {
                message = outputName
            }
        }
    }

    func moveHubPages(from source: IndexSet, to destination: Int) {
        hubOrder.move(fromOffsets: source, toOffset: destination)
    }

    func adoptHarness() {
        guard !voice.isActive else { return }
        rememberEditor()
    }

    /// Apps that can never be the Flow destination.
    ///
    /// Only Knurl itself, and the two places where "words land in Finder"
    /// would be nonsense. Everything else you are actually working in — your
    /// editor, your terminal, your browser — is a valid target, because the
    /// whole point of Flow is that it lands where you already are.
    private static let excludedHarnesses: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
    ]

    private func rememberEditor() {
        guard !voice.isActive else { return }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        guard let id = front.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        guard !Self.excludedHarnesses.contains(id) else { return }
        editor = front
        if let name = front.localizedName, !name.isEmpty {
            harnessName = name
            desk.noteHarness(name)
        }
    }

    private func restoreEditor() {
        editor?.activate()
    }

    private func syncAngle() {
        angle = DialMath.gaugeAngle(progress: progress)
    }

    private func adoptOutputDevices(_ next: [AudioDevice]) {
        guard outputRosterFrozen, !outputDevices.isEmpty else {
            set(\.outputDevices, next)
            return
        }
        let incoming = Dictionary(uniqueKeysWithValues: next.map { ($0.uid, $0) })
        set(\.outputDevices, outputDevices.map { incoming[$0.uid] ?? $0 })
    }
}
