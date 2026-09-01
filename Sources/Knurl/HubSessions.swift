import KnurlCore
import SwiftUI

struct HubSessions: View {
    @Bindable var state: DialState
    @State private var selected: DeskReceipt.ID?

    var body: some View {
        HubPageScroll {
            Text("Sessions")
                .font(.largeTitle.weight(.semibold))
            Text("What this Mac actually recorded.")
                .font(.title3)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HubSection(title: "This session", accessory: DialMath.sessionClock(timeline.date.timeIntervalSince(state.desk.startedAt))) {
                    HubFact(label: "Harness", value: state.harnessName)
                    HubFact(label: "Agents", value: "\(state.desk.sessions.count)")
                    HubFact(label: "Flow", value: "\(state.desk.flowUses) uses")
                    HubFact(label: "Music", value: state.music.hasTrack ? state.music.title : "—")
                    HubFact(label: "Battery", value: state.desk.power.snapshot.percentLabel)
                    HubFact(label: "Thermal", value: state.desk.power.snapshot.thermal.title)
                }
            }

            HubDivider()

            HubSection(title: "Receipts") {
                if state.desk.receipts.isEmpty {
                    HubEmpty(
                        title: "None yet",
                        detail: "Harness changes, Flow, music, power, and workspace apply land here. No score."
                    )
                } else {
                    ForEach(state.desk.receipts) { receipt in
                        receiptRow(receipt)
                    }
                }
            }
        }
    }

    private func receiptRow(_ receipt: DeskReceipt) -> some View {
        let open = selected == receipt.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.clock.string(from: receipt.at))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 54, alignment: .leading)
                Text(receipt.summary)
                    .font(.callout)
                Spacer()
                if receipt.simulated {
                    Text("Simulated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if open {
                Text(receipt.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 54)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .overlay(ImmediatePress(action: { selected = open ? nil : receipt.id }))
        .accessibilityAddTraits(.isButton)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
