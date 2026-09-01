import KnurlLink
import SwiftUI

struct CrownView: View {
    @Bindable var session: PhoneSession
    @State private var drag: CGFloat = 0
    @State private var lastY: CGFloat = 0

    private let modes = [
        ("volume", "speaker.wave.2.fill", "Volume"),
        ("brightness", "sun.max.fill", "Bright"),
        ("media", "playpause.fill", "Media"),
        ("output", "hifispeaker.fill", "Output"),
        ("mic", "mic.fill", "Mic"),
    ]

    var body: some View {
        VStack(spacing: 22) {
            Text(session.hello?.host ?? "Looking for Mac…")
                .font(.headline)
            Text(session.hello?.target ?? session.lastError ?? "Same Wi-Fi as Knurl on the Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            crown
            Text(session.hello?.readout ?? "—")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(modes, id: \.0) { mode in
                    Button {
                        session.select(mode.0)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.1)
                            Text(mode.2)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            session.hello?.mode == mode.0
                                ? Color.accentColor
                                : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                }
            }
            HStack(spacing: 16) {
                Button {
                    session.rotate(-1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 56, height: 44)
                }
                .buttonStyle(.bordered)
                Button("Go") {
                    session.confirm()
                }
                .buttonStyle(.borderedProminent)
                Button {
                    session.rotate(1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 56, height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .onAppear { session.start() }
    }

    private var crown: some View {
        Circle()
            .fill(.black.opacity(0.45))
            .frame(width: 240, height: 240)
            .overlay {
                Circle()
                    .trim(from: 0, to: 0.75 * (session.hello?.progress ?? 0.5))
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .padding(18)
                    .rotationEffect(.degrees(135))
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let delta = value.translation.height - lastY
                        lastY = value.translation.height
                        drag += -delta / 28
                        let steps = Int(drag.rounded(.towardZero))
                        if abs(steps) >= 1 {
                            session.rotate(steps)
                            drag -= CGFloat(steps)
                        }
                    }
                    .onEnded { _ in
                        lastY = 0
                        drag = 0
                    }
            )
            .onTapGesture { session.confirm() }
    }
}
