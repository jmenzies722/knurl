import KnurlCore
import SwiftUI

// MARK: - System
//
// The room around the editor, one face at a time, plus the hardware truth
// underneath it. The face switcher is the same 1–5 the crown answers to, so
// this page and the physical dial never disagree about where you are.

struct HubSystem: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tools: DeskToolbox { state.desk.tools }

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    var body: some View {
        HubPageScroll {
            HubHallHeader(title: "System", whisper: "The room around \(state.harnessName).") {
                faceSwitcher
            }
            stage
            machine
            power
            snapshot
        }
        .animation(live.motion(KnurlMotion.heavy), value: state.control)
        .animation(live.motion(), value: state.desk.powerMode)
    }

    // MARK: Face switcher

    private var faceSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(Array(DialMode.allCases.enumerated()), id: \.element.id) { index, mode in
                let selected = state.control == mode
                let tint = faceTint(mode)
                HStack(spacing: 5) {
                    Image(systemName: tabSymbol(mode))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selected ? .white : tint)
                    if selected {
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(KnurlPalette.inkFaint)
                    }
                }
                .padding(.horizontal, selected ? 11 : 9)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(selected ? tint : KnurlPalette.control)
                }
                .overlay {
                    Capsule().strokeBorder(selected ? .clear : KnurlPalette.hairline, lineWidth: 1)
                }
                .shadow(color: selected ? tint.opacity(0.5) : .clear, radius: 10, y: 2)
                .overlay(
                    ImmediatePress {
                        if selected { state.confirmDial() } else { state.selectControl(mode) }
                    }
                )
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background { Capsule().fill(KnurlPalette.sunken) }
        .overlay { Capsule().strokeBorder(KnurlPalette.hairline, lineWidth: 1) }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        switch state.control {
        case .media:
            VStack(alignment: .leading, spacing: KnurlSpace.room) {
                DeskCrownBank(state: state, hero: .media)
                mediaDetail
            }
        case .mic:
            VStack(alignment: .leading, spacing: KnurlSpace.room) {
                DeskCrownBank(state: state, hero: .mic)
                HubSection(title: "Input", accessory: state.inputName) {
                    VStack(spacing: 2) {
                        ForEach(state.inputDevices) { device in
                            HubDeviceRow(
                                name: device.name,
                                detail: device.transport.title,
                                symbol: device.transport.symbol,
                                selected: device.uid == state.inputUID
                            ) {
                                state.selectInput(device)
                            }
                        }
                    }
                }
            }
        case .output:
            VStack(alignment: .leading, spacing: KnurlSpace.room) {
                DeskCrownBank(state: state, hero: .output)
                HubSection(title: "Speakers", accessory: state.outputKind) {
                    VStack(spacing: 2) {
                        ForEach(state.outputDevices) { device in
                            HubDeviceRow(
                                name: device.name,
                                detail: device.transport.title,
                                symbol: device.transport.symbol,
                                selected: device.uid == state.outputUID
                            ) {
                                state.pickOutput(device)
                            }
                        }
                    }
                    if let memory = state.outputMemoryLine {
                        Text(memory)
                            .font(.knurlEyebrow.weight(.regular))
                            .foregroundStyle(KnurlPalette.inkFaint)
                    }
                }
            }
        default:
            DeskCrownBank(state: state, hero: state.control)
        }
    }

    private var mediaDetail: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            HubSection(title: "Track") {
                VStack(spacing: 0) {
                    HubFact(label: "Title", value: state.music.cardTitle)
                    if !state.music.artist.isEmpty {
                        HubFact(label: "Artist", value: state.music.artist)
                    }
                    if !state.music.album.isEmpty {
                        HubFact(label: "Album", value: state.music.album)
                    }
                    if !state.music.genre.isEmpty {
                        HubFact(label: "Genre", value: state.music.genre)
                    }
                }
            }
            HubSection(title: "Library") {
                MusicLibraryStrip(state: state)
            }
        }
    }

    // MARK: Machine
    //
    // Per-core load is the one number a developer actually reads differently
    // from a general user: one pinned core is a runaway thread, all cores hot
    // is a build. A single averaged percentage cannot tell those apart.

    private var machine: some View {
        HubSection(title: "This Mac") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                HubVitalsRow(state: state, showsNetwork: true)
                HubCoreStrip(state: state)
            }
        }
    }

    // MARK: Power

    private var power: some View {
        HubSection(title: "Power", accessory: state.desk.powerMode.title) {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                HStack(alignment: .center, spacing: KnurlSpace.room) {
                    Text(state.desk.power.snapshot.percentLabel)
                        .font(.knurlNumeral(44))
                        .foregroundStyle(KnurlPalette.ink)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.desk.power.snapshot.chargeLabel)
                            .font(.knurlBody)
                            .foregroundStyle(KnurlPalette.ink)
                        HStack(spacing: 5) {
                            KnurlPip(
                                tint: state.desk.power.snapshot.thermal.isException
                                    ? KnurlPalette.alert
                                    : KnurlPalette.live,
                                live: state.desk.power.snapshot.thermal.isException,
                                lively: live.lively,
                                size: 6
                            )
                            Text("Thermal \(state.desk.power.snapshot.thermal.title)")
                                .font(.knurlLabel)
                                .foregroundStyle(
                                    state.desk.power.snapshot.thermal.isException
                                        ? KnurlPalette.alert
                                        : KnurlPalette.inkSoft
                                )
                        }
                        if tools.awake {
                            Text("Knurl is holding this Mac awake · \(tools.awakeLabel)")
                                .font(.knurlEyebrow.weight(.regular))
                                .foregroundStyle(KnurlPalette.warn)
                        }
                    }
                    Spacer(minLength: 0)
                    KnurlMeter(
                        progress: Double(state.desk.power.snapshot.percent ?? 0) / 100,
                        tint: KnurlPalette.warn,
                        height: 8
                    )
                    .frame(width: 180)
                }

                HStack(spacing: KnurlSpace.tight) {
                    ForEach(PowerMode.allCases) { mode in
                        HubGlassButton(
                            title: mode.title,
                            tint: KnurlPalette.warn,
                            selected: state.desk.powerMode == mode
                        ) {
                            state.desk.powerMode = mode
                        }
                        .help(mode.summary)
                    }
                    Spacer(minLength: 0)
                    HubGlassButton(
                        title: tools.awake ? "Release awake" : "Keep awake",
                        symbol: tools.awake ? "eye.fill" : "eye",
                        tint: KnurlPalette.warn,
                        selected: tools.awake
                    ) {
                        tools.toggleAwake()
                    }
                }

                Text("Battery mode also parks the Hub's decorative motion — the room stops breathing so the Mac lasts longer.")
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
        }
    }

    // MARK: Snapshot

    private var snapshot: some View {
        HubSection(title: "Adaptive desk", accessory: "read only") {
            VStack(spacing: 0) {
                HubFact(label: "Workspace", value: state.desk.windows.lastPreset?.title ?? "Free")
                HubFact(label: "Output", value: state.outputName, secondary: state.outputKind)
                HubFact(label: "Volume", value: state.isMuted ? "Muted" : "\(state.volumePercent)%")
                HubFact(label: "Brightness", value: "\(state.brightnessPercent)%")
                HubFact(label: "Mic", value: state.inputName)
                HubFact(label: "Music", value: state.music.hasTrack ? state.music.title : "—")
                HubFact(label: "Power", value: state.desk.powerMode.title)
                HubFact(label: "Awake", value: tools.awake ? tools.awakeLabel : "System decides")
            }
            Text("This is the current snapshot, not a silent apply. Automatic restoration is opt-in and still off.")
                .font(.knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
        }
    }

    // MARK: Facts

    private func faceTint(_ mode: DialMode) -> Color {
        HubTint.face(
            mode,
            progress: state.controlProgress,
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted)
        )
    }

    private func tabSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .media: state.music.isPlaying ? "pause.fill" : "play.fill"
        case .output: "hifispeaker.fill"
        case .mic:
            if state.voice.isListening { "waveform" }
            else if state.isMicMuted { "mic.slash.fill" }
            else { "mic.fill" }
        }
    }
}

/// The per-core strip, isolated for the same reason as the vitals row.
struct HubCoreStrip: View {
    @Bindable var state: DialState

    var body: some View {
        let cores = state.desk.tools.vitals.cores
        if !cores.isEmpty {
            VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                KnurlEyebrow(text: "Cores", accessory: "\(cores.count)")
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(cores.enumerated()), id: \.offset) { _, load in
                        CoreBar(load: load)
                    }
                }
                .frame(height: 44)
                .padding(KnurlSpace.snug)
                .knurlSurface(.sunken, radius: KnurlRadius.chip)
            }
        }
    }
}

// MARK: - Core bar

struct CoreBar: View {
    var load: Double

    private var tint: Color {
        if load > 0.85 { return KnurlPalette.alert }
        if load > 0.55 { return KnurlPalette.warn }
        return KnurlPalette.live
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(2, geometry.size.height * DialMath.clampVolume(load)))
                    .shadow(color: tint.opacity(0.45), radius: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.linear(duration: 0.9), value: load)
        .accessibilityHidden(true)
    }
}
