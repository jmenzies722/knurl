import SwiftUI

struct MusicLibraryStrip: View {
    @Bindable var state: DialState
    var compact: Bool = false

    var body: some View {
        if state.music.sources.isEmpty {
            Text("Open Music to load genres and playlists.")
                .font(compact ? .system(size: 11) : .caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: compact ? 6 : 8) {
                    ForEach(state.music.sources) { source in
                        chip(source)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? 36 : 42)
        }
    }

    private func chip(_ source: MusicSource) -> some View {
        let selected = state.music.activeSourceID == source.id
            || (source.kind == .genre && source.title.caseInsensitiveCompare(state.music.genre) == .orderedSame)
        return Button {
            state.playSource(source.id)
        } label: {
            HStack(spacing: 5) {
                if !compact {
                    Image(systemName: source.kind == .genre ? "opticaldisc" : "music.note.list")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(source.title)
                    .font(compact ? .system(size: 11, weight: .medium) : .caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 7 : 8)
            .foregroundStyle(.primary.opacity(0.92))
            .glassEffect(
                selected
                    ? .regular.tint(HubTint.face(.media, progress: 0.6, muted: false).opacity(0.42)).interactive()
                    : .regular.interactive(),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("\(source.title), \(source.kind == .genre ? "genre" : "playlist")")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
