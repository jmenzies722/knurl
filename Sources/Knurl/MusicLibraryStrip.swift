import KnurlCore
import SwiftUI

struct MusicLibraryStrip: View {
    @Bindable var state: DialState
    var compact: Bool = false

    var body: some View {
        if state.music.sources.isEmpty {
            Text("Open Music to load genres and playlists.")
                .font(compact ? .system(size: 11) : .knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
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
            // Without a soft edge the last chip looks cut off rather than
            // scrollable, which is what it actually is.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
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
            .padding(.horizontal, compact ? 11 : 13)
            .padding(.vertical, compact ? 7 : 8)
            .foregroundStyle(selected ? .white : KnurlPalette.inkSoft)
            .background {
                Capsule().fill(
                    selected ? DialSwatch.stable(.media) : KnurlPalette.control
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    selected ? DialSwatch.stable(.media) : KnurlPalette.hairline,
                    lineWidth: 1
                )
            }
            .shadow(color: selected ? DialSwatch.stable(.media).opacity(0.35) : .clear, radius: 9, y: 2)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("\(source.title), \(source.kind == .genre ? "genre" : "playlist")")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
