import SwiftUI

struct FlowWaveform: View {
    var levels: [Float]
    var tint: Color
    var bars: Int = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: levels.isEmpty)) { _ in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0 ..< bars, id: \.self) { index in
                    Capsule()
                        .fill(tint.opacity(0.28 + Double(sample(index)) * 0.72))
                        .frame(width: 3, height: 6 + CGFloat(sample(index)) * 28)
                }
            }
            .frame(height: 36)
            .accessibilityHidden(true)
        }
    }

    private func sample(_ index: Int) -> Float {
        guard !levels.isEmpty else { return 0.12 }
        let start = max(0, levels.count - bars)
        let slice = Array(levels.dropFirst(start))
        if index < slice.count { return min(1, max(0.08, slice[index])) }
        return 0.1
    }
}
