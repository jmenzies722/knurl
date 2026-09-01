import KnurlCore
import SwiftUI

struct NotchView: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if state.isNotchExpanded {
                expanded(in: geometry.size)
            } else {
                housing(in: geometry.size)
            }
        }
        .animation(
            reduceMotion || !state.desk.allowsDecorativeMotion
                ? .easeOut(duration: 0.16)
                : .spring(duration: 0.42, bounce: 0.18),
            value: state.isNotchExpanded
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.2),
            value: whisper.line
        )
    }

    private var whisper: NotchWhisper {
        state.desk.whisper(
            listening: state.voice.isListening,
            destination: state.harnessName,
            musicTitle: state.music.hasTrack ? state.music.title : nil
        )
    }

    private func housing(in size: CGSize) -> some View {
        HStack(spacing: 8) {
            Image(systemName: housingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: state.voice.isListening && !reduceMotion)
            Text(whisper.line)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .overlay(ImmediatePress(action: { state.toggleNotch() }))
        .accessibilityLabel(whisper.line)
        .accessibilityAddTraits(.isButton)
    }

    private func expanded(in size: CGSize) -> some View {
        let housingHeight = max(28, size.height - NotchMath.shelfGap - NotchMath.shelfHeight)
        return VStack(spacing: NotchMath.shelfGap) {
            housing(in: CGSize(width: size.width, height: housingHeight))
            shelf
                .frame(height: NotchMath.shelfHeight)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var shelf: some View {
        HStack(spacing: 12) {
            if state.voice.isListening {
                FlowWaveform(
                    levels: state.voice.levels,
                    tint: .white,
                    bars: 12
                )
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(whisper.line)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !whisper.detail.isEmpty {
                        Text(whisper.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            if case .attention = whisper {
                Text("Hold")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .overlay(
                        ImmediateHold(
                            down: { state.beginTalk(presentHUD: false) },
                            up: { state.endTalk() }
                        )
                    )
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(ImmediatePress(action: { state.toggleNotch() }))
        .accessibilityLabel("\(whisper.line). \(whisper.detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var housingSymbol: String {
        if state.voice.isListening { return "waveform" }
        if !state.desk.attention.isEmpty { return "circle.fill" }
        if state.music.isPlaying { return "music.note" }
        return "dial.medium"
    }
}
