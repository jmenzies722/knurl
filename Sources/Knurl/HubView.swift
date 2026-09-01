import KnurlCore
import SwiftUI

struct HubView: View {
    @Bindable var state: DialState

    var body: some View {
        VStack(spacing: 18) {
            faceTabs
            nowPlaying
            HStack(alignment: .top, spacing: 14) {
                stage
                talkBoard
                compactOutputs
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var faceTabs: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(DialMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    faceTab(mode, number: index + 1)
                }
            }
        }
    }

    private func faceTab(_ mode: DialMode, number: Int) -> some View {
        let selected = state.control == mode
        let tint = faceTint(mode)
        return HStack(spacing: 8) {
            Image(systemName: tabSymbol(mode))
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: selected)
                .foregroundStyle(tint)
            Text(mode.title)
                .font(.system(size: 14, weight: .semibold))
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .foregroundStyle(.primary.opacity(0.94))
        .glassEffect(
            selected
                ? .regular.tint(tint.opacity(0.48)).interactive()
                : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            ImmediatePress {
                if selected {
                    state.confirmDial()
                } else {
                    state.selectControl(mode)
                }
            }
        )
    }

    private var nowPlaying: some View {
        HStack(alignment: .center, spacing: 22) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                Text(state.music.cardTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                if !state.music.artist.isEmpty {
                    Text(state.music.artist)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !state.music.hasTrack {
                    Text(state.music.cardArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !state.music.album.isEmpty {
                        Text(state.music.album)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(0)
                    }
                    if !state.music.genre.isEmpty {
                        Text(state.music.genre)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                            .frame(minWidth: 96, maxWidth: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(
                                .regular.tint(faceTint(.media).opacity(0.35)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .help(state.music.genre)
                            .layoutPriority(1)
                    }
                }
                seek
                HStack(spacing: 8) {
                    hubButton("shuffle", selected: state.music.shuffleOn) {
                        state.toggleShuffle()
                    }
                    hubButton("backward.fill") { state.skip(-1) }
                    Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 78, height: 42)
                        .glassEffect(
                            .regular.tint(faceTint(.media).opacity(0.55)).interactive(),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(ImmediatePress(action: { state.collapsedPlay() }))
                    hubButton("forward.fill") { state.skip(1) }
                    hubButton(state.music.repeatMode.symbol, selected: state.music.repeatMode != .off) {
                        state.cycleRepeat()
                    }
                    Spacer(minLength: 8)
                    Text("Open Music")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .overlay(ImmediatePress(action: { state.revealMusic() }))
                }
                if !state.music.sources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(state.music.sources) { source in
                                let selected = state.music.activeSourceID == source.id
                                Text(source.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .glassEffect(
                                        selected
                                            ? .regular.tint(faceTint(.media).opacity(0.4))
                                            : .regular,
                                        in: Capsule()
                                    )
                                    .overlay(ImmediatePress(action: { state.playSource(source.id) }))
                            }
                        }
                    }
                    .frame(height: 40)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.22))
            if let cover = state.music.cover, state.music.hasTrack {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Image(systemName: "dial.medium")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 148, height: 148)
    }

    private var seek: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            let progress = state.music.canSeek
                ? state.music.displayedPlayhead(at: timeline.date)
                : 0
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

    @ViewBuilder
    private var stage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.control.title)
                .font(.headline)
            Text(stageCopy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            switch state.control {
            case .volume:
                stageGauge(
                    readout: state.isMuted ? "Muted" : "\(state.volumePercent)",
                    tint: faceTint(.volume),
                    value: Binding(
                        get: { state.volumeProgress },
                        set: { state.setRoomVolume($0) }
                    )
                )
            case .brightness:
                stageGauge(
                    readout: "\(state.brightnessPercent)",
                    tint: faceTint(.brightness),
                    value: Binding(
                        get: { Double(state.brightnessPercent) / 100 },
                        set: { state.setRoomBrightness($0) }
                    )
                )
            case .mic:
                stageGauge(
                    readout: state.isMicMuted ? "Muted" : "\(state.micPercent)",
                    tint: faceTint(.mic),
                    value: Binding(
                        get: { Double(state.micPercent) / 100 },
                        set: { state.setRoomMic($0) }
                    )
                )
            case .output:
                Text("Pick a Core Audio output. AirPlay is the Wi‑Fi path.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .media:
                mediaClock
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var mediaClock: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            let progress = state.music.canSeek
                ? state.music.displayedPlayhead(at: timeline.date)
                : 0
            let elapsed = progress * state.music.duration
            VStack(alignment: .leading, spacing: 4) {
                Text(state.music.canSeek ? DialMath.clock(elapsed) : "—")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(faceTint(.media))
                Text(state.music.canSeek ? "−\(DialMath.clock(max(0, state.music.duration - elapsed))) remaining" : "Nothing in Music yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var talkBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talk")
                .font(.headline)
            if state.voice.isListening || !state.voice.preview.isEmpty {
                Text(state.voice.preview.isEmpty ? "Listening…" : state.voice.preview)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
            } else {
                Text("Hold, speak, release. Words land in the last app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: state.voice.isListening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: state.voice.isListening)
                Text(state.voice.isListening ? "Release to paste" : "Hold to talk  ⌃⌥M")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassEffect(
                .regular.tint(faceTint(.mic).opacity(state.voice.isListening ? 0.5 : 0.18)).interactive(),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                ImmediateHold(
                    down: { state.beginTalk(presentHUD: false) },
                    up: { state.endTalk() }
                )
            )
            if let message = state.voice.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var compactOutputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Output")
                    .font(.headline)
                Spacer()
                RoutePicker()
                    .frame(width: 28, height: 28)
            }
            Text(state.outputName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text("AirPlay for HomePods and TVs")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.outputDevices) { device in
                        let selected = device.uid == state.outputUID
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(device.transport.title)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .glassEffect(
                            selected
                                ? .regular.tint(faceTint(.output).opacity(0.42))
                                : .regular,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(ImmediatePress(action: { state.selectOutput(device) }))
                    }
                }
            }
            .frame(height: 48)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var stageCopy: String {
        switch state.control {
        case .volume: state.isMuted ? "Click the tab to unmute." : state.outputName
        case .brightness: "This display"
        case .mic: state.voice.isListening ? "Listening" : state.inputName
        case .output: state.outputKind
        case .media: state.music.hasTrack ? state.music.line : "Music.app"
        }
    }

    private func stageGauge(readout: String, tint: Color, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(readout)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Slider(value: value, in: 0 ... 1)
        }
    }

    private func hubButton(_ symbol: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .frame(width: 42, height: 42)
            .foregroundStyle(selected ? faceTint(.media) : .primary.opacity(0.9))
            .glassEffect(
                selected
                    ? .regular.tint(faceTint(.media).opacity(0.4)).interactive()
                    : .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    private func faceTint(_ mode: DialMode) -> Color {
        let rgb = DialTint.rgb(
            progress: state.controlProgress,
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted),
            mode: mode
        )
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}
