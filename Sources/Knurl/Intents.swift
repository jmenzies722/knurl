import AppIntents
import KnurlCore

enum FaceEntity: String, AppEnum {
    case media
    case volume
    case brightness
    case output
    case mic

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Face"
    }

    static var caseDisplayRepresentations: [FaceEntity: DisplayRepresentation] {
        [
            .media: "Media",
            .volume: "Volume",
            .brightness: "Bright",
            .output: "Output",
            .mic: "Mic",
        ]
    }

    var mode: DialMode {
        DialMode(rawValue: rawValue) ?? .volume
    }
}

@MainActor
private func knurlState() throws -> DialState {
    guard let state = AppDelegate.shared?.state else {
        throw KnurlIntentError.notReady
    }
    return state
}

private enum KnurlIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady

    var localizedStringResource: LocalizedStringResource {
        "Knurl isn’t ready yet. Open the app once, then try again."
    }
}

struct SelectFaceIntent: AppIntent {
    static var title: LocalizedStringResource { "Switch Knurl Face" }
    static var description: IntentDescription { "Select Media, Volume, Bright, Output, or Mic." }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Face")
    var face: FaceEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        try knurlState().selectControl(face.mode)
        return .result()
    }
}

struct SwapOutputIntent: AppIntent {
    static var title: LocalizedStringResource { "Swap Knurl Output" }
    static var description: IntentDescription { "Switch back to the last speaker." }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try knurlState().swapSpeaker()
        return .result()
    }
}

struct StartTalkIntent: AppIntent {
    static var title: LocalizedStringResource { "Start Knurl Flow" }
    static var description: IntentDescription { "Begin Knurl Flow. Run Stop Knurl Flow when finished." }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try knurlState().beginTalk(presentHUD: false)
        return .result()
    }
}

struct StopTalkIntent: AppIntent {
    static var title: LocalizedStringResource { "Stop Knurl Flow" }
    static var description: IntentDescription { "Finish Flow and paste into the last app." }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try knurlState().endTalk()
        return .result()
    }
}

struct OpenHubIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Knurl" }
    static var description: IntentDescription { "Open the Knurl Hub window." }

    @MainActor
    func perform() async throws -> some IntentResult {
        try knurlState().presentHub()
        return .result()
    }
}

struct ShowDialIntent: AppIntent {
    static var title: LocalizedStringResource { "Show Knurl Dial" }
    static var description: IntentDescription { "Open the side dial." }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.noteHUDActivation()
        try knurlState().summon()
        return .result()
    }
}

struct KnurlShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SelectFaceIntent(),
            phrases: [
                "Switch \(.applicationName) to \(\.$face)",
                "Set \(.applicationName) face to \(\.$face)",
            ],
            shortTitle: "Switch face",
            systemImageName: "dial.medium"
        )
        AppShortcut(
            intent: SwapOutputIntent(),
            phrases: [
                "Swap \(.applicationName) output",
                "Switch \(.applicationName) speaker",
            ],
            shortTitle: "Swap output",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: StartTalkIntent(),
            phrases: [
                "Start \(.applicationName) talk",
                "Start \(.applicationName) flow",
            ],
            shortTitle: "Start Flow",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopTalkIntent(),
            phrases: [
                "Stop \(.applicationName) talk",
                "Stop \(.applicationName) flow",
            ],
            shortTitle: "Stop Flow",
            systemImageName: "mic.slash.fill"
        )
        AppShortcut(
            intent: OpenHubIntent(),
            phrases: [
                "Open \(.applicationName)",
            ],
            shortTitle: "Open Knurl",
            systemImageName: "macwindow"
        )
        AppShortcut(
            intent: ShowDialIntent(),
            phrases: [
                "Show \(.applicationName) dial",
            ],
            shortTitle: "Show dial",
            systemImageName: "circle.lefthalf.filled"
        )
    }
}
