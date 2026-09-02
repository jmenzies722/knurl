import Foundation

public struct DeskTimer: Equatable, Sendable {
    public static let maxDuration: TimeInterval = 90 * 60
    public static let presets: [(title: String, seconds: TimeInterval)] = [
        ("15", 15 * 60),
        ("25", 25 * 60),
        ("50", 50 * 60),
        ("90", 90 * 60),
    ]

    public var duration: TimeInterval
    public var remaining: TimeInterval
    public var running: Bool
    public var endsAt: Date?

    public init(
        duration: TimeInterval = 25 * 60,
        remaining: TimeInterval = 25 * 60,
        running: Bool = false,
        endsAt: Date? = nil
    ) {
        self.duration = duration
        self.remaining = remaining
        self.running = running
        self.endsAt = endsAt
    }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return DialMath.clampVolume(remaining / duration)
    }

    public var isArmed: Bool {
        remaining > 0 && remaining < duration
    }

    public var crownProgress: Double {
        if running || isArmed { return progress }
        return DialMath.clampVolume(duration / Self.maxDuration)
    }

    public var readout: String {
        DialMath.sessionClock(remaining)
    }

    public var whisper: String? {
        running && remaining > 0 ? readout : nil
    }

    public mutating func setDuration(_ seconds: TimeInterval) {
        let next = min(Self.maxDuration, max(60, seconds))
        duration = next
        remaining = next
        running = false
        endsAt = nil
    }

    @discardableResult
    public mutating func setCrown(_ value: Double, now: Date = Date()) -> Bool {
        if running || isArmed {
            remaining = max(0, DialMath.clampVolume(value) * duration)
            endsAt = running && remaining > 0 ? now.addingTimeInterval(remaining) : nil
            if remaining <= 0 {
                running = false
                endsAt = nil
                return true
            }
            return false
        }
        setDuration(DialMath.clampVolume(value) * Self.maxDuration)
        return false
    }

    public mutating func start(at now: Date = Date()) {
        if remaining <= 0 { remaining = duration }
        running = true
        endsAt = now.addingTimeInterval(remaining)
    }

    @discardableResult
    public mutating func pause(at now: Date = Date()) -> Bool {
        let done = tick(now: now)
        running = false
        endsAt = nil
        return done
    }

    public mutating func reset() {
        remaining = duration
        running = false
        endsAt = nil
    }

    @discardableResult
    public mutating func tick(now: Date = Date()) -> Bool {
        guard running, let endsAt else { return false }
        remaining = max(0, endsAt.timeIntervalSince(now))
        if remaining > 0 { return false }
        running = false
        self.endsAt = nil
        remaining = 0
        return true
    }
}
