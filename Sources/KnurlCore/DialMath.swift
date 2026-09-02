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

    public static func detentIndex(progress: Double, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let scaled = clampVolume(progress) * Double(count - 1)
        return min(count - 1, max(0, Int(scaled.rounded())))
    }

    public static func detentProgress(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0.5 }
        return clampVolume(Double(index) / Double(count - 1))
    }

    public static func sessionClock(_ interval: Double) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
