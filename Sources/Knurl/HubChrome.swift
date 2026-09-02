import KnurlCore
import SwiftUI

enum HubMotion {
    static func spring(reduceMotion: Bool, allowed: Bool) -> Animation? {
        reduceMotion || !allowed ? nil : .spring(duration: 0.42, bounce: 0.12)
    }

    static func lively(reduceMotion: Bool, allowed: Bool) -> Animation? {
        reduceMotion || !allowed ? nil : .spring(duration: 0.48, bounce: 0.16)
    }
}

struct HubHallHeader<Accessory: View>: View {
    var title: String
    var whisper: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    init(title: String, whisper: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.whisper = whisper
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                if let whisper, !whisper.isEmpty {
                    Text(whisper)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

extension HubHallHeader where Accessory == EmptyView {
    init(title: String, whisper: String? = nil) {
        self.init(title: title, whisper: whisper) { EmptyView() }
    }
}

struct HubHallMetric: View {
    var value: String
    var lively: Bool

    var body: some View {
        Text(value)
            .font(.title.weight(.semibold).monospacedDigit())
            .contentTransition(lively ? .numericText() : .opacity)
    }
}

struct HubSelectedGlass: ViewModifier {
    var active: Bool
    var id: String
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if active {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

struct HubGlance: View {
    var title: String
    var value: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(14)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(ImmediatePress(action: action))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct HubLiveTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color
    var selected: Bool
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? tint : .secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(12)
        .glassEffect(
            selected
                ? .regular.tint(tint.opacity(0.32)).interactive()
                : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(ImmediatePress(action: action))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct HubToolbarMusic: View {
    @Bindable var state: DialState

    var body: some View {
        Button {
            state.revealMusic()
        } label: {
            HStack(spacing: 8) {
                if let cover = state.music.cover, state.music.hasTrack {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: state.music.isPlaying ? "pause.fill" : "music.note")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(state.music.hasTrack ? state.music.title : "Music")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(state.music.hasTrack ? "Open Music, \(state.music.title)" : "Open Music")
    }
}

struct HubDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.45))
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

struct HubSection<Content: View>: View {
    var title: String
    var accessory: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer(minLength: 8)
                if let accessory {
                    Text(accessory)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }
}

struct HubFact: View {
    var label: String
    var value: String
    var secondary: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.callout.weight(.medium))
                if let secondary, !secondary.isEmpty {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct HubEmpty: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct HubGlassButton: View {
    var title: String
    var symbol: String? = nil
    var tint: Color = .primary
    var selected: Bool = false
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .symbolEffect(.bounce, value: selected)
                    .symbolEffectsRemoved(reduceMotion)
            }
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(
            selected
                ? .regular.tint(tint.opacity(0.36)).interactive()
                : .regular.interactive(),
            in: Capsule()
        )
        .overlay(ImmediatePress(action: action))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
    }
}

enum HubTint {
    static func face(_ mode: DialMode, progress: Double, muted: Bool) -> Color {
        let rgb = DialTint.rgb(progress: progress, muted: muted, mode: mode)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

/// A selectable hardware row: real Button, so it gets focus, keyboard
/// activation and hover for free. The old version was a HubFact with an
/// ImmediatePress overlay, which looked like loose text and could not be
/// reached from the keyboard.
struct HubDeviceRow: View {
    var name: String
    var detail: String
    var symbol: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(name), \(detail)")
    }
}
