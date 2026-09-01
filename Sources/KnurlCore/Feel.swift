import Foundation

public enum TickSound: String, CaseIterable, Sendable, Identifiable {
    case tink
    case pop
    case bottle
    case purr
    case silent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tink: "Tink"
        case .pop: "Pop"
        case .bottle: "Bottle"
        case .purr: "Purr"
        case .silent: "Silent"
        }
    }

    public var fileName: String? {
        switch self {
        case .tink: "Tink"
        case .pop: "Pop"
        case .bottle: "Bottle"
        case .purr: "Purr"
        case .silent: nil
        }
    }

    public static func detent(from progress: Double) -> Int {
        Int((DialMath.clampVolume(progress) / DialMath.volumeStep).rounded())
    }
}

public enum DialTint: Sendable {
    /// Cool indigo at rest, system blue in the middle, warm amber at the top.
    public static func rgb(progress: Double, muted: Bool) -> (Double, Double, Double) {
        rgb(progress: progress, muted: muted, mode: .volume)
    }

    public static func rgb(progress: Double, muted: Bool, mode: DialMode) -> (Double, Double, Double) {
        if muted { return (0.55, 0.56, 0.58) }
        switch mode {
        case .volume:
            let t = DialMath.clampVolume(progress)
            if t < 0.5 {
                return mix((0.45, 0.50, 0.86), (0.35, 0.58, 0.98), t / 0.5)
            }
            return mix((0.35, 0.58, 0.98), (0.98, 0.62, 0.28), (t - 0.5) / 0.5)
        case .brightness:
            return mix((0.28, 0.24, 0.18), (1.0, 0.78, 0.32), DialMath.clampVolume(progress))
        case .media:
            return mix((0.62, 0.36, 0.92), (0.96, 0.40, 0.52), DialMath.clampVolume(progress))
        case .output:
            return (0.22, 0.78, 0.72)
        case .mic:
            return mix((0.36, 0.78, 0.46), (0.98, 0.72, 0.28), DialMath.clampVolume(progress))
        }
    }

    private static func mix(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double),
        _ t: Double
    ) -> (Double, Double, Double) {
        (
            a.0 + (b.0 - a.0) * t,
            a.1 + (b.1 - a.1) * t,
            a.2 + (b.2 - a.2) * t
        )
    }
}
