import KnurlCore
import SwiftUI

// MARK: - Motion
//
// Kept as the app-wide entry point so the HUD, the notch and the Hub all ask
// the same question. The curves themselves now live in KnurlMotion.

enum HubMotion {
    static func spring(reduceMotion: Bool, allowed: Bool) -> Animation? {
        reduceMotion || !allowed ? nil : KnurlMotion.settle
    }

    static func lively(reduceMotion: Bool, allowed: Bool) -> Animation? {
        reduceMotion || !allowed ? nil : KnurlMotion.heavy
    }
}

// MARK: - Page frame

/// Every Hub page is the same column: a fixed-width reading measure, generous
/// gutters, and nothing painted behind it. The atmosphere belongs to the Hub
/// window, not to six separate pages that each have to remember to draw it.
struct HubPageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KnurlSpace.hall) {
                content()
            }
            .padding(.horizontal, gutter)
            .padding(.top, KnurlSpace.hall)
            .padding(.bottom, KnurlSpace.stage + KnurlSpace.room)
            .frame(maxWidth: measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        // Measure the scroll view, do not *wrap* it.
        //
        // The previous version put a GeometryReader around the ScrollView to
        // get the width. GeometryReader takes all the space offered and
        // reports its own size, so every page inside it lost the natural
        // height it would otherwise propose — which is why scrolling started
        // misbehaving. `onGeometryChange` reads the same number without
        // becoming the parent of the layout.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.knurlWide, width >= 1000)
    }

    /// Text past about 1,280 points is genuinely harder to read, so the
    /// measure stops there — but everything below that uses the room it has
    /// instead of stopping dead at 940 and leaving the stage empty.
    private var measure: CGFloat {
        width <= 0 ? 1080 : min(1280, max(600, width - 2 * gutter))
    }

    private var gutter: CGFloat {
        width >= 1400 ? KnurlSpace.stage + KnurlSpace.room : KnurlSpace.stage
    }
}

// MARK: - Hall header

/// The top of a page: an oversized rounded title, a whisper under it, and
/// whatever live control belongs up here. The title is deliberately the
/// largest thing on screen — a page you land on should say where you are
/// before you read anything else.
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
        HStack(alignment: .center, spacing: KnurlSpace.room) {
            VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                Text(title)
                    .font(.knurlHall)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [KnurlPalette.ink, KnurlPalette.ink.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                if let whisper, !whisper.isEmpty {
                    Text(whisper)
                        .font(.knurlBody)
                        .foregroundStyle(KnurlPalette.inkSoft)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: KnurlSpace.snug)
            accessory()
        }
        .padding(.bottom, KnurlSpace.tight)
    }
}

extension HubHallHeader where Accessory == EmptyView {
    init(title: String, whisper: String? = nil) {
        self.init(title: title, whisper: whisper) { EmptyView() }
    }
}

// MARK: - Bands

/// A titled band. The eyebrow rule replaces what used to be a heading plus a
/// divider, which was two elements doing one job.
struct HubSection<Content: View>: View {
    var title: String
    var accessory: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            KnurlEyebrow(text: title, accessory: accessory)
            content()
        }
    }
}

/// Retained because the HUD and older pages still call it. On a Hub page the
/// eyebrow rule already separates bands, so this is now nearly invisible.
struct HubDivider: View {
    var body: some View {
        Rectangle()
            .fill(KnurlPalette.hairline)
            .frame(height: 1)
            .padding(.vertical, KnurlSpace.tight)
    }
}

// MARK: - Rows and facts

struct HubFact: View {
    var label: String
    var value: String
    var secondary: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KnurlSpace.step) {
            Text(label)
                .font(.knurlLabel)
                .foregroundStyle(KnurlPalette.inkFaint)
                .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.knurlBody.weight(.medium))
                    .foregroundStyle(KnurlPalette.ink)
                if let secondary, !secondary.isEmpty {
                    Text(secondary)
                        .font(.knurlEyebrow)
                        .foregroundStyle(KnurlPalette.inkFaint)
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

struct HubEmpty: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.tight) {
            Text(title)
                .font(.knurlTitle)
                .foregroundStyle(KnurlPalette.inkSoft)
            Text(detail)
                .font(.knurlBody)
                .foregroundStyle(KnurlPalette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KnurlSpace.room)
        .knurlSurface(.sunken)
    }
}

/// A selectable hardware row. Still a real Button so it keeps focus, keyboard
/// activation and hover; the surface is what changed.
struct HubDeviceRow: View {
    var name: String
    var detail: String
    var symbol: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: KnurlSpace.snug) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? KnurlPalette.live : KnurlPalette.inkSoft)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.knurlBody.weight(selected ? .semibold : .regular))
                        .foregroundStyle(KnurlPalette.ink)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.knurlEyebrow)
                            .foregroundStyle(KnurlPalette.inkFaint)
                    }
                }
                Spacer(minLength: KnurlSpace.snug)
                if selected {
                    KnurlPip(tint: KnurlPalette.live, live: false)
                }
            }
            .padding(.horizontal, KnurlSpace.step)
            .padding(.vertical, KnurlSpace.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                    .fill(selected || hovering ? KnurlPalette.raised : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                    .strokeBorder(selected ? KnurlPalette.hairlineStrong : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(KnurlMotion.snap, value: hovering)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(name), \(detail)")
    }
}

// MARK: - Chips and buttons

/// The workhorse control. Glass, because chips float above the page — that is
/// the one place PRODUCT.md asks for it.
struct HubGlassButton: View {
    var title: String
    var symbol: String? = nil
    var tint: Color = KnurlPalette.ink
    var selected: Bool = false
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: KnurlSpace.tight) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .symbolEffect(.bounce, value: selected)
                    .symbolEffectsRemoved(reduceMotion)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(selected ? .white : KnurlPalette.ink)
        .padding(.horizontal, KnurlSpace.step)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(selected ? tint : KnurlPalette.control.opacity(hovering ? 1 : 0.8))
        }
        .overlay {
            Capsule().strokeBorder(
                selected ? tint.opacity(0.9) : KnurlPalette.hairline,
                lineWidth: 1
            )
        }
        .shadow(color: selected ? tint.opacity(0.45) : .clear, radius: 10, y: 2)
        .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
        .onHover { hovering = $0 }
        .animation(KnurlMotion.snap, value: hovering)
        .animation(KnurlMotion.snap, value: selected)
        .overlay(ImmediatePress(action: action))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
    }
}

// MARK: - Action card
//
// A tool you can press. Distinct from a face tile: a tile shows a value the
// dial can change, a card does one thing when you click it.

struct KnurlActionCard: View {
    var title: String
    var detail: String
    var symbol: String
    var tint: Color = KnurlPalette.calm
    var selected: Bool = false
    var badge: String? = nil
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.snug) {
            HStack(alignment: .top, spacing: KnurlSpace.snug) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? tint : KnurlPalette.inkSoft)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? tint.opacity(0.20) : KnurlPalette.sunken)
                    }
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.knurlEyebrow.monospacedDigit())
                        .foregroundStyle(selected ? tint : KnurlPalette.inkFaint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(selected ? tint.opacity(0.18) : KnurlPalette.sunken)
                        }
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                }
            }
            Spacer(minLength: KnurlSpace.tight)
            Text(title)
                .font(.knurlBody.weight(.semibold))
                .foregroundStyle(KnurlPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(detail)
                .font(.knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(KnurlSpace.step)
        .knurlSurface(
            selected || hovering ? .raised : .card,
            tint: selected ? tint : nil,
            glow: selected ? 0.4 : 0
        )
        .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(KnurlMotion.snap, value: hovering)
        .animation(KnurlMotion.settle, value: selected)
        .overlay(ImmediatePress(action: action))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(title). \(detail)")
    }
}

// MARK: - Stat
//
// A number with texture. The sparkline is not a chart — it is there so a
// glance can tell "68% and climbing" from "68% and settling", which the
// number alone cannot say.

struct KnurlStat: View {
    var label: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color
    var progress: Double
    var history: [Double] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.snug) {
            HStack(spacing: KnurlSpace.tight) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.knurlEyebrow)
                    .tracking(0.9)
                    .foregroundStyle(KnurlPalette.inkFaint)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.knurlNumeral(24))
                .foregroundStyle(KnurlPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(reduceMotion ? .opacity : .numericText())
            Text(detail)
                .font(.knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if history.count > 1 {
                KnurlSparkline(samples: history, tint: tint)
                    .frame(height: 26)
            } else {
                KnurlMeter(progress: progress, tint: tint, height: 5)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(KnurlSpace.step)
        .knurlSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), \(detail)")
    }
}

// MARK: - Tints

enum HubTint {
    static func face(_ mode: DialMode, progress: Double, muted: Bool) -> Color {
        let rgb = DialTint.rgb(progress: progress, muted: muted, mode: mode)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

// MARK: - Toolbar

struct HubToolbarMusic: View {
    @Bindable var state: DialState

    var body: some View {
        Button {
            state.revealMusic()
        } label: {
            HStack(spacing: KnurlSpace.tight) {
                if let cover = state.music.cover, state.music.hasTrack {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 17, height: 17)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: state.music.isPlaying ? "pause.fill" : "music.note")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(state.music.hasTrack ? state.music.title : "Music")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(KnurlPalette.ink)
            .padding(.horizontal, KnurlSpace.snug)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(state.music.hasTrack ? "Open Music, \(state.music.title)" : "Open Music")
    }
}


// MARK: - Vitals row
//
// Its own view on purpose. `DeskToolbox` republishes a sample every couple of
// seconds; whichever view body reads it is the view that gets invalidated. As
// a computed property on HubHome that meant re-rendering the crowns, the face
// tiles and every card on the page to move one sparkline by a pixel.

struct HubVitalsRow: View {
    @Bindable var state: DialState
    var showsNetwork: Bool = false

    private var tools: DeskToolbox { state.desk.tools }

    var body: some View {
        HStack(spacing: KnurlSpace.snug) {
            KnurlStat(
                label: "CPU",
                value: tools.vitals.cpuLabel,
                detail: "\(tools.vitals.cores.count) cores",
                symbol: "cpu",
                tint: KnurlPalette.calm,
                progress: tools.vitals.cpu,
                history: tools.cpuHistory
            )
            KnurlStat(
                label: "Memory",
                value: tools.vitals.memoryLabel,
                detail: tools.vitals.memoryDetail,
                symbol: "memorychip",
                tint: KnurlPalette.live,
                progress: tools.vitals.memoryProgress,
                history: tools.memoryHistory
            )
            if showsNetwork {
                KnurlStat(
                    label: "Network",
                    value: DeskFormat.rate(tools.vitals.networkIn),
                    detail: "up \(DeskFormat.rate(tools.vitals.networkOut))",
                    symbol: "network",
                    tint: KnurlPalette.warn,
                    progress: 0,
                    history: tools.networkHistory
                )
            } else {
                KnurlStat(
                    label: "Battery",
                    value: state.desk.power.snapshot.percentLabel,
                    detail: state.desk.power.snapshot.chargeLabel,
                    symbol: "battery.100",
                    tint: state.desk.power.snapshot.thermal.isException
                        ? KnurlPalette.alert
                        : KnurlPalette.warn,
                    progress: Double(state.desk.power.snapshot.percent ?? 0) / 100
                )
            }
            KnurlStat(
                label: "Disk",
                value: tools.vitals.diskLabel,
                detail: tools.vitals.diskDetail,
                symbol: "internaldrive",
                tint: KnurlPalette.inkSoft,
                progress: tools.vitals.diskProgress
            )
        }
    }
}
