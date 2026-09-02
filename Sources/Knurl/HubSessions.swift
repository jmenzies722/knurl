import KnurlAgents
import KnurlCore
import SwiftUI

struct HubSessions: View {
    @Bindable var state: DialState
    var agents: AgentSessionManager

    @State private var tab: SessionTab = .live
    @State private var range: AnalyticsRange = .today
    @State private var expanded: Set<UUID> = []
    @State private var openScore: UUID?

    enum SessionTab: String, CaseIterable, Identifiable {
        case live = "Live"
        case history = "History"
        case agentsTab = "Agents"
        case insights = "Insights"
        var id: String { rawValue }
    }

    var body: some View {
        HubPageScroll {
            HubHallHeader(title: "Sessions", whisper: whisper) {
                Picker("", selection: $tab) {
                    ForEach(SessionTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }

            switch tab {
            case .live: liveTab
            case .history: historyTab
            case .agentsTab: agentsTab
            case .insights: insightsTab
            }
        }
    }

    private var whisper: String {
        let live = agents.store.live.count
        if live == 0 { return "No agent session running." }
        return live == 1 ? "One session running." : "\(live) sessions running."
    }

    // MARK: - Live

    @ViewBuilder
    private var liveTab: some View {
        if agents.store.live.isEmpty {
            ContentUnavailableView {
                Label("No session running", systemImage: "waveform.path")
            } description: {
                Text(agents.bridgeIsRunning
                     ? "Knurl is listening for Cursor and Claude Code. Open an agent and a session starts here."
                     : "The local event bridge is not running. Turn on Agent hooks in Settings to track sessions.")
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ForEach(agents.store.live) { session in
                LiveSessionCard(
                    session: session,
                    onPause: { agents.pause(session.id) },
                    onResume: { agents.resume(session.id) },
                    onEnd: { agents.endSession(session.id) },
                    onOpen: { tab = .history }
                )
                HubDivider()
                timeline(for: session)
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historyTab: some View {
        rangePicker

        let scoped = SessionAnalyticsEngine.sessions(agents.store.all, in: range)
        let summary = SessionAnalyticsEngine.summarise(scoped)

        if summary.isEmpty {
            HubEmpty(
                title: "Nothing in this period",
                detail: "Sessions appear once an agent runs with hooks installed, or when a known agent app is frontmost."
            )
        } else {
            HubSection(title: range.title) {
                MetricGrid(summary: summary)
            }
            HubDivider()
            HubSection(title: "Sessions", accessory: "\(scoped.count)") {
                ForEach(scoped) { session in
                    SessionRow(
                        session: session,
                        expanded: expanded.contains(session.id),
                        onToggle: { toggle(session.id) },
                        onOutcome: { agents.store.setOutcome($0, for: session.id) }
                    )
                }
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            rangeChip("Today", .today)
            rangeChip("7 days", .days(7))
            rangeChip("30 days", .days(30))
            Spacer()
        }
    }

    private func rangeChip(_ title: String, _ value: AnalyticsRange) -> some View {
        HubGlassButton(title: title, selected: range == value) { range = value }
    }

    // MARK: - Agents

    @ViewBuilder
    private var agentsTab: some View {
        let rows = SessionAnalyticsEngine.compare(
            SessionAnalyticsEngine.sessions(agents.store.all, in: range)
        )
        rangePicker
        if rows.isEmpty {
            HubEmpty(
                title: "No agent data yet",
                detail: "Comparison needs finished sessions. Cursor and Claude Code report tools and files; others report duration only."
            )
        } else {
            ForEach(rows) { row in
                AgentComparisonRow(row: row)
            }
        }
    }

    // MARK: - Insights

    @ViewBuilder
    private var insightsTab: some View {
        let found = SessionInsightEngine.insights(for: agents.store.all)
        if found.isEmpty {
            ContentUnavailableView {
                Label("Not enough data yet", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Knurl needs at least \(SessionInsightEngine.minimumPerGroup) finished sessions on each side of a comparison before it will claim a pattern. It will not guess.")
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ForEach(found) { insight in
                InsightRow(insight: insight)
            }
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timeline(for session: KnurlAgents.AgentSession) -> some View {
        HubSection(title: "Timeline", accessory: "\(session.events.count) events") {
            if session.events.isEmpty {
                HubEmpty(title: "Nothing recorded yet", detail: "Events appear as the agent works.")
            } else {
                ForEach(session.events.suffix(40).reversed()) { event in
                    TimelineRow(
                        event: event,
                        expanded: expanded.contains(event.id),
                        onToggle: { toggle(event.id) }
                    )
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

// MARK: - Live card

private struct LiveSessionCard: View {
    var session: KnurlAgents.AgentSession
    var onPause: () -> Void
    var onResume: () -> Void
    var onEnd: () -> Void
    var onOpen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let score = EfficiencyScorer.score(session, at: now)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.agent.title)
                            .font(.title3.weight(.semibold))
                        Text(session.displayProject)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(SessionFormat.clock(session.duration(at: now)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }

                HStack(spacing: 28) {
                    clock("Agent active", session.metrics.agentActiveSeconds)
                    clock("You working", session.metrics.humanActiveSeconds)
                    clock("Waiting", session.metrics.idleSeconds)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(score.confidence == .insufficient ? "—" : "\(score.value)")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text("Efficiency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(counters)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if session.status == .paused {
                        HubGlassButton(title: "Resume", symbol: "play.fill", action: onResume)
                    } else {
                        HubGlassButton(title: "Pause", symbol: "pause.fill", action: onPause)
                    }
                    HubGlassButton(title: "End session", symbol: "stop.fill", action: onEnd)
                    HubGlassButton(title: "Details", symbol: "list.bullet", action: onOpen)
                    Spacer()
                    Text(session.agent.integration.title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var counters: String {
        let metrics = session.metrics
        var parts: [String] = []
        if metrics.correctionLoops > 0 { parts.append("\(metrics.correctionLoops) corrections") }
        if metrics.toolCalls > 0 { parts.append("\(metrics.toolCalls) tool calls") }
        if !metrics.filesChanged.isEmpty { parts.append("\(metrics.filesChanged.count) files changed") }
        if metrics.prompts > 0 { parts.append("\(metrics.prompts) prompts") }
        return parts.isEmpty ? "No tool activity reported yet." : parts.joined(separator: " · ")
    }

    private func clock(_ label: String, _ seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(SessionFormat.short(seconds))
                .font(.callout.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rows

private struct TimelineRow: View {
    var event: AgentEvent
    var expanded: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SessionFormat.time(event.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .leading)
                Circle()
                    .fill(SessionFormat.tint(event.kind))
                    .frame(width: 6, height: 6)
                Text(event.summary)
                    .font(.callout)
                    .foregroundStyle(event.kind.isFailure ? Color.orange : .primary)
                Spacer(minLength: 8)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(event.kind.rawValue) · \(event.source.title)")
                    ForEach(event.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key): \(value)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 64)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SessionRow: View {
    var session: KnurlAgents.AgentSession
    var expanded: Bool
    var onToggle: () -> Void
    var onOutcome: (SessionOutcome) -> Void

    var body: some View {
        let score = EfficiencyScorer.score(session)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SessionFormat.time(session.startedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .leading)
                Text(session.agent.title)
                    .font(.callout.weight(.medium))
                Text(session.displayProject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(session.outcome.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SessionFormat.short(session.duration()))
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
                Text(score.confidence == .insufficient ? "—" : "\(score.value)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ScoreExplanation(score: score)
                    HStack(spacing: 8) {
                        Text("Outcome")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { session.outcome },
                            set: { onOutcome($0) }
                        )) {
                            ForEach(SessionOutcome.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        if session.outcomeProvenance == .inferred {
                            Text("Inferred")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.leading, 58)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityAddTraits(.isButton)
    }
}

private struct ScoreExplanation: View {
    var score: EfficiencyScore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Efficiency \(score.confidence == .insufficient ? "—" : String(score.value))")
                .font(.callout.weight(.semibold))
            Text(score.confidence.title)
                .font(.caption)
                .foregroundStyle(.tertiary)
            ForEach(score.contributions) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.delta > 0 ? "+" : "−")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(item.delta > 0 ? Color.green : Color.orange)
                        .frame(width: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label).font(.caption)
                        Text(item.evidence)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct AgentComparisonRow: View {
    var row: AgentComparison

    var body: some View {
        HubSection(title: row.agent.title, accessory: SessionFormat.short(row.summary.totalSeconds)) {
            VStack(alignment: .leading, spacing: 0) {
                HubFact(label: "Sessions", value: "\(row.summary.sessionCount)")
                HubFact(label: "Avg length", value: SessionFormat.short(row.summary.averageSessionSeconds))
                HubFact(label: "Prompts/session", value: String(format: "%.1f", row.promptsPerSession))
                HubFact(label: "Tool failures", value: "\(row.summary.failedToolCalls) of \(row.summary.toolCalls)")
                HubFact(label: "Corrections", value: String(format: "%.1f per session", row.summary.correctionRate))
                HubFact(label: "Successful", value: "\(Int(row.summary.successRate * 100))%")
                HubFact(
                    label: "Avg efficiency",
                    value: row.averageEfficiency.map(String.init) ?? "Not enough data"
                )
                HubFact(
                    label: "Time to result",
                    value: row.averageTimeToResultSeconds.map(SessionFormat.short) ?? "Not reported"
                )
            }
        }
    }
}

private struct InsightRow: View {
    var insight: SessionInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.headline)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(insight.evidence, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Across \(insight.sampleSize) sessions")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct MetricGrid: View {
    var summary: AnalyticsSummary

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 132), spacing: 18, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            cell("Agent time", SessionFormat.short(summary.agentActiveSeconds))
            cell("You working", SessionFormat.short(summary.humanActiveSeconds))
            cell("Waiting", SessionFormat.short(summary.idleSeconds))
            cell("Sessions", "\(summary.sessionCount)")
            cell("Avg length", SessionFormat.short(summary.averageSessionSeconds))
            cell("Longest", SessionFormat.short(summary.longestSessionSeconds))
            cell("Prompts", "\(summary.prompts)")
            cell("Tool calls", "\(summary.toolCalls)")
            cell("Failed tools", "\(summary.failedToolCalls)")
            cell("Files changed", "\(summary.filesChanged)")
            cell("Tests", "\(summary.testRuns - summary.testFailures)/\(summary.testRuns)")
            cell("Corrections", String(format: "%.1f", summary.correctionRate))
            cell("Context switches", "\(summary.contextSwitches)")
            cell("Successful", "\(Int(summary.successRate * 100))%")
        }
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

enum SessionFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func short(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }

    static func time(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func tint(_ kind: AgentEventKind) -> Color {
        switch kind {
        case .toolFailed, .testFailed: .orange
        case .testPassed, .gitCommit, .sessionEnded: .green
        case .userActivity, .contextSwitch: .blue
        case .idleStarted, .idleEnded: .gray
        default: .secondary
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
