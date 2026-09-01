import Foundation

public struct OutputSnapshot: Sendable, Equatable, Codable {
    public var level: Float
    public var muted: Bool

    public init(level: Float, muted: Bool) {
        self.level = min(1, max(0, level))
        self.muted = muted
    }
}

public struct OutputMemory: Sendable, Equatable, Codable {
    public var snapshots: [String: OutputSnapshot]

    public init(snapshots: [String: OutputSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    public mutating func remember(uid: String, level: Float, muted: Bool) {
        guard !uid.isEmpty else { return }
        snapshots[uid] = OutputSnapshot(level: level, muted: muted)
    }

    public func recall(uid: String) -> OutputSnapshot? {
        snapshots[uid]
    }
}
