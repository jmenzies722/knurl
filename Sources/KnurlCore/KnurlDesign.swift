import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Palette
//
// One adaptive palette for the whole desk. Every colour is built once from a
// dynamic NSColor so a card, a chip and the dial all shift together when the
// Mac flips appearance — no `@Environment(\.colorScheme)` plumbed through
// forty views, and no light-mode surface that reads as a bug.

public enum KnurlPalette {
    // Light is the hero now. The first pass was a near-black control room,
    // which looked striking in isolation and wrong next to every other app on
    // the Mac — a window is not a HUD. These track Apple's own system greys so
    // the Hub sits in a stack of Tahoe windows without shouting.

    /// The field the Hub sits on.
    public static let void = dynamic(dark: hex(0x18181B), light: hex(0xF2F2F7))
    /// The stage behind the content column.
    public static let stage = dynamic(dark: hex(0x161619), light: hex(0xF7F7FA))
    /// A card resting on the stage.
    public static let card = dynamic(dark: hex(0x24242A), light: hex(0xFFFFFF))
    /// A card that is lifted — hovered, selected, live.
    public static let raised = dynamic(dark: hex(0x303037), light: hex(0xFFFFFF))
    /// A well the eye reads as cut into the surface.
    public static let sunken = dynamic(dark: hex(0x141417), light: hex(0xEDEDF2))
    /// The fill under a chip or an unselected button. Distinct from `raised`
    /// because in light mode a raised card is white, and a white chip on a
    /// white card is a chip you cannot see.
    public static let control = dynamic(dark: hex(0x35353B), light: hex(0xEFEFF4))
    /// The dial's unfilled ring and the disc under its readout.
    public static let dialTrack = dynamicAlpha(dark: (0xFFFFFF, 0.16), light: (0x1D1D1F, 0.10))
    public static let dialWell = dynamicAlpha(dark: (0xFFFFFF, 0.04), light: (0x1D1D1F, 0.03))

    public static let hairline = dynamicAlpha(dark: (0xFFFFFF, 0.10), light: (0x1D1D1F, 0.10))
    public static let hairlineStrong = dynamicAlpha(dark: (0xFFFFFF, 0.22), light: (0x1D1D1F, 0.18))
    /// The specular line along the top edge of a raised surface.
    public static let sheen = dynamicAlpha(dark: (0xFFFFFF, 0.16), light: (0xFFFFFF, 1.0))

    // Apple's text greys. #1D1D1F is the one Apple uses for body copy; the
    // secondary and tertiary steps are close to `secondaryLabelColor`.
    public static let ink = dynamicAlpha(dark: (0xFFFFFF, 0.96), light: (0x1D1D1F, 1.0))
    public static let inkSoft = dynamicAlpha(dark: (0xFFFFFF, 0.66), light: (0x1D1D1F, 0.62))
    public static let inkFaint = dynamicAlpha(dark: (0xFFFFFF, 0.42), light: (0x1D1D1F, 0.42))

    // The machined dial, in two metals. A control that is meant to read as
    // hardware cannot be a flat fill: these are the two ends of the gradient
    // across its face, plus the colour its idle ticks are cut in.
    public static let metalHigh = dynamic(dark: hex(0x44444B), light: hex(0xFDFDFF))
    public static let metalLow = dynamic(dark: hex(0x1B1B20), light: hex(0xDCDCE4))
    public static let metalEdge = dynamicAlpha(dark: (0xFFFFFF, 0.16), light: (0x1D1D1F, 0.12))
    public static let metalTick = dynamicAlpha(dark: (0xFFFFFF, 0.30), light: (0x1D1D1F, 0.28))
    public static let metalInk = dynamicAlpha(dark: (0xFFFFFF, 0.96), light: (0x1D1D1F, 0.94))

    // Signal colours, matched to Apple's system palette so a green here reads
    // as the same green the rest of the Mac uses for "running".
    public static let live = dynamic(dark: hex(0x30D158), light: hex(0x28A745))
    public static let warn = dynamic(dark: hex(0xFF9F0A), light: hex(0xF08C00))
    public static let alert = dynamic(dark: hex(0xFF453A), light: hex(0xE5322A))
    public static let calm = dynamic(dark: hex(0x0A84FF), light: hex(0x0071E3))

#if canImport(AppKit)
    public static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDarkDesk ? dark : light })
    }

    private static func dynamicAlpha(
        dark: (UInt32, Double),
        light: (UInt32, Double)
    ) -> Color {
        dynamic(
            dark: hex(dark.0).withAlphaComponent(dark.1),
            light: hex(light.0).withAlphaComponent(light.1)
        )
    }
#else
    public static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func dynamicAlpha(
        dark: (UInt32, Double),
        light: (UInt32, Double)
    ) -> Color {
        dynamic(
            dark: hex(dark.0).withAlphaComponent(dark.1),
            light: hex(light.0).withAlphaComponent(light.1)
        )
    }
#endif
}

#if canImport(AppKit)
extension NSAppearance {
    public var isDarkDesk: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
#endif

// MARK: - Metrics

public enum KnurlSpace {
    public static let hair: CGFloat = 2
    public static let tight: CGFloat = 6
    public static let snug: CGFloat = 10
    public static let step: CGFloat = 14
    public static let room: CGFloat = 20
    public static let hall: CGFloat = 34
    public static let stage: CGFloat = 40
}

public enum KnurlRadius {
    public static let chip: CGFloat = 11
    public static let card: CGFloat = 18
    public static let panel: CGFloat = 24
    public static let stage: CGFloat = 30
}

public enum KnurlMotion {
    /// The default. Apple's own UI settles in roughly a quarter of a second;
    /// anything slower reads as the app thinking rather than responding.
    public static let settle = Animation.spring(duration: 0.26, bounce: 0.12)
    /// For things that should feel like they carry mass — the dial, the hero.
    public static let heavy = Animation.spring(duration: 0.34, bounce: 0.16)
    /// For chips and hovers, where any lag at all reads as lag.
    public static let snap = Animation.spring(duration: 0.15, bounce: 0.04)

    public static func allowed(_ lively: Bool, _ animation: Animation) -> Animation? {
        lively ? animation : nil
    }
}

/// One place that decides whether this view is allowed to move. Battery power
/// and Reduce Motion both mean "no", and both must be checked at the same
/// point or half the Hub keeps breathing while the other half freezes.
public struct KnurlLiveliness {
    public var lively: Bool

    public init(reduceMotion: Bool, powerAllows: Bool) {
        lively = !reduceMotion && powerAllows
    }

    public func motion(_ animation: Animation = KnurlMotion.settle) -> Animation? {
        lively ? animation : nil
    }
}

// MARK: - Atmosphere
//
// The animated field behind every Hub page. It is a mesh gradient whose
// control points drift on a slow sine, tinted by whichever face the dial is
// on — so switching from Volume to Media visibly warms the whole room rather
// than swapping one chip's colour. Frozen flat when motion is not allowed.

public struct KnurlAtmosphere: View {
    public var tint: Color
    public var energy: Double
    public var lively: Bool

    // The field is decoration. When Knurl is not the active app nobody is
    // looking at it, so it freezes rather than burning a core behind another
    // window — this alone took the idle Hub from ~8% CPU to under 1%.
    @Environment(\.knurlOnScreen) private var onScreen
#if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    private var animating: Bool { lively && onScreen && activeState != .inactive }
#else
    // iOS has no equivalent of an inactive window: a backgrounded app is not
    // drawing at all, so "is anybody looking" is already answered.
    private var animating: Bool { lively && onScreen }
#endif


    public init(tint: Color, energy: Double, lively: Bool) {
        self.tint = tint
        self.energy = energy
        self.lively = lively
    }

    public var body: some View {
        ZStack {
            KnurlPalette.void
            // The control points drift through a full cycle in about forty
            // seconds. Eight frames a second is already three hundred frames
            // per cycle — past that you are paying for motion nobody can
            // resolve, across the whole height of the rail.
            TimelineView(.animation(minimumInterval: 1.0 / 8, paused: !animating)) { timeline in
                let t = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
                mesh(t)
                    .opacity(0.72)
            }
            // A whisper of fall-off so a long page is not a flat sheet. The
            // first pass used a .plusDarker scrim at 28%, which sat over every
            // surface in the window and dragged the whole palette down.
            LinearGradient(
                colors: [.white.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
        .animation(lively ? .easeInOut(duration: 0.9) : nil, value: tint)
    }

    private func mesh(_ t: TimeInterval) -> some View {
        let drift = { (seed: Double, amount: Float) -> Float in
            Float(sin(t * 0.16 + seed) * Double(amount))
        }
        // Lighter and more pastel: the field tints the room, it does not
        // paint it. Anything stronger and the cards start to look stained.
        let lift = 0.12 + 0.20 * energy
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5 + drift(0.0, 0.06), 0), .init(1, 0),
                .init(0, 0.5 + drift(1.4, 0.07)),
                .init(0.5 + drift(2.1, 0.10), 0.5 + drift(3.3, 0.09)),
                .init(1, 0.5 + drift(4.0, 0.07)),
                .init(0, 1), .init(0.5 + drift(5.2, 0.06), 1), .init(1, 1),
            ],
            colors: [
                tint.opacity(lift * 0.55), tint.opacity(lift * 0.28), KnurlPalette.calm.opacity(lift * 0.30),
                tint.opacity(lift * 0.34), tint.opacity(lift * 0.85), tint.opacity(lift * 0.22),
                KnurlPalette.calm.opacity(lift * 0.22), tint.opacity(lift * 0.30), tint.opacity(lift * 0.48),
            ],
            smoothsColors: true
        )
    }
}

// MARK: - Surfaces

public enum KnurlLevel {
    case card
    case raised
    case sunken

    public var fill: Color {
        switch self {
        case .card: KnurlPalette.card
        case .raised: KnurlPalette.raised
        case .sunken: KnurlPalette.sunken
        }
    }

    public var shadow: (Color, CGFloat, CGFloat) {
        switch self {
        case .card: (.black.opacity(0.26), 18, 7)
        case .raised: (.black.opacity(0.38), 30, 13)
        case .sunken: (.clear, 0, 0)
        }
    }

    /// How much lighter the top of the surface is than the bottom. This is
    /// the whole difference between a panel and a rectangle: a real surface
    /// is lit from above, so it cannot be one flat value.
    public var lift: Double {
        switch self {
        case .card: 0.055
        case .raised: 0.085
        case .sunken: -0.03
        }
    }
}

/// The house card: a fill, a hairline that brightens toward the top-leading
/// corner as if lit from above, a specular top edge, and a drop shadow. Three
/// cheap layers, but they are what makes a rectangle read as a physical tile
/// instead of a coloured div.
public struct KnurlSurface: ViewModifier {
    public var level: KnurlLevel = .card
    public var radius: CGFloat = KnurlRadius.card
    public var tint: Color? = nil
    public var glow: Double = 0


    public init(
        level: KnurlLevel = .card,
        radius: CGFloat = KnurlRadius.card,
        tint: Color? = nil,
        glow: Double = 0
    ) {
        self.level = level
        self.radius = radius
        self.tint = tint
        self.glow = glow
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let shadow = level.shadow
        return content
            .background {
                ZStack {
                    shape.fill(level.fill)
                    // Top-lit, always. Flat fills are what made the Hub read
                    // as a diagram of an app rather than an app.
                    shape.fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(max(0, level.lift)),
                                .clear,
                                .black.opacity(max(0, -level.lift) + 0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    if let tint {
                        shape.fill(
                            LinearGradient(
                                colors: [tint.opacity(0.14), tint.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .shadow(color: shadow.0, radius: shadow.1, y: shadow.2)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            (tint ?? KnurlPalette.hairlineStrong).opacity(tint == nil ? 1 : 0.65),
                            KnurlPalette.hairline.opacity(0.4),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .overlay(alignment: .top) {
                // The specular edge. Inset so it never touches the corner
                // radius, where it would look like a rendering seam.
                Capsule()
                    .fill(KnurlPalette.sheen)
                    .frame(height: 1)
                    .padding(.horizontal, radius * 0.6)
                    .blendMode(.plusLighter)
                    .opacity(level == .sunken ? 0 : 1)
            }
            // `compositingGroup` costs an offscreen pass, so it is only paid
            // for when there is actually a glow that has to wrap the whole
            // composite. Unconditional, it made every card in the Hub an
            // extra render target.
            .modifier(KnurlGlow(tint: tint, glow: glow))
    }
}

private struct KnurlGlow: ViewModifier {
    public var tint: Color?
    public var glow: Double

    public func body(content: Content) -> some View {
        if glow > 0, let tint {
            content
                .compositingGroup()
                .shadow(color: tint.opacity(glow * 0.5), radius: 22 * glow)
        } else {
            content
        }
    }
}

extension View {
    public func knurlSurface(
        _ level: KnurlLevel = .card,
        radius: CGFloat = KnurlRadius.card,
        tint: Color? = nil,
        glow: Double = 0
    ) -> some View {
        modifier(KnurlSurface(level: level, radius: radius, tint: tint, glow: glow))
    }
}

// MARK: - Type

extension Font {
    /// The hero numeral: rounded, monospaced digits, so a readout that ticks
    /// from 9 to 10 does not shove the layout sideways.
    public static func knurlNumeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    public static var knurlEyebrow: Font { .system(size: 11, weight: .semibold) }
    public static var knurlLabel: Font { .system(size: 12, weight: .medium) }
    public static var knurlBody: Font { .system(size: 13, weight: .regular) }
    public static var knurlTitle: Font { .system(size: 17, weight: .semibold) }
    public static var knurlHall: Font { .system(size: 34, weight: .semibold, design: .rounded) }
}

// MARK: - Small parts

/// An all-caps tracked label. Used once per band so the eye can find the
/// seams of a long page without a horizontal rule every 40 points.
public struct KnurlEyebrow: View {
    public var text: String
    public var accessory: String? = nil
    public var tint: Color = KnurlPalette.inkFaint


    public init(text: String, accessory: String? = nil, tint: Color = KnurlPalette.inkFaint) {
        self.text = text
        self.accessory = accessory
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KnurlSpace.snug) {
            Text(text.uppercased())
                .font(.knurlEyebrow)
                .tracking(1.2)
                .foregroundStyle(tint)
            Rectangle()
                .fill(KnurlPalette.hairline)
                .frame(height: 1)
            if let accessory {
                Text(accessory)
                    .font(.knurlEyebrow.monospacedDigit())
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
        }
    }
}

/// A dot that pulses only while something is genuinely live. A static dot
/// means "present"; a pulsing dot means "running right now".
public struct KnurlPip: View {
    public var tint: Color
    public var live: Bool
    public var lively: Bool = true
    public var size: CGFloat = 7

    @Environment(\.knurlOnScreen) private var onScreen


    public init(tint: Color, live: Bool, lively: Bool = true, size: CGFloat = 7) {
        self.tint = tint
        self.live = live
        self.lively = lively
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !(live && lively && onScreen))) { timeline in
            let phase = live && lively && onScreen
                ? 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3.0)
                : 0
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .shadow(color: tint.opacity(0.5 + 0.5 * phase), radius: 3 + 4 * phase)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.5 * (1 - phase)), lineWidth: 1)
                        .scaleEffect(1 + 1.1 * phase)
                }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A horizontal level bar with a lit fill and a tick track behind it. This is
/// the flat cousin of the dial — same vocabulary, less room.
public struct KnurlMeter: View {
    public var progress: Double
    public var tint: Color
    public var height: CGFloat = 6
    public var showsTrack: Bool = true


    public init(progress: Double, tint: Color, height: CGFloat = 6, showsTrack: Bool = true) {
        self.progress = progress
        self.tint = tint
        self.height = height
        self.showsTrack = showsTrack
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if showsTrack {
                    Capsule().fill(KnurlPalette.sunken)
                    Capsule().strokeBorder(KnurlPalette.hairline, lineWidth: 0.8)
                }
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geometry.size.width * DialMath.clampVolume(progress)))
                    .shadow(color: tint.opacity(0.35), radius: 4)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A history strip. Takes newest-last samples in 0...1 and draws a filled
/// curve. Deliberately unlabelled — it is texture for a number, not a chart.
public struct KnurlSparkline: View {
    public var samples: [Double]
    public var tint: Color


    public init(samples: [Double], tint: Color) {
        self.samples = samples
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geometry in
            let points = pointList(in: geometry.size)
            ZStack {
                if points.count > 1 {
                    line(points)
                        .stroke(tint.opacity(0.95), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    fill(points, height: geometry.size.height)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.30), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func pointList(in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let step = size.width / CGFloat(samples.count - 1)
        return samples.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height * (1 - CGFloat(DialMath.clampVolume(value))) * 0.92 + size.height * 0.04
            )
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func fill(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = line(points)
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
        path.addLine(to: CGPoint(x: points[0].x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Dial skin
//
// The first pass made the dial out of machined aluminium: knurled teeth, an
// angular metal gradient, a dark well. It read as a photograph of hardware,
// and hardware is heavy — every edge was a hard line, and the whole control
// fought the soft surfaces around it.
//
// This is the opposite: one luminous ring on an open surface. No teeth, no
// bezel seam, no well. The colour does the work and the geometry gets out of
// the way, which is also what makes the value readable at a glance from
// across a desk.

public enum KnurlMetal: Sendable {
    /// Follows the Mac's appearance. The Hub and the phone use this.
    case adaptive
    /// Forced dark, for surfaces that float over your work — the HUD and the
    /// notch are dark no matter what the system appearance is.
    case graphite

    public var isDark: Bool { self == .graphite }

    /// The unfilled part of the ring. Soft and low-contrast: it is a guide,
    /// not a frame.
    /// Visible enough to read as a channel at any value. A dial sitting at 6%
    /// still has to look like a dial, and 10% white on near-black does not.
    public var track: Color {
        self == .graphite
            ? Color.white.opacity(0.16)
            : KnurlPalette.dialTrack
    }

    /// The disc the readout sits on. Almost nothing — just enough separation
    /// from the page for the numeral to sit on something.
    public var well: Color {
        self == .graphite
            ? Color.white.opacity(0.04)
            : KnurlPalette.dialWell
    }

    public var ink: Color { self == .graphite ? .white : KnurlPalette.ink }

    /// The scrub handle: a solid puck that reads as grabbable.
    public var handle: Color { self == .graphite ? .white : .white }

    public var handleEdge: Color {
        self == .graphite ? Color.black.opacity(0.25) : Color.black.opacity(0.10)
    }
}

// MARK: - On screen
//
// A hidden window still has a live SwiftUI hierarchy. Ordering a window out
// does not stop the `TimelineView`s inside it, so the Hub kept animating a
// playhead, a clock, five crowns and a mesh gradient while it was closed —
// invisible work, on a laptop, forever.
//
// This is the one signal that says "nobody can see this". It is set once at
// the root of each surface from that window's real visibility, and every view
// that owns a timeline reads it.

public struct KnurlOnScreenKey: EnvironmentKey {
    public static let defaultValue = true
}

public extension EnvironmentValues {
    var knurlOnScreen: Bool {
        get { self[KnurlOnScreenKey.self] }
        set { self[KnurlOnScreenKey.self] = newValue }
    }
}


// MARK: - Wide
//
// Set by the page frame from its real width. Pages read it to decide whether
// to stack or to sit side by side — a decision that belongs to the space
// available, not to a guess about the size of somebody's display.

public struct KnurlWideKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var knurlWide: Bool {
        get { self[KnurlWideKey.self] }
        set { self[KnurlWideKey.self] = newValue }
    }
}

// MARK: - Equaliser
//
// Two modes, and the difference matters.
//
// Given real levels it draws them: that is Flow, where the bars are the
// microphone and moving bars mean the mic is genuinely open. Given none it
// animates a phase-offset sine — which is decorative, and is exactly what
// Apple Music's own now-playing bars do, because no app can tap another app's
// audio without Screen Recording and Knurl will not ask for that. So it reads
// as "this is playing", never as "this is the waveform".
//
// Cheap on purpose: a handful of capsules, no blur, no offscreen pass, and
// paused the moment nothing is playing or nobody is looking.

public struct KnurlEqualizer: View {
    public var levels: [Float]?
    public var tint: Color
    public var bars: Int
    public var active: Bool
    public var lively: Bool
    public var height: CGFloat

    @Environment(\.knurlOnScreen) private var onScreen

    public init(
        levels: [Float]? = nil,
        tint: Color,
        bars: Int = 4,
        active: Bool,
        lively: Bool = true,
        height: CGFloat = 16
    ) {
        self.levels = levels
        self.tint = tint
        self.bars = bars
        self.active = active
        self.lively = lively
        self.height = height
    }

    private var animating: Bool { active && lively && onScreen }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { timeline in
            let t = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(alignment: .center, spacing: max(1.5, height * 0.13)) {
                ForEach(0 ..< bars, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: max(2, height * 0.17),
                            height: max(2, height * amplitude(index, t))
                        )
                }
            }
            .frame(height: height, alignment: .center)
            .opacity(active ? 1 : 0.35)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func amplitude(_ index: Int, _ t: TimeInterval) -> CGFloat {
        if let levels, !levels.isEmpty {
            // Newest samples last; spread them across the bars.
            let slice = levels.suffix(bars)
            let position = index % slice.count
            let value = slice[slice.index(slice.startIndex, offsetBy: position)]
            return CGFloat(min(1, max(0.12, value)))
        }
        guard animating else { return 0.22 }
        // Irrational-ish speeds so the bars never fall into lockstep, which is
        // the thing that makes a decorative equaliser look mechanical.
        let speed = 2.1 + Double(index) * 0.63
        let phase = Double(index) * 1.7
        return CGFloat(0.28 + 0.62 * abs(sin(t * speed + phase)))
    }
}

// MARK: - Notch tint
//
// What colour the notch lights up in. `automatic` keeps the behaviour the
// notch was built with — green while dictating, amber for the hour, the
// media hue while a track plays — because the colour is carrying meaning
// there. Pick a fixed one and it stops reporting and just looks how you want,
// which is a fair trade to want.

public enum NotchTint: String, CaseIterable, Sendable, Identifiable {
    case automatic
    case blue
    case teal
    case green
    case yellow
    case orange
    case pink
    case purple
    case graphite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .blue: "Blue"
        case .teal: "Teal"
        case .green: "Green"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .pink: "Pink"
        case .purple: "Purple"
        case .graphite: "Graphite"
        }
    }

    /// Nil means "follow whatever is happening".
    public var color: Color? {
        switch self {
        case .automatic: nil
        case .blue: Color(red: 0.04, green: 0.52, blue: 1.00)
        case .teal: Color(red: 0.19, green: 0.78, blue: 0.82)
        case .green: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .yellow: Color(red: 1.00, green: 0.84, blue: 0.04)
        case .orange: Color(red: 1.00, green: 0.62, blue: 0.04)
        case .pink: Color(red: 1.00, green: 0.18, blue: 0.33)
        case .purple: Color(red: 0.75, green: 0.35, blue: 0.95)
        case .graphite: Color(white: 0.78)
        }
    }

    /// What to show in a swatch. Automatic has no single colour, so it gets
    /// the spectrum it actually chooses from.
    public var swatch: AnyShapeStyle {
        if let color {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(
            AngularGradient(
                colors: [
                    NotchTint.green.color!, NotchTint.teal.color!, NotchTint.blue.color!,
                    NotchTint.purple.color!, NotchTint.pink.color!, NotchTint.orange.color!,
                    NotchTint.green.color!,
                ],
                center: .center
            )
        )
    }
}
