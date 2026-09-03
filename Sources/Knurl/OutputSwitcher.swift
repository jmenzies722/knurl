import KnurlCore
import SwiftUI

/// Destinations under the Output crown: one chip per speaker, AirPlay last.
/// Turn the crown to land on one; a tap picks the same destination.
struct OutputDestinationRail: View {
    @Bindable var state: DialState
    var compact: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 6 : 8) {
                ForEach(state.outputDevices, id: \.uid) { device in
                    chip(device)
                }
                moreAirPlay
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.16), value: state.outputUID)
    }

    private func chip(_ device: AudioDevice) -> some View {
        let selected = device.uid == state.outputUID
        let tint = HubTint.face(.output, progress: 0.55, muted: false)
        return HStack(spacing: compact ? 5 : 7) {
            Image(systemName: device.transport.symbol)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? tint : .secondary)
            Text(device.name)
                .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? KnurlPalette.ink : KnurlPalette.inkSoft)
        .padding(.horizontal, compact ? 11 : 13)
        .padding(.vertical, compact ? 7 : 9)
        .background {
            Capsule().fill(selected ? tint.opacity(0.9) : KnurlPalette.control)
        }
        .overlay {
            Capsule().strokeBorder(selected ? tint : KnurlPalette.hairline, lineWidth: 1)
        }
        .shadow(color: selected ? tint.opacity(0.35) : .clear, radius: 9, y: 2)
        .overlay(ImmediatePress { state.pickOutput(device) })
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(device.name)
    }

    private var moreAirPlay: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                Text("AirPlay")
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
            }
            .padding(.horizontal, compact ? 11 : 13)
            .padding(.vertical, compact ? 7 : 11)
            .foregroundStyle(KnurlPalette.inkSoft)
            .background { Capsule().fill(KnurlPalette.control) }
            .overlay { Capsule().strokeBorder(KnurlPalette.hairline, lineWidth: 1) }
            RoutePicker()
                .opacity(0.02)
        }
        .accessibilityLabel("More AirPlay speakers")
    }
}
