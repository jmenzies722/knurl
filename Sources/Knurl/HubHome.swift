import KnurlCore
import SwiftUI

struct HubHome: View {
    @Bindable var state: DialState

    var body: some View {
        HubPageScroll {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knurl")
                        .font(.largeTitle.weight(.semibold))
                    Text("Workstation")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(DialMath.sessionClock(timeline.date.timeIntervalSince(state.desk.startedAt)))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .padding(.bottom, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)], spacing: 28) {
                HubSection(title: "Current project") {
                    HubFact(label: "Harness", value: state.harnessName)
                    HubFact(
                        label: "Project",
                        value: state.desk.projectName,
                        secondary: "Named when a session reports a worktree."
                    )
                }
                HubSection(title: "Agent pulse", accessory: "\(state.desk.workingCount) working") {
                    HubFact(label: "Working", value: "\(state.desk.workingCount)")
                    HubFact(label: "Needs you", value: needsYou)
                }
                HubSection(title: "Workspace") {
                    HubFact(
                        label: "Layout",
                        value: state.desk.windows.lastPreset?.title ?? "Free",
                        secondary: workspaceLine
                    )
                }
                HubSection(title: "Project pulse") {
                    HubFact(label: "Build", value: "—")
                    HubFact(label: "Tests", value: "—")
                    Text("Build and test facts arrive with agent hooks.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HubSection(title: "Desk") {
                    HubFact(label: "Output", value: state.outputName)
                    HubFact(label: "Volume", value: state.isMuted ? "Muted" : "\(state.volumePercent)%")
                    HubFact(label: "Mic", value: state.inputName)
                    HubFact(label: "Brightness", value: "\(state.brightnessPercent)%")
                }
                HubSection(title: "Power") {
                    HubFact(label: "Battery", value: state.desk.power.snapshot.percentLabel)
                    HubFact(label: "Mode", value: state.desk.powerMode.title)
                    HubFact(label: "Thermal", value: state.desk.power.snapshot.thermal.title)
                    HubFact(label: "Source", value: state.desk.power.snapshot.chargeLabel)
                }
            }

            HubDivider()

            HubSection(title: "Current flow session") {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Text(DialMath.sessionClock(timeline.date.timeIntervalSince(state.desk.startedAt)))
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(state.desk.sessions.count) agents")
                            Text("\(state.desk.flowUses) Flow uses")
                            Text(state.music.hasTrack ? state.music.title : "No music")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        Spacer()
                    }
                }
            }
        }
    }

    private var needsYou: String {
        let count = state.desk.attention.count
        return count == 0 ? "Nothing needs you" : "\(count)"
    }

    private var workspaceLine: String {
        let windows = state.desk.windows.windows.count
        let displays = state.desk.windows.displays.count
        if !state.desk.windows.enabled {
            return "Window Manager is off"
        }
        return "\(windows) windows · \(displays) displays"
    }
}

struct HubPageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .backgroundExtensionEffect()
    }
}
