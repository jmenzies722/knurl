import KnurlCore
import SwiftUI

struct HubAgents: View {
    @Bindable var state: DialState

    var body: some View {
        HubPageScroll {
            Text("Agents")
                .font(.largeTitle.weight(.semibold))
            Text("Attention, not chat.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HubSection(title: "Needs you") {
                if state.desk.attention.isEmpty {
                    HubEmpty(
                        title: "Nothing needs you",
                        detail: "Approvals and waiting agents surface here. Knurl does not invent them."
                    )
                } else {
                    ForEach(state.desk.attention) { session in
                        agentRow(session, emphasize: true)
                    }
                }
            }

            HubDivider()

            HubSection(title: "Active agents", accessory: "\(state.desk.sessions.count)") {
                if state.desk.sessions.isEmpty {
                    HubEmpty(
                        title: "No agents working",
                        detail: "Cursor, Claude Code, Codex, and Xcode appear when they report in. Hooks are not installed yet."
                    )
                } else {
                    ForEach(state.desk.sessions) { session in
                        agentRow(session, emphasize: session.needsHuman)
                    }
                }
            }

            HubDivider()

            HubSection(title: "Live agent graph") {
                AgentGraph(sessions: state.desk.sessions)
            }

            HubDivider()

            HubSection(title: "Worktree guard") {
                HubEmpty(
                    title: "No overlapping worktrees",
                    detail: "Conflicts appear when two sessions report the same branch or files. Paths only — never source."
                )
            }

            HubDivider()

            HubSection(title: "Support") {
                ForEach(AgentProvider.allCases.filter { $0 != .unknown }) { provider in
                    HubFact(label: provider.title, value: provider.support)
                }
            }
        }
    }

    private func agentRow(_ session: AgentSession, emphasize: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Circle()
                .fill(emphasize ? Color.orange : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.provider.title)
                        .font(.callout.weight(.semibold))
                    if session.simulated {
                        Text("Simulated")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(session.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let message = session.attentionMessage {
                    Text(message)
                        .font(.caption)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.state.title)
                    .font(.caption.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(DialMath.sessionClock(session.elapsed(at: timeline.date)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                HubGlassButton(title: "Jump", symbol: "arrow.up.forward") {
                    state.jumpToHarness()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct AgentGraph: View {
    var sessions: [AgentSession]

    var body: some View {
        VStack(spacing: 18) {
            Text("KNURL")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(.separator.opacity(0.5))
                .frame(width: 1, height: 16)
            HStack(alignment: .top, spacing: 28) {
                ForEach(AgentProvider.allCases.filter { $0 != .unknown }) { provider in
                    let live = sessions.filter { $0.provider == provider }
                    VStack(spacing: 8) {
                        Text(provider.title)
                            .font(.caption.weight(.semibold))
                        if live.isEmpty {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(live) { session in
                                Text(session.state.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(session.needsHuman ? .orange : .secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sessions.isEmpty ? "Agent graph waiting for sessions" : "Agent graph")
    }
}
