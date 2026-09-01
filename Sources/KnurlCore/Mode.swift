public enum DialMode: String, CaseIterable, Sendable, Identifiable {
    case media
    case volume
    case brightness
    case output
    case mic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .volume: "Volume"
        case .brightness: "Bright"
        case .media: "Media"
        case .output: "Output"
        case .mic: "Mic"
        }
    }

    public var symbol: String {
        switch self {
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .media: "playpause.fill"
        case .output: "hifispeaker.fill"
        case .mic: "mic.fill"
        }
    }

    public var confirmTitle: String {
        switch self {
        case .volume: "Mute"
        case .brightness: "Half"
        case .media: "Play / Pause"
        case .output: "Swap"
        case .mic: "Mute mic"
        }
    }

    public var isGauge: Bool {
        self == .volume || self == .brightness || self == .mic
    }

    public var stepBackSymbol: String {
        switch self {
        case .volume, .brightness, .mic: "minus"
        case .media: "backward.fill"
        case .output: "chevron.left"
        }
    }

    public var stepForwardSymbol: String {
        switch self {
        case .volume, .brightness, .mic: "plus"
        case .media: "forward.fill"
        case .output: "chevron.right"
        }
    }

    public var hint: String {
        switch self {
        case .volume: "Turn for level. Click to mute."
        case .brightness: "Turn for this Mac’s built-in display. Externals keep their own controls. Click for halfway."
        case .media: "Turn to seek. Arrows skip. 1–5 switch faces. Click to play or pause."
        case .output: "Turn to pick a speaker. AirPlay for HomePods and TVs."
        case .mic: "Turn for gain. Hold Flow or ⌃⌥M. Click to mute."
        }
    }

    public func advanced(by delta: Int) -> DialMode {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), !all.isEmpty else { return self }
        let count = all.count
        let next = ((index + delta) % count + count) % count
        return all[next]
    }
}
