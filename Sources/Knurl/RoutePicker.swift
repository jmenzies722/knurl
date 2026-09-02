import AVKit
import SwiftUI

struct RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}

struct HomePodRouteButton: View {
    var nearby: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "homepod.fill")
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("HomePod & AirPlay")
                    .font(.callout.weight(.semibold))
                Text(nearby ? "Speakers nearby — click to pick one." : "Click to find HomePods, TVs, and AirPlay speakers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            RoutePicker()
                .frame(width: 36, height: 36)
                .accessibilityLabel("Choose HomePod or AirPlay speaker")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
