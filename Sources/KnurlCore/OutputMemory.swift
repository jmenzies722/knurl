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

public struct AirPlayDestination: Sendable, Equatable, Codable, Identifiable {
    public var uid: String
    public var name: String
    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// HomePods vanish from Core Audio when AirPlay sleeps. Keep the ones the
/// user has already used so the Output crown can land on them again.
public struct AirPlayMemory: Sendable, Equatable, Codable {
    public var destinations: [AirPlayDestination]

    public init(destinations: [AirPlayDestination] = []) {
        self.destinations = destinations
    }

    public mutating func remember(uid: String, name: String) {
        guard !uid.isEmpty, !name.isEmpty else { return }
        destinations.removeAll { $0.uid == uid }
        destinations.insert(AirPlayDestination(uid: uid, name: name), at: 0)
        if destinations.count > 8 {
            destinations = Array(destinations.prefix(8))
        }
    }
}

public struct MusicAirPlayDevice: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case computer
        case homePod
        case television
        case bluetooth
        case speaker
        case unknown

        public var title: String {
            switch self {
            case .computer: "This Mac"
            case .homePod: "HomePod"
            case .television: "TV"
            case .bluetooth: "Bluetooth"
            case .speaker: "AirPlay"
            case .unknown: "AirPlay"
            }
        }

        public static func parse(_ raw: String) -> Kind {
            let text = raw.lowercased()
            if text.contains("homepod") { return .homePod }
            if text.contains("computer") { return .computer }
            if text.contains("tv") || text.contains("television") { return .television }
            if text.contains("bluetooth") { return .bluetooth }
            if text.contains("airplay") { return .speaker }
            return .unknown
        }
    }

    public static let uidPrefix = "music-airplay:"

    public var name: String
    public var kind: Kind
    public var selected: Bool
    public var available: Bool

    public var id: String { uid }
    public var uid: String { Self.uidPrefix + name }

    public init(name: String, kind: Kind, selected: Bool, available: Bool) {
        self.name = name
        self.kind = kind
        self.selected = selected
        self.available = available
    }

    /// Field values that must never end up displayed as a device name. If a
    /// row ever arrives without its separators, the fields run together and
    /// the first "name" is really the second column — which is how a speaker
    /// called "computer false true" gets onto a screen. Dropping the row is
    /// always better than showing that.
    private static let fieldNoise: Set<String> = [
        "true", "false", "computer", "homepod", "tv", "television",
        "bluetooth", "airplay", "unknown", "missing value",
    ]

    public static func parseList(_ raw: String) -> [MusicAirPlayDevice] {
        raw.split(separator: "\u{1f}", omittingEmptySubsequences: true).compactMap { row in
            let cols = row.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cols.count >= 4 else { return nil }
            let name = cols[0]
            guard !name.isEmpty,
                  !name.contains("\t"),
                  !fieldNoise.contains(name.lowercased())
            else { return nil }
            return MusicAirPlayDevice(
                name: name,
                kind: Kind.parse(cols[1]),
                selected: cols[2].lowercased() == "true",
                available: cols[3].lowercased() == "true"
            )
        }
    }
}
