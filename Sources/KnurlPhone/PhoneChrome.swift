import KnurlCore
import SwiftUI

// MARK: - Phone chrome
//
// The iPhone is not a companion app with its own look — it is the crown of
// the same desk, held in a hand. So it draws from the same `KnurlPalette`,
// the same spacing scale and the same surfaces as the Mac Hub, and only the
// things that genuinely differ on a phone are redefined here: touch targets,
// safe areas, and the fact that there is no pointer to hover with.

enum PhoneMotion {
    static func spring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : KnurlMotion.settle
    }

    static func heavy(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : KnurlMotion.heavy
    }
}

// MARK: - Header

struct PhoneHallHeader<Accessory: View>: View {
    var title: String
    var whisper: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: KnurlSpace.step) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(KnurlPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let whisper, !whisper.isEmpty {
                    Text(whisper)
                        .font(.system(size: 13))
                        .foregroundStyle(KnurlPalette.inkSoft)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: KnurlSpace.snug)
            accessory()
        }
    }
}

// MARK: - Bands

struct PhoneSection<Content: View>: View {
    var title: String
    var accessory: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.snug) {
            KnurlEyebrow(text: title, accessory: accessory)
            content()
        }
    }
}

struct PhoneFact: View {
    var label: String
    var value: String
    var secondary: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KnurlSpace.step) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KnurlPalette.inkFaint)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KnurlPalette.ink)
                if let secondary, !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 11))
                        .foregroundStyle(KnurlPalette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KnurlPalette.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows
//
// 48 points tall rather than the Mac's 32: this row is hit with a thumb, and
// a pointer-sized target is the single most common way a Mac design fails
// when it is carried across to a phone.

struct PhoneDeviceRow: View {
    var name: String
    var detail: String
    var symbol: String = "hifispeaker.fill"
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KnurlSpace.snug) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? KnurlPalette.live : KnurlPalette.inkSoft)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 15, weight: selected ? .semibold : .regular))
                        .foregroundStyle(KnurlPalette.ink)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(KnurlPalette.inkFaint)
                    }
                }
                Spacer(minLength: KnurlSpace.snug)
                if selected {
                    KnurlPip(tint: KnurlPalette.live, live: false, size: 7)
                }
            }
            .padding(.horizontal, KnurlSpace.step)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                    .fill(selected ? KnurlPalette.control : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                    .strokeBorder(selected ? KnurlPalette.hairlineStrong : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ImmediatePressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(name), \(detail)")
    }
}

// MARK: - Chips

struct PhoneChip: View {
    var title: String
    var symbol: String? = nil
    var tint: Color = KnurlPalette.ink
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KnurlSpace.tight) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : KnurlPalette.ink)
            .padding(.horizontal, KnurlSpace.step)
            .frame(height: 38)
            .background {
                Capsule().fill(selected ? tint : KnurlPalette.control)
            }
            .overlay {
                Capsule().strokeBorder(selected ? tint : KnurlPalette.hairline, lineWidth: 1)
            }
            .shadow(color: selected ? tint.opacity(0.45) : .clear, radius: 10, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(ImmediatePressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
    }
}

// MARK: - Tint

func phoneTint(mode: DialMode, progress: Double, muted: Bool) -> Color {
    let rgb = DialTint.rgb(progress: progress, muted: muted, mode: mode)
    return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
}
