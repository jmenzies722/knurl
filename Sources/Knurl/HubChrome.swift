import KnurlCore
import SwiftUI

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

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
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
