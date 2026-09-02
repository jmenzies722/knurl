import Foundation

public struct MenuBarLive: Equatable, Sendable {
    public var symbol: String
    public var line: String
    public var detail: String
    public var playing: Bool

    public init(symbol: String, line: String, detail: String = "", playing: Bool = false) {
        self.symbol = symbol
        self.line = line
        self.detail = detail
        self.playing = playing
    }

    public var pillWidth: CGFloat {
        if line.isEmpty { return 28 }
        let text = min(128, CGFloat(line.count) * 7.1)
        return min(176, 28 + text)
    }

    public static func snapshot(
        listening: Bool,
        attention: String?,
        musicTitle: String?,
        musicPlaying: Bool,
        outputName: String?,
        timerRemaining: String? = nil,
        destination: String? = nil
    ) -> MenuBarLive {
        if listening {
            let dest = destination?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return MenuBarLive(
                symbol: "waveform",
                line: "Flow",
                detail: dest.isEmpty ? "Listening" : "→ \(dest)",
                playing: false
            )
        }
        if let timerRemaining, !timerRemaining.isEmpty {
            return MenuBarLive(symbol: "timer", line: timerRemaining, detail: "Hour", playing: false)
        }
        if let attention, !attention.isEmpty {
            return MenuBarLive(symbol: "circle.fill", line: attention, detail: "Needs you", playing: false)
        }
        if let musicTitle, !musicTitle.isEmpty {
            return MenuBarLive(
                symbol: musicPlaying ? "pause.fill" : "play.fill",
                line: musicTitle,
                detail: "Music",
                playing: musicPlaying
            )
        }
        if let outputName, !outputName.isEmpty {
            return MenuBarLive(symbol: "hifispeaker.fill", line: outputName, detail: "Output")
        }
        return MenuBarLive(symbol: "dial.medium", line: "Knurl")
    }
}
