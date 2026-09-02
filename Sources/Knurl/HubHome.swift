import KnurlCore
import SwiftUI

struct HubHome: View {
    @Bindable var state: DialState
    @Namespace private var room
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HubPageScroll {
            atmosphere
            roomBoard
            DeskCrownBank(state: state, hero: state.control, compact: true)
            feel
        }
        .animation(motion, value: state.volumePercent)
        .animation(motion, value: state.brightnessPercent)
        .animation(motion, value: state.outputUID)
        .animation(motion, value: state.control)
        .animation(motion, value: state.desk.timer.running)
        .animation(motion, value: state.desk.timer.readout)
        .animation(motion, value: state.music.title)
        .animation(motion, value: state.voice.isListening)
        .animation(motion, value: state.tickSound)
        .animation(motion, value: state.hapticOn)
    }

    private var motion: Animation? {
        HubMotion.spring(reduceMotion: reduceMotion, allowed: state.desk.allowsDecorativeMotion)
    }

    private var atmosphere: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HubHallHeader(title: time(timeline.date), whisper: whisper) {
                HStack(spacing: 8) {
                    HubGlassButton(
                        title: state.desk.timer.running ? state.desk.timer.readout : "Hour",
                        symbol: "timer",
                        selected: state.desk.timer.running
                    ) {
                        state.hubPage = .tools
                    }
                    HubGlassButton(
                        title: "Flow",
                        symbol: state.voice.isListening ? "waveform" : "mic.fill",
                        selected: state.voice.isListening
                    ) {
                        state.hubPage = .flow
                    }
                }
            }
        }
    }

    private var roomBoard: some View {
        HubSection(title: "Room") {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(DialMode.allCases) { mode in
                        HubLiveTile(
                            title: mode.title,
                            value: tileValue(mode),
                            symbol: tileSymbol(mode),
                            tint: tileTint(mode),
                            selected: state.control == mode
                        ) {
                            if state.control == mode {
                                state.confirmDial()
                            } else {
                                state.selectControl(mode)
                            }
                        }
                        .glassEffectID(mode.rawValue, in: room)
                        .modifier(HubSelectedGlass(active: state.control == mode, id: "room-tile", namespace: room))
                    }
                }
            }
        }
    }

    private var feel: some View {
        HubSection(title: "Feel") {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(TickSound.allCases) { sound in
                        HubGlassButton(
                            title: sound.title,
                            selected: state.tickSound == sound
                        ) {
                            state.setSound(sound)
                        }
                    }
                    HubGlassButton(
                        title: "Haptic",
                        symbol: state.hapticOn ? "hand.tap.fill" : "hand.tap",
                        selected: state.hapticOn
                    ) {
                        state.setHaptic(!state.hapticOn)
                    }
                }
            }
        }
    }

    private var whisper: String {
        if state.desk.timer.running {
            return "Hour · \(state.desk.timer.readout)"
        }
        if state.voice.isListening {
            return "Flow → \(state.harnessName)"
        }
        if state.music.hasTrack {
            return state.music.title
        }
        return "\(state.control.title) · enjoy the Mac."
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func tileValue(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "Muted" : "\(state.volumePercent)"
        case .brightness: "\(state.brightnessPercent)"
        case .mic: state.isMicMuted ? "Muted" : "\(state.micPercent)"
        case .output: shortName(state.outputName)
        case .media: state.music.hasTrack ? shortName(state.music.title) : "—"
        }
    }

    private func tileSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "speaker.slash.fill" : mode.symbol
        case .mic: state.isMicMuted ? "mic.slash.fill" : mode.symbol
        case .media: state.music.isPlaying ? "pause.fill" : mode.symbol
        case .output:
            state.outputDevices.first { $0.uid == state.outputUID }?.transport.symbol
                ?? mode.symbol
        case .brightness:
            mode.symbol
        }
    }

    private func tileTint(_ mode: DialMode) -> Color {
        let progress: Double = switch mode {
        case .volume: state.volumeProgress
        case .brightness: Double(state.brightnessPercent) / 100
        case .mic: Double(state.micPercent) / 100
        case .output: state.outputProgress
        case .media: state.music.displayedPlayhead()
        }
        return HubTint.face(
            mode,
            progress: progress,
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted)
        )
    }

    private func shortName(_ name: String) -> String {
        name.count > 12 ? String(name.prefix(11)) + "…" : name
    }
}

struct HubPageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .backgroundExtensionEffect()
    }
}
