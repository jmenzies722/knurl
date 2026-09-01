import KnurlCore
import KnurlLink
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct CrownView: View {
    @Bindable var session: PhoneSession
    @Namespace private var faces
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PhoneAtmosphere(mode: session.currentMode, reduceMotion: reduceMotion)
            if session.isConnected {
                connected
            } else {
                looking
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: session.detentTick)
        .sensoryFeedback(.selection, trigger: session.faceTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: session.confirmTick)
        .onAppear { session.start() }
    }

    private var connected: some View {
        VStack(spacing: 16) {
            statusPill
            if session.currentMode == .media {
                mediaHeader
            }
            Spacer(minLength: 0)
            PhoneCrown(session: session)
            if session.currentMode == .media {
                TransportBar(session: session)
                if let playlists = session.hello?.playlists, !playlists.isEmpty {
                    ChipScroller(items: playlists.map { ($0, $0, false) }) { session.pick($0) }
                }
            } else if let devices = session.hello?.devices, !devices.isEmpty {
                ChipScroller(
                    items: devices.map { ($0.id, $0.name, $0.id == session.hello?.deviceUID) }
                ) { session.pick($0) }
                if session.currentMode == .output {
                    Button("Swap") { session.confirm() }
                        .buttonStyle(.glass)
                }
            }
            if session.currentMode == .mic {
                Text("Talk stays on the Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            faceChips
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var mediaHeader: some View {
        VStack(spacing: 4) {
            Text(session.hello?.title ?? "Music")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(session.hello?.target ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            let detail = [session.hello?.album, session.hello?.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.32, green: 0.92, blue: 0.58))
                .frame(width: 7, height: 7)
            Text(session.hello?.host ?? session.connectedName ?? "Knurl")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var looking: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(emptyTitle).font(.headline)
                Text(session.lastError ?? "Open Knurl on this Mac. Allow Local Network if this stays empty.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if session.macs.count > 1 {
                    ForEach(session.macs) { mac in
                        Button(mac.name) { session.connect(mac) }
                            .buttonStyle(.glassProminent)
                    }
                }
                Button("Look Again") { session.refresh() }
                    .buttonStyle(.glass)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Spacer()
        }
        .padding(24)
    }

    private var emptyTitle: String {
        if session.lastError != nil { return "Couldn’t reach the Mac desk." }
        if session.macs.isEmpty { return "Looking for the Mac desk…" }
        return "Connecting…"
    }

    private var faceChips: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(DialMode.allCases) { mode in
                    let selected = session.face == mode.rawValue
                    Button {
                        session.select(mode.rawValue)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: chipSymbol(mode))
                                .font(.body.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, value: reduceMotion ? 0 : (selected ? session.faceTick : 0))
                            Text(mode.title)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(ImmediatePressStyle())
                    .foregroundStyle(tint(for: mode, muted: chipMuted(mode)))
                    .glassEffect(
                        selected
                            ? .regular.tint(tint(for: mode, muted: chipMuted(mode)).opacity(0.55)).interactive()
                            : .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .modifier(SelectedChipGlass(active: selected && !reduceMotion, namespace: faces))
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func chipSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: (session.hello?.muted == true && session.face == "volume") ? "speaker.slash.fill" : mode.symbol
        case .mic: (session.hello?.muted == true && session.face == "mic") ? "mic.slash.fill" : mode.symbol
        case .media: session.hello?.playing == true ? "pause.fill" : "play.fill"
        default: mode.symbol
        }
    }

    private func chipMuted(_ mode: DialMode) -> Bool {
        session.hello?.muted == true && session.face == mode.rawValue
    }

    private func tint(for mode: DialMode, muted: Bool) -> Color {
        let rgb = DialTint.rgb(progress: session.hello?.progress ?? 0.5, muted: muted, mode: mode)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

private struct SelectedChipGlass: ViewModifier {
    var active: Bool
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if active {
            content.glassEffectID("face", in: namespace)
        } else {
            content
        }
    }
}

private struct TransportBar: View {
    @Bindable var session: PhoneSession

    var body: some View {
        HStack(spacing: 10) {
            glassIcon("shuffle", on: session.hello?.shuffle == true) { session.shuffle() }
            glassIcon("backward.fill", on: false) { session.skip(-1) }
            Button {
                session.confirm()
            } label: {
                Image(systemName: session.hello?.playing == true ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 72, height: 48)
            }
            .buttonStyle(ImmediatePressStyle())
            .glassEffect(.regular.tint(Color(red: 0.96, green: 0.40, blue: 0.52).opacity(0.45)).interactive(), in: Capsule())
            glassIcon("forward.fill", on: false) { session.skip(1) }
            glassIcon(session.hello?.repeat == "one" ? "repeat.1" : "repeat", on: session.hello?.repeat != "off" && session.hello?.repeat != nil) {
                session.cycleRepeat()
            }
        }
        .padding(.top, 4)
    }

    private func glassIcon(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(ImmediatePressStyle())
        .glassEffect(
            on ? .regular.tint(.white.opacity(0.28)).interactive() : .regular.interactive(),
            in: Circle()
        )
    }
}

private struct ChipScroller: View {
    var items: [(id: String, title: String, selected: Bool)]
    var pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    Button(item.title) { pick(item.id) }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .buttonStyle(ImmediatePressStyle())
                        .glassEffect(
                            item.selected
                                ? .regular.tint(.white.opacity(0.28)).interactive()
                                : .regular.interactive(),
                            in: Capsule()
                        )
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollBounceBehavior(.always)
    }
}

private struct PhoneCrown: View {
    @Bindable var session: PhoneSession
    @State private var lastAngle: Double?
    @State private var stepBank = 0.0
    @State private var localProgress: Double?

    private let size: CGFloat = 252

    var body: some View {
        let mode = session.currentMode
        let muted = session.hello?.muted == true
        TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            let progress = liveProgress(at: timeline.date)
            let rgb = DialTint.rgb(progress: progress, muted: muted, mode: mode)
            let tint = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
            ZStack {
                well(tint: tint, mode: mode)
                arc(progress: progress, tint: tint, playing: session.hello?.playing == true)
                if mode != .media {
                    VStack(spacing: 8) {
                        Image(systemName: crownSymbol(mode, muted: muted))
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(tint)
                            .contentTransition(.symbolEffect(.replace))
                        Text(session.hello?.readout ?? mode.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .glassEffect(.regular.tint(.black.opacity(0.35)), in: Capsule())
                            .contentTransition(.numericText())
                    }
                } else {
                    VStack {
                        Spacer()
                        Text(capsuleText(progress: progress))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassEffect(.regular.tint(.black.opacity(0.4)), in: Capsule())
                            .padding(.bottom, 28)
                    }
                    .frame(width: 168, height: 168)
                    .allowsHitTesting(false)
                }
                Button {
                    session.confirm()
                } label: {
                    Color.clear.frame(width: 120, height: 120)
                }
                .buttonStyle(ImmediatePressStyle())
                .accessibilityLabel(mode.confirmTitle)
            }
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.2)).interactive(), in: Circle())
            .contentShape(Circle())
            .gesture(drag)
            .animation(session.dragging ? nil : .snappy(duration: 0.16), value: session.hello?.readout)
            .animation(.snappy(duration: 0.18), value: session.face)
            .accessibilityValue(session.hello?.readout ?? "")
        }
    }

    private func liveProgress(at date: Date) -> Double {
        if session.dragging, let localProgress { return localProgress }
        let fallback = DialMath.clampVolume(session.hello?.progress ?? 0.12)
        if session.hello?.playing == true, let duration = session.hello?.duration, duration > 1 {
            let elapsed = fallback * duration + date.timeIntervalSince(session.helloAt)
            return DialMath.clampVolume(elapsed / duration)
        }
        return fallback
    }

    private func capsuleText(progress: Double) -> String {
        if let duration = session.hello?.duration, duration > 1 {
            let elapsed = progress * duration
            return "\(DialMath.clock(elapsed))  −\(DialMath.clock(max(0, duration - elapsed)))"
        }
        return session.hello?.readout ?? "Music"
    }

    private func crownSymbol(_ mode: DialMode, muted: Bool) -> String {
        switch mode {
        case .volume: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .mic: muted ? "mic.slash.fill" : "mic.fill"
        default: mode.symbol
        }
    }

    private func well(tint: Color, mode: DialMode) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.28))
            if mode == .media, let data = session.art, let image = CoverImage.make(data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 168, height: 168)
                    .clipShape(Circle())
            } else {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        .init(0, 0), .init(0.5, 0), .init(1, 0),
                        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                        .init(0, 1), .init(0.5, 1), .init(1, 1),
                    ],
                    colors: [
                        tint.opacity(0.55), .clear, Color(red: 1.0, green: 0.78, blue: 0.32).opacity(0.28),
                        .clear, tint.opacity(0.16), .clear,
                        Color(red: 0.98, green: 0.55, blue: 0.42).opacity(0.2),
                        .clear,
                        Color(red: 0.42, green: 0.86, blue: 0.78).opacity(0.26),
                    ]
                )
                .clipShape(Circle())
            }
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .padding(16)
                .rotationEffect(.degrees(135))
            ForEach(0..<11, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index % 5 == 0 ? 0.34 : 0.12))
                    .frame(width: 1.6, height: index % 5 == 0 ? 9 : 4)
                    .offset(y: -92)
                    .rotationEffect(.degrees(135 + Double(index) / 10 * 270))
            }
        }
    }

    private func arc(progress: Double, tint: Color, playing: Bool) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75 * max(progress, 0.02))
                .stroke(
                    AngularGradient(
                        colors: [Color(red: 0.45, green: 0.50, blue: 0.86), tint],
                        center: .center,
                        startAngle: .degrees(135),
                        endAngle: .degrees(135 + 270 * max(progress, 0.001))
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .padding(16)
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(playing ? 0.55 : 0.22), radius: playing ? 12 : 5)
            Capsule()
                .fill(.white)
                .frame(width: 5, height: 22)
                .offset(y: -92)
                .rotationEffect(.degrees(DialMath.ringAngle(progress: progress)))
        }
        .allowsHitTesting(false)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !session.dragging {
                    session.dragging = true
                    stepBank = Double(TickSound.detent(from: session.hello?.progress ?? 0.5))
                }
                let mode = session.currentMode
                if mode == .output {
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
}

private enum CoverImage {
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

private struct PhoneAtmosphere: View {
    var mode: DialMode
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            Color.black
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(0.42, 0.38), .init(1, 0.55),
                    .init(0, 1), .init(0.55, 1), .init(1, 1),
                ],
                colors: atmosphereColors
            )
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: mode)
    }

    private var atmosphereColors: [Color] {
        let rgb = DialTint.rgb(progress: 0.55, muted: false, mode: mode)
        let tint = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        return [
            tint.opacity(0.42),
            Color(red: 0.22, green: 0.12, blue: 0.40),
            Color(red: 0.08, green: 0.28, blue: 0.48),
            Color(red: 0.18, green: 0.08, blue: 0.28),
            tint.opacity(0.28),
            Color(red: 0.06, green: 0.22, blue: 0.36),
            Color(red: 0.04, green: 0.06, blue: 0.14),
            Color(red: 0.12, green: 0.08, blue: 0.22),
            Color.black,
        ]
    }
}
