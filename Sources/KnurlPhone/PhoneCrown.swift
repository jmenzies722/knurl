import KnurlCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct PhoneCrown: View {
    @Bindable var session: PhoneSession
    var size: CGFloat = 248
    var metal: KnurlMetal = .adaptive

    @State private var lastAngle: Double?
    @State private var stepBank = 0.0
    @State private var localProgress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.knurlOnScreen) private var onScreen
    @Environment(\.scenePhase) private var scenePhase

    private var mode: DialMode { session.currentMode }
    private var muted: Bool { session.hello?.muted == true }
    private var ticks: Int {
        if mode == .output, let count = session.hello?.devices?.count {
            return max(count, 2)
        }
        return 11
    }

    var body: some View {
        // Only the parts that actually change on a clock live inside a
        // timeline. The first version rebuilt the whole crown — knurled
        // bezel, tick ring, two Canvases, four shadows — twelve times a
        // second, forever. On this machine that was the phone app burning a
        // third of a core while sitting still, and the Mac burning another
        // third answering the connection it kept hot.
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !shouldBreathe)) { timeline in
                let pulse = shouldBreathe
                    ? 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 1.15)
                    : 0.5
                halo(progress: staticProgress, tint: staticTint, pulse: pulse)
            }
            bezel
            wellFace(progress: staticProgress, tint: staticTint)
            trackRing
            tickRing(progress: staticProgress, tint: staticTint)
            movingParts
            cap
        }
        .frame(width: size, height: size)
        .scaleEffect(session.dragging ? 0.972 : 1)
        .animation(reduceMotion ? nil : KnurlMotion.snap, value: session.dragging)
        .contentShape(Circle())
        .gesture(drag)
        .overlay {
            Button {
                session.confirm()
            } label: {
                Color.clear.frame(width: size * 0.46, height: size * 0.46)
            }
            .buttonStyle(ImmediatePressStyle())
            .accessibilityLabel(mode.confirmTitle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityValue(session.hello?.readout ?? mode.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: session.rotate(1)
            case .decrement: session.rotate(-1)
            default: break
            }
        }
    }

    /// The needle and the readout. These follow a playing track, so they get a
    /// timeline — but only while a track is actually playing, and at four
    /// frames a second rather than twelve, which is all a second hand needs.
    @ViewBuilder
    private var movingParts: some View {
        if mode == .media, session.hello?.playing == true, !reduceMotion, onScreen {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let progress = liveProgress(at: timeline.date)
                let tint = phoneTint(mode: mode, progress: progress, muted: muted)
                ZStack {
                    needle(progress: progress, tint: tint, pulse: 0.5)
                    face(progress: progress, tint: tint)
                }
            }
        } else {
            ZStack {
                needle(progress: staticProgress, tint: staticTint, pulse: 0.5)
                face(progress: staticProgress, tint: staticTint)
            }
        }
    }

    /// The value as last reported, without a clock. Everything that is not
    /// literally animating reads this.
    private var staticProgress: Double { liveProgress(at: session.helloAt) }

    private var staticTint: Color {
        phoneTint(mode: mode, progress: staticProgress, muted: muted)
    }

    // MARK: Layers
    //
    // The same luminous ring the Mac draws. No bezel, no teeth, no well —
    // colour and one handle.

    private var ringRadius: CGFloat { size * 0.5 - inset }
    private var inset: CGFloat { size * 0.11 }
    private var lineWidth: CGFloat { size * 0.085 }

    private func halo(progress: Double, tint: Color, pulse: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: tint.opacity(0.50), location: 0.30),
                        .init(color: tint.opacity(0.22), location: 0.58),
                        .init(color: tint.opacity(0), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.70
                )
            )
            .opacity(0.30 + 0.34 * DialMath.clampVolume(progress) + 0.06 * pulse)
            .scaleEffect(1.14)
            .allowsHitTesting(false)
    }

    private var bezel: some View {
        Circle()
            .fill(metal.well)
            .padding(inset + lineWidth * 0.5)
    }

    private func wellFace(progress: Double, tint: Color) -> some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(metal.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .padding(inset)
            .rotationEffect(.degrees(135))
            .allowsHitTesting(false)
    }

    private var trackRing: some View { EmptyView() }

    private func tickRing(progress: Double, tint: Color) -> some View {
        Circle()
            .trim(from: 0, to: 0.75 * DialMath.clampVolume(progress))
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: tint.opacity(0.60), location: 0),
                        .init(color: tint, location: 0.55),
                        .init(color: tint.opacity(0.95), location: 1),
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .padding(inset)
            .rotationEffect(.degrees(135))
            .shadow(color: tint.opacity(0.45), radius: size * 0.045)
            .allowsHitTesting(false)
    }

    private var cap: some View { EmptyView() }

    private var shouldBreathe: Bool {
        !reduceMotion && !session.dragging && onScreen
    }

    private func liveProgress(at date: Date) -> Double {
        if session.dragging, let localProgress { return localProgress }
        let fallback = DialMath.clampVolume(session.hello?.progress ?? 0.12)
        if mode == .media, session.hello?.playing == true, let duration = session.hello?.duration, duration > 1 {
            let elapsed = fallback * duration + date.timeIntervalSince(session.helloAt)
            return DialMath.clampVolume(elapsed / duration)
        }
        return fallback
    }

    @ViewBuilder
    private func face(progress: Double, tint: Color) -> some View {
        if mode == .media, let data = session.art, let image = CoverImage.make(data) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: size * 0.52, height: size * 0.52)
                .clipShape(Circle())
                .overlay(alignment: .bottom) {
                    Text(mediaClock(progress: progress))
                        .font(.system(size: size * 0.048, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, size * 0.08)
                }
                .allowsHitTesting(false)
        } else {
            VStack(spacing: size * 0.018) {
                Image(systemName: crownSymbol)
                    .font(.system(size: size * 0.105, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.6), radius: size * 0.03)
                    .symbolEffect(.bounce, value: reduceMotion ? "" : crownSymbol)
                    .symbolEffectsRemoved(reduceMotion)
                Text(session.hello?.readout ?? mode.title)
                    .font(.knurlNumeral(min(38, size * 0.145)))
                    .foregroundStyle(metal.ink)
                    .minimumScaleFactor(0.35)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                Text(caption.uppercased())
                    .font(.system(size: max(9, size * 0.042), weight: .semibold))
                    .tracking(size * 0.006)
                    .foregroundStyle(metal.ink.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(size * 0.18)
            .allowsHitTesting(false)
        }
    }

    /// The handle. Same as the Mac: a solid puck that says where the value is
    /// and where to put your thumb.
    private func needle(progress: Double, tint: Color, pulse: Double) -> some View {
        Circle()
            .fill(metal.handle)
            .frame(width: lineWidth * 0.86, height: lineWidth * 0.86)
            .overlay { Circle().strokeBorder(metal.handleEdge, lineWidth: 0.5) }
            .overlay {
                Circle()
                    .fill(tint)
                    .frame(width: lineWidth * 0.30, height: lineWidth * 0.30)
            }
            .shadow(color: .black.opacity(0.22), radius: size * 0.018, y: size * 0.006)
            .scaleEffect(session.dragging ? 1.22 : 1)
            .offset(y: -(size / 2 - inset))
            .rotationEffect(.degrees(DialMath.ringAngle(progress: progress)))
            .allowsHitTesting(false)
    }

    private var caption: String {
        switch mode {
        case .media: session.hello?.target ?? mode.title
        case .output: session.hello?.target ?? mode.title
        default: mode.title
        }
    }

    private var crownSymbol: String {
        switch mode {
        case .volume: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .mic: session.isListening ? "waveform" : (muted ? "mic.slash.fill" : "mic.fill")
        case .output: "hifispeaker.fill"
        case .media: session.hello?.playing == true ? "pause.fill" : "play.fill"
        }
    }

    private func mediaClock(progress: Double) -> String {
        if let duration = session.hello?.duration, duration > 1 {
            let elapsed = progress * duration
            return "\(DialMath.clock(elapsed))  −\(DialMath.clock(max(0, duration - elapsed)))"
        }
        return session.hello?.readout ?? "Music"
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !session.dragging {
                    session.dragging = true
                    stepBank = Double(TickSound.detent(from: session.hello?.progress ?? 0.5))
                }
                if mode == .output {
                    turnOutput(value)
                    return
                }
                let dx = value.location.x - size / 2
                let dy = value.location.y - size / 2
                let degrees = atan2(dx, -dy) * 180 / .pi
                guard let next = DialMath.ringProgress(clockwiseFromNoon: degrees) else { return }
                localProgress = next
                session.setProgress(next)
                let detent = TickSound.detent(from: next)
                if detent != Int(stepBank) {
                    stepBank = Double(detent)
                    session.tickDetent()
                }
            }
            .onEnded { _ in
                session.dragging = false
                lastAngle = nil
                stepBank = 0
                localProgress = nil
            }
    }

    private func turnOutput(_ value: DragGesture.Value) {
        let angle = atan2(value.location.y - size / 2, value.location.x - size / 2)
        if let lastAngle {
            var delta = angle - lastAngle
            if delta > Double.pi { delta -= 2 * Double.pi }
            if delta < -Double.pi { delta += 2 * Double.pi }
            stepBank += delta
            let step = Double.pi / 10
            while stepBank > step {
                stepBank -= step
                session.rotate(1)
            }
            while stepBank < -step {
                stepBank += step
                session.rotate(-1)
            }
        }
        lastAngle = angle
    }
}

enum CoverImage {
    static func make(_ data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}
