import KnurlCore
import SwiftUI

struct NotchView: View {
    @Bindable var state: DialState

    var body: some View {
        Group {
            if state.isNotchExpanded {
                desk
            } else {
                chip
            }
        }
        .animation(.snappy(duration: 0.24), value: state.isNotchExpanded)
    }

    private var chip: some View {
        HStack(spacing: 10) {
            Image(systemName: "dial.medium")
                .font(.system(size: 12, weight: .semibold))
            Text(state.music.cardTitle)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(state.voice.isListening ? "Talk" : "Idle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state.voice.isListening ? .primary : .secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(state.control.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(ImmediatePress(action: { state.expandNotch() }))
    }

    private var desk: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "dial.medium")
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Knurl")
                        .font(.headline)
                    Text("Engineer desk  ·  notch, side dial, this view")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Esc")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(8)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .help("Collapse to notch")
                    .overlay(ImmediatePress(action: { state.collapseNotch() }))
            }
            .padding(.horizontal, 8)
            HubView(state: state)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
