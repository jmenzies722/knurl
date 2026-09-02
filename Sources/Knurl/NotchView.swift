import KnurlCore
import SwiftUI

struct NotchView: View {
    @Bindable var state: DialState
    @Namespace private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if state.isNotchExpanded {
                expanded(in: geometry.size)
            } else {
                housingChip(width: geometry.size.width, height: geometry.size.height)
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
        .animation(motion, value: state.voice.isActive)
        .animation(motion, value: state.voice.preview)
    }

    private var motion: Animation? {
        reduceMotion || !state.desk.allowsDecorativeMotion
            ? nil
            : .spring(duration: 0.36, bounce: 0.12)
    }

    private var whisper: NotchWhisper {
        state.desk.whisper(
            listening: state.voice.isActive,
            destination: state.harnessName,
            musicTitle: state.music.hasTrack ? state.music.title : nil
        )
    }

    private var shelfHeight: CGFloat {
        state.voice.isActive ? NotchMath.flowShelfHeight : NotchMath.shelfHeight
    }

    private func expanded(in size: CGSize) -> some View {
        let housed = NotchMath.housingInExpanded(housing: state.notchHousing, expanded: state.notchExpanded)
        let housingWidth = housed.width > 1 ? housed.width : min(232, size.width)
        let housingHeight = housed.height > 1
            ? housed.height
            : max(28, size.height - NotchMath.shelfGap - shelfHeight)
        let housingX = housed.width > 1 ? housed.minX : (size.width - housingWidth) / 2
        return ZStack(alignment: .topLeading) {
            housingChip(width: housingWidth, height: housingHeight)
                .frame(width: housingWidth, height: housingHeight)
                .offset(x: housingX, y: 0)
            shelf
                .frame(width: size.width, height: shelfHeight)
                .offset(x: 0, y: housingHeight + NotchMath.shelfGap)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func housingChip(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 7) {
            Image(systemName: housingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(
                    .variableColor.iterative,
                    isActive: state.voice.isActive && !reduceMotion
                )
            Text(whisper.line)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(width: width, height: height)
        .background(Color.black)
        .overlay(ImmediatePress(action: { state.toggleNotch() }))
        .accessibilityLabel(whisper.line)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var shelf: some View {
        if state.voice.isActive || state.voice.message != nil || !state.voice.lastTranscript.isEmpty {
            flowShelf
        } else {
            glanceShelf
        }
    }

    private var flowShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                FlowWaveform(
                    levels: state.voice.levels,
                    tint: .white,
                    bars: 14
                )
                Spacer(minLength: 8)
                flowCapsules
            }
            Text(flowLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("→ \(state.harnessName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("\(flowLine). \(state.harnessName)")
    }

    private var glanceShelf: some View {
        HStack(spacing: 12) {
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
            Spacer(minLength: 8)
            if case .timer = whisper {
                notchCapsule(state.desk.timer.running ? "Pause" : "Start") {
                    state.toggleHour()
                }
            }
            holdCapsule
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Color.clear
                .padding(.trailing, 120)
                .overlay(ImmediatePress(action: { state.toggleNotch() }))
        }
        .accessibilityLabel("\(whisper.line). \(whisper.detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var flowCapsules: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                holdCapsule
                    .glassEffectID("flow-hold", in: flow)
                if state.voice.isActive {
                    notchCapsule("Cancel") {
                        state.cancelTalk()
                    }
                    .glassEffectID("flow-cancel", in: flow)
                } else if !state.voice.lastTranscript.isEmpty {
                    notchCapsule("Resend") {
                        state.resendTalk()
                    }
                    .glassEffectID("flow-resend", in: flow)
                }
            }
        }
    }

    private var holdCapsule: some View {
        Text(state.voice.isActive ? "Release" : "Hold")
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
            .accessibilityLabel(state.voice.isActive ? "Release Flow" : "Hold Flow")
            .accessibilityAddTraits(.isButton)
    }

    private func notchCapsule(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
    }

    private var flowLine: String {
        if let message = state.voice.message, !message.isEmpty {
            return message
        }
        if !state.voice.preview.isEmpty {
            return state.voice.preview
        }
        if state.voice.isActive {
            return "Listening…"
        }
        if !state.voice.lastTranscript.isEmpty {
            return state.voice.lastTranscript
        }
        return "Hold to talk"
    }

    private var housingSymbol: String {
        if state.voice.isActive { return "waveform" }
        if state.desk.timer.running { return "timer" }
        if !state.desk.attention.isEmpty { return "circle.fill" }
        if state.music.isPlaying { return "music.note" }
        return "dial.medium"
    }
}
