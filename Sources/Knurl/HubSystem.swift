import KnurlCore
import SwiftUI

struct HubSystem: View {
    @Bindable var state: DialState
    @Namespace private var faces
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HubPageScroll {
            HubHallHeader(title: "System", whisper: "The room around \(state.harnessName)") {
                faceSwitcher
            }
            stage
            HubDivider()
            power
            HubDivider()
            adaptive
        }
        .animation(HubMotion.lively(reduceMotion: reduceMotion, allowed: state.desk.allowsDecorativeMotion), value: state.control)
    }

    private var faceSwitcher: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(DialMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    let selected = state.control == mode
                    let tint = HubTint.face(
                        mode,
                        progress: state.controlProgress,
                        muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted)
                    )
                    HStack(spacing: 5) {
                        Image(systemName: tabSymbol(mode))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                        if selected {
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                        } else {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, selected ? 10 : 8)
                    .padding(.vertical, 7)
                    .glassEffect(
                        selected ? .regular.tint(tint.opacity(0.45)).interactive() : .regular.interactive(),
                        in: Capsule()
                    )
                    .glassEffectID(mode.rawValue, in: faces)
                    .modifier(SelectedFaceGlass(active: selected, namespace: faces))
                    .overlay(
                        ImmediatePress {
                            if selected { state.confirmDial() } else { state.selectControl(mode) }
                        }
                    )
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch state.control {
        case .media:
            VStack(alignment: .leading, spacing: 20) {
                mediaStage
                DeskCrownBank(state: state, hero: .volume)
            }
        case .mic:
            VStack(alignment: .leading, spacing: 18) {
                DeskCrownBank(state: state, hero: .mic)
                HubSection(title: "Input") {
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
        default:
            DeskCrownBank(state: state, hero: state.control)
        }
    }

    private var mediaStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.music.cardTitle)
                        .font(.title2.weight(.semibold))
                    if !state.music.artist.isEmpty {
                        Text(state.music.artist)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !state.music.album.isEmpty {
                HubFact(label: "Album", value: state.music.album)
            }
            if !state.music.genre.isEmpty {
                HubFact(label: "Genre", value: state.music.genre)
            }
            HubSection(title: "Library") {
                MusicLibraryStrip(state: state)
            }
            seek
            transport
        }
    }

    private var power: some View {
        HubSection(title: "Battery coding") {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(state.desk.power.snapshot.percentLabel)
                    .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.desk.power.snapshot.chargeLabel)
                    Text("Thermal \(state.desk.power.snapshot.thermal.title)")
                        .foregroundStyle(state.desk.power.snapshot.thermal.isException ? .orange : .secondary)
                    Text(state.desk.timer.running ? "Hour · \(state.desk.timer.readout)" : state.harnessName)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Spacer()
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(PowerMode.allCases) { mode in
                        HubGlassButton(
                            title: mode.title,
                            selected: state.desk.powerMode == mode
                        ) {
                            state.desk.powerMode = mode
                        }
                        .help(mode.summary)
                    }
                }
            }
        }
    }

    private var adaptive: some View {
        HubSection(title: "Adaptive desk") {
            HubFact(label: "Workspace", value: state.desk.windows.lastPreset?.title ?? "Free")
            HubFact(label: "Output", value: state.outputName)
            HubFact(label: "Volume", value: state.isMuted ? "Muted" : "\(state.volumePercent)%")
            HubFact(label: "Brightness", value: "\(state.brightnessPercent)%")
            HubFact(label: "Mic", value: state.inputName)
            HubFact(label: "Music", value: state.music.hasTrack ? state.music.title : "—")
            HubFact(label: "Power", value: state.desk.powerMode.title)
            Text("Automatic restoration is opt-in and off. This is the current snapshot, not a silent apply.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.16))
            if let cover = state.music.cover, state.music.hasTrack {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "dial.medium")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
    }

    private var seek: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            let progress = state.music.canSeek ? state.music.displayedPlayhead(at: timeline.date) : 0
            let elapsed = progress * state.music.duration
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { progress },
                        set: { state.music.seek(to: $0) }
                    ),
                    in: 0 ... 1
                )
                .disabled(!state.music.canSeek)
                HStack {
                    Text(state.music.canSeek ? DialMath.clock(elapsed) : "—")
                    Spacer()
                    Text(state.music.canSeek ? "−\(DialMath.clock(max(0, state.music.duration - elapsed)))" : "—")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var transport: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                hubButton("shuffle", selected: state.music.shuffleOn) { state.toggleShuffle() }
                hubButton("backward.fill") { state.skip(-1) }
                Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 52, height: 34)
                    .glassEffect(
                        .regular.tint(HubTint.face(.media, progress: 0.6, muted: false).opacity(0.55)).interactive(),
                        in: Capsule()
                    )
                    .overlay(ImmediatePress(action: { state.collapsedPlay() }))
                hubButton("forward.fill") { state.skip(1) }
                hubButton(state.music.repeatMode.symbol, selected: state.music.repeatMode != .off) {
                    state.cycleRepeat()
                }
            }
        }
    }

    private func hubButton(_ symbol: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .frame(width: 34, height: 34)
            .foregroundStyle(selected ? HubTint.face(.media, progress: 0.6, muted: false) : .primary.opacity(0.9))
            .glassEffect(
                selected
                    ? .regular.tint(HubTint.face(.media, progress: 0.6, muted: false).opacity(0.4)).interactive()
                    : .regular.interactive(),
                in: Capsule()
            )
            .overlay(ImmediatePress(action: action))
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

