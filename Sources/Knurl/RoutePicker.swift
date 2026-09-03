import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Holds Apple's route picker so the Output crown can present it when a
/// remembered HomePod is not in Core Audio yet. Knurl does not browse the LAN.
@MainActor
final class AirPlayGate {
    static let shared = AirPlayGate()
    private weak var picker: AVRoutePickerView?

    func bind(_ view: AVRoutePickerView) {
        picker = view
    }

    func present() {
        guard let picker else { return }
        click(in: picker)
    }

    private func click(in view: NSView) {
        if let button = view as? NSButton {
            button.performClick(nil)
            return
        }
        for child in view.subviews {
            click(in: child)
        }
    }
}

/// Apple's AirPlay picker, stretched over the whole HomePod row so a click
/// anywhere opens HomePods / TVs. Knurl does not browse the LAN itself.
struct RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.isRoutePickerButtonBordered = false
        view.player = context.coordinator.player
        AirPlayGate.shared.bind(view)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = context.coordinator.player
        AirPlayGate.shared.bind(view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let player = AVPlayer()
    }
}

struct HomePodRouteButton: View {
    var nearby: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                Image(systemName: "homepod.fill")
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HomePod & AirPlay")
                        .font(.callout.weight(.semibold))
                    Text(nearby
                         ? "Speakers nearby — click to pick one."
                         : "Click to find HomePods, TVs, and AirPlay speakers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "airplayaudio")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            RoutePicker()
                .opacity(0.015)
        }
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose HomePod or AirPlay speaker")
    }
}
