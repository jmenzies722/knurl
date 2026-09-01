public enum DialMath: Sendable {
    public static let volumeStep = 0.05

    public static func clampVolume(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    public static func steppedVolume(current: Double, detents: Int) -> Double {
        clampVolume(current + Double(detents) * volumeStep)
    }

    public static func percent(_ volume: Double) -> Int {
        Int((clampVolume(volume) * 100).rounded())
    }

    /// Map a drag angle (0° = east, CCW) onto a 270° gauge from 7:30 to 4:30.
    /// Returns nil in the bottom gap so the needle cannot wrap backward.
    public static func gaugeProgress(angleDegrees: Double) -> Double? {
        var swept = angleDegrees - 135
        while swept < 0 { swept += 360 }
        while swept >= 360 { swept -= 360 }
        if swept > 270 { return nil }
        return swept / 270
    }

    public static func acceptsGaugeJump(from current: Double, to next: Double) -> Bool {
        abs(next - current) <= 0.32
    }

    public static func gaugeAngle(progress: Double) -> Double {
        135 + clampVolume(progress) * 270
    }

    /// 0° = 12 o'clock, clockwise. Live arc is 7:30 (225°) → 12 → 4:30 (135°).
    public static func ringProgress(clockwiseFromNoon: Double) -> Double? {
        var clock = clockwiseFromNoon
        while clock < 0 { clock += 360 }
        while clock >= 360 { clock -= 360 }
        var swept = clock - 225
        if swept < 0 { swept += 360 }
        if swept > 270 { return nil }
        return swept / 270
    }

    public static func ringAngle(progress: Double) -> Double {
        225 + clampVolume(progress) * 270
    }

    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
