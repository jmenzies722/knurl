import KnurlCore
import SwiftUI

struct HubTools: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HubPageScroll {
            HubHallHeader(
                title: "Tools",
                whisper: state.desk.timer.running ? "Hour is on the notch." : "Turn the hour. Enjoy the Mac."
            ) {
                if state.desk.timer.running {
                    HubHallMetric(
                        value: state.desk.timer.readout,
                        lively: lively
                    )
                }
            }

            VStack(spacing: 22) {
                DeskCrown(
                    progress: state.desk.timer.crownProgress,
                    tint: .primary,
                    symbol: state.desk.timer.running ? "pause.fill" : "play.fill",
                    readout: state.desk.timer.readout,
                    caption: state.desk.timer.running ? "Hour" : "Set",
                    ticks: 10,
                    size: 236,
                    lively: lively,
                    onTurn: { state.setHourCrown($0) },
                    onConfirm: { state.toggleHour() }
                )
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    ForEach(DeskTimer.presets, id: \.seconds) { preset in
                        HubGlassButton(
                            title: preset.title,
                            selected: !state.desk.timer.running
                                && abs(state.desk.timer.duration - preset.seconds) < 1
                        ) {
                            state.setHourDuration(preset.seconds)
                        }
                    }
                    HubGlassButton(
                        title: state.desk.timer.running ? "Pause" : "Start",
                        symbol: state.desk.timer.running ? "pause.fill" : "play.fill",
                        selected: state.desk.timer.running
                    ) {
                        state.toggleHour()
                    }
                    if state.desk.timer.remaining != state.desk.timer.duration || state.desk.timer.running {
                        HubGlassButton(title: "Reset", symbol: "arrow.counterclockwise") {
                            state.resetHour()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HubDivider()

            HubSection(title: "The hour") {
                HStack(spacing: 10) {
                    HubToolCard(
                        title: "Start the hour",
                        detail: "Fifty minutes. Lights down. Notch keeps time.",
                        symbol: "hourglass"
                    ) {
                        state.startTheHour()
                    }
                    HubToolCard(
                        title: state.roomDimmed ? "Restore lights" : "Dim the room",
                        detail: state.roomDimmed
                            ? "Bring the display back."
                            : "Drop brightness. Remembers where you were.",
                        symbol: state.roomDimmed ? "sun.max.fill" : "moon.fill",
                        selected: state.roomDimmed
                    ) {
                        state.toggleRoomDim()
                    }
                }
            }

            HubDivider()

            HubSection(title: "The room") {
                HStack(spacing: 10) {
                    HubToolCard(
                        title: state.swapLabel,
                        detail: state.outputName,
                        symbol: "arrow.triangle.2.circlepath"
                    ) {
                        state.swapSpeaker()
                    }
                    HubToolCard(
                        title: state.voice.isListening ? "Release Flow" : "Hold Flow",
                        detail: "→ \(state.harnessName)",
                        symbol: state.voice.isListening ? "waveform" : "mic.fill",
                        selected: state.voice.isListening
                    ) {}
                    .overlay(
                        ImmediateHold(
                            down: { state.beginTalk(presentHUD: false) },
                            up: { state.endTalk() }
                        )
                    )
                }
            }
        }
        .animation(motion, value: state.desk.timer.running)
        .animation(motion, value: state.roomDimmed)
        .animation(motion, value: state.voice.isListening)
    }

    private var lively: Bool {
        !reduceMotion && state.desk.allowsDecorativeMotion
    }

    private var motion: Animation? {
        HubMotion.spring(reduceMotion: reduceMotion, allowed: state.desk.allowsDecorativeMotion)
    }
}

struct HubToolCard: View {
    var title: String
    var detail: String
    var symbol: String
    var selected: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .buttonStyle(.plain)
        // A card sits on the page, it does not float above it, so it gets a
        // surface rather than glass. PRODUCT.md: not on every card.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(hovering ? 0.9 : 0.5), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(title). \(detail)")
    }
}
