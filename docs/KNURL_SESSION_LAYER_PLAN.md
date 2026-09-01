# Knurl Session Layer Plan

Phase 0 audit. Written after reading the repo, running `swift test` (15 passed)
and `scripts/package-app.sh`, and checking current Cursor / Claude Code / Codex
docs. Do not implement adapters until Phase 2+.

North star: the harness does the coding. Knurl runs the desk and the
human-attention loop. Five faces. Three surfaces. One Session Layer.
Surface exceptions, not activity.

---

## Current State

Knurl is a Swift 6 SPM Mac app (`Package.swift`, macOS 26) plus an XcodeGen
iPhone crown (`project.yml`). Lab repo at `~/Developer/labs/knurl`. No Polar.
No Session Layer. No agent code.

`DialState` (~860 lines) is the god object. Three surfaces attach to it:
Hub window, edge HUD, notch chip. Persistence is UserDefaults only.
iPhone talks over Bonjour `_knurl._tcp` (`CrownServer` / `PhoneSession`).
That is a dial remote, not a session.

`DialState.startSession()` is a 400 ms poll loop. The name is a lie.

Verified 2026-09-01:

```text
swift test --parallel   → 15 passed
scripts/package-app.sh  → .build/Knurl.app signed
```

---

## Architecture Map

```text
KnurlApp
  └─ AppDelegate (owns DialState)
        ├─ HubWindow  → HubView
        ├─ HUDPanel   → HUDView
        ├─ NotchPanel → NotchView
        ├─ StatusBar
        ├─ HotkeyCenter
        └─ CrownServer ── KnurlLink ── KnurlPhone

KnurlCore     DialMode, DialMath, audio, notch geometry, output memory
KnurlLink     Crown JSON wire types
KnurlPhone    LAN crown UI
```

Hardware lives in the Knurl target: `MusicApp` (Apple Events), `NowPlaying`,
`Voice`, `Brightness` (DisplayServices + HID), `OutputWatch`, `RoutePicker`.

Reach-back: ~35 `AppDelegate.shared` calls. Intents, hotkeys, panels, and
crown all hit `DialState` through that singleton.

---

## Existing Product Features

Works today:

- Five faces, one grammar (1–5, turn/click, ⌃⌥K / arrows / M)
- Titled Hub, parked cold start, close ≠ quit, remembered frame
- Unified toolbar (Open Music, Settings)
- Face morph (`glassEffectID("face")` on the selected tab)
- Music.app follow (Apple Events, not MediaRemote)
- Volume + per-output memory, built-in brightness, Core Audio + AirPlay picker, Swap
- Mic gain, input picker, hold-to-talk, last transcript, destination chip
- Notch housing via `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, opaque black
- App Intents (`openAppWhenRun = false` except Open Hub)
- Launch at Login
- iPhone LAN crown (do not grow)

Does not exist:

- Session Layer types, store, adapters, bridge
- Agent Pulse, Attention Queue, Jump, Session Receipts
- Worktree Guard, Desk Profiles, Context Health
- Settings sections for Agents / Privacy / retention
- Simulator script

---

## Gaps

| Requirement | Status |
|---|---|
| Agent Pulse | Missing |
| Attention Queue | Missing |
| Jump to session | Missing (harness name is NSWorkspace only) |
| Talk to waiting agent | Talk pastes to last app; no agent routing |
| Attention choreography | Tick exists; not wired to sessions |
| Session Receipts | Missing |
| Worktree Guard | Missing |
| Desk Profiles | Missing |
| Context Health | Missing |
| Hub layout for Pulse / Receipts | Hub is faces + now-playing + three glass cards |
| Notch as attention glance | Notch shows music / harness / face |
| Liquid Glass restraint | Glass on now-playing, stage, Talk, Output, genre, strip chips |
| Settings IA | One flat sheet |
| Knurl-target tests | None (Core only) |

---

## Technical Debt (roadmap-relevant only)

1. `DialState` owns presentation, hardware, music, voice, and crown. Session
   state must not be stuffed into it. New `SessionStore`, observed by views.
2. `mode` vs `control` — two `DialMode` fields. Hub/HUD/intents use `control`.
   Do not add a third. Collapse later; not a Phase 1 rewrite.
3. `AppDelegate.shared` coupling. Session Layer must not depend on it.
   Adapters talk to `SessionStore`. Views take `SessionStore` as a parameter.
4. Three poll loops (400 ms session, 280 ms meters, NowPlaying). Session Layer
   is event-driven. Do not add a fourth poll.
5. UserDefaults scattered (`Preferences`, HUD dock, brightness estimate).
   Receipts get their own store. Do not merge everything first.
6. Crown LAN is unauthenticated JSON. Do not reuse it for agent events.
7. `KnurlRemote` in `project.yml` points at missing sources. Ignore.
8. This machine already has `~/.cursor/hooks.json` entries (VibeBridge and
   local scripts). Cursor install must merge, never overwrite.

---

## Session Layer Architecture

New SPM target `KnurlAgents` (Foundation only). Knurl links it. Tests in
`KnurlAgentsTests`. UI stays in the Knurl target.

```text
Sources/KnurlAgents/
  Core/          types, events, metrics
  Store/         SessionStore actor + snapshot
  Bridge/        localhost receiver
  Adapters/      Cursor, ClaudeCode, Codex, Xcode, Simulator
  Persistence/   receipts on disk
```

### Types

```swift
enum AgentProvider: String, Codable, Sendable {
    case cursor, claudeCode, codex, xcode, unknown
}

enum AgentState: String, Codable, Sendable {
    case starting, working, waitingForInput, waitingForPermission
    case idle, completed, failed
}

enum BlockingReason: String, Codable, Sendable {
    case humanInput, permission, testFailure, mergeConflict, unknown
}

enum SessionEventKind: String, Codable, Sendable {
    case sessionStarted, sessionUpdated
    case toolStarted, toolCompleted
    case fileChanged
    case subagentStarted, subagentCompleted
    case permissionRequested, humanInputRequested
    case contextCompacted
    case testsStarted, testsCompleted
    case sessionIdle, sessionCompleted, sessionFailed
}

struct SessionMetrics: Codable, Sendable, Equatable {
    var subagentCount: Int
    var filesTouched: Int
    var testRuns: Int
    var permissions: Int
    var humanResponses: Int
    var waitingSeconds: TimeInterval
    var autonomousSeconds: TimeInterval
}

struct AgentSession: Identifiable, Codable, Sendable {
    var id: UUID
    var provider: AgentProvider
    var externalSessionID: String?
    var title: String?
    var projectName: String?
    var repositoryURL: URL?
    var branch: String?
    var worktreeURL: URL?
    var state: AgentState
    var blockingReason: BlockingReason?
    var attentionMessage: String?
    var startedAt: Date
    var lastActivityAt: Date
    var endedAt: Date?
    var metrics: SessionMetrics
    var timeline: [SessionReceiptEntry]
}

struct SessionReceiptEntry: Codable, Sendable, Identifiable {
    var id: UUID
    var at: Date
    var kind: SessionEventKind
    var summary: String
}

struct SessionEvent: Sendable {
    var provider: AgentProvider
    var externalSessionID: String
    var kind: SessionEventKind
    var at: Date
    var title: String?
    var projectName: String?
    var worktreePath: String?
    var branch: String?
    var filePath: String?          // path only, never contents
    var attentionMessage: String?
    var blockingReason: BlockingReason?
}

protocol AgentSessionAdapter: Sendable {
    var provider: AgentProvider { get }
    func start() async throws
    func stop() async
}

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [AgentSession] = []
    var attention: [AgentSession] { sessions.filter(\.needsHuman) }
    var pulseSummary: PulseSummary { ... }
    func apply(_ event: SessionEvent)
    func jump(to session: AgentSession)   // activate app; no fake AX targeting
}
```

`needsHuman` = `waitingForInput` | `waitingForPermission` | `failed`.

Views consume `SessionStore`. No provider switches in SwiftUI.

---

## Cursor Integration

Source of truth: [cursor.com/docs/hooks](https://cursor.com/docs/hooks)
(fetched 2026-09-01). Command hooks, JSON stdin/stdout.

Events we will observe (fail open, never block):

| Cursor hook | Knurl event |
|---|---|
| `sessionStart` | `sessionStarted` (`session_id`, `workspace_roots`) |
| `sessionEnd` | `sessionCompleted` or fail from `stop` status |
| `stop` (`completed` / `aborted` / `error`) | `sessionCompleted` / `sessionFailed` |
| `preToolUse` | `toolStarted` |
| `postToolUse` | `toolCompleted` |
| `postToolUseFailure` | `toolCompleted` + possible fail signal |
| `afterFileEdit` | `fileChanged` (path only) |
| `subagentStart` / `subagentStop` | `subagentStarted` / `subagentCompleted` |
| `beforeShellExecution` when Cursor asks | `permissionRequested` if we only *observe*; we do not return deny |
| `preCompact` | `contextCompacted` |

Do not hook `afterAgentThought` or `beforeSubmitPrompt` (noise / prompt text).
Do not store `transcript_path` contents.

Install: a small `knurl-cursor-hook` binary or script that POSTs to the
local bridge. Merge into project `.cursor/hooks.json` **and** offer a user
hook. Never overwrite existing entries (this machine already has VibeBridge
and protect-nectar hooks).

Cloud agents do not run user hooks. Local desk is the product.

Jump: `NSWorkspace` activate `com.todesktop.*` / Cursor bundle. No AX
session targeting.

---

## Claude Code Integration

Source: [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)
(2026-09-01).

Richer than Cursor for attention:

| Claude hook | Knurl event |
|---|---|
| `SessionStart` / `SessionEnd` | session start/end |
| `PreToolUse` / `PostToolUse` / `PostToolUseFailure` | tools |
| `PermissionRequest` | `permissionRequested` → `waitingForPermission` |
| `Notification` `permission_prompt` / `agent_needs_input` / `idle_prompt` | `humanInputRequested` / idle |
| `SubagentStart` / `SubagentStop` | subagents |
| `TaskCreated` / `TaskCompleted` | metrics + title if present |
| `Stop` / `StopFailure` | completed / failed |
| `PreCompact` | `contextCompacted` |

Config lives in `~/.claude/settings.json` (and project `.claude/settings.json`).
Merge a command hook. Fail open. Do not store prompts.

Cursor can also load Claude hook names (third-party hooks). Prefer native
Cursor format for Cursor, native Claude format for Claude Code. Do not
double-fire if both load the same script — key events by
`(provider, externalSessionID, kind, at)`.

---

## Codex Integration

Current supported path is `codex app-server` (JSON-RPC 2.0, stdio or local
WebSocket). That protocol is for **embedding Codex as a client**, not for
watching someone else's session.

Knurl must not spawn `codex app-server` or start threads. That would make
Knurl an agent UI.

Phase 8 options, in order:

1. If a documented observe-only hook or local event tap exists in the
   installed Codex CLI — use that.
2. If Codex Desktop already exposes a loopback event port — subscribe,
   localhost only, validate schema.
3. Otherwise: Codex adapter stays a stub; simulator covers Pulse until a
   public observe API exists.

Do not implement against deprecated `--listen` examples if `--stdio` is
current. Re-read the installed `codex app-server --help` at Phase 8.

Jump: activate the Codex Mac app / CLI frontmost window via bundle id if
known; otherwise tell the user Codex is not jumpable.

---

## Xcode Integration

Public and honest: limited.

- Jump = activate `com.apple.dt.Xcode`
- Frontmost harness already updates `DialState.harnessName`
- No public Xcode agent-session hook as of this audit
- Do not scrape the activity viewer, do not AX the navigator

Adapter reports `unknown` / idle unless Apple ships a hook. Settings:
“Xcode — Limited support.”

---

## UI Integration

Session Layer is **not a sixth face**.

| Surface | What it shows |
|---|---|
| Hub | Agent Pulse (quiet rows), Attention (“Needs you”), Jump, Talk destination, Session Receipts disclosure |
| Dial | No agent dashboard. Optional one-line “Needs you” when Mic/Talk is up |
| Notch | `● 3` / `Claude needs you` / `✓ Codex · 21m` then retract. No lists, no chat |
| Talk | If a session is waiting: “Words land in Claude Code” + Jump/paste |
| Desk strip | `MEDIA · Cursor · knurl/main · Words land in Cursor · 1 needs you` |

Attention choreography (Phase 5): tick + optional brief music duck + notch
island. Never notify on tool/file/subagent chatter.

Liquid Glass: faces, Talk hold, transport, toolbar only. Not on session rows.

---

## Persistence Strategy

Phase 2–3: in-memory `SessionStore` + fixtures.

Phase 10: Codable JSON under

```text
~/Library/Application Support/com.shualabs.knurl/sessions/
```

One file per session id. Actor-serialized writes. Retention:
Off / 7 / 30 / 90 / Forever + Clear.

Do not use SwiftData until receipts prove they need a query engine.
Do not store source, transcripts, prompts, env, secrets, screenshots.

---

## Privacy and Security

Bridge:

- `127.0.0.1` only (HTTP) or a user-scoped Unix socket
- `POST /event` typed JSON, max 64 KB
- No `/run`, `/exec`, `/shell`
- Unknown fields ignored; bad JSON → 400, never crash
- No command execution from payloads
- Paths stored as paths, never file contents

Hooks: observe only. Fail open. Do not return `deny` from Knurl hooks
(Guardrails are Phase “later”).

Privacy copy (only if still true):

> Knurl receives local lifecycle events from supported developer tools.
> Knurl does not record your screen, monitor your keyboard, or send your
> source code to a cloud AI service.

Logging: `os.Logger` subsystems `Knurl.Agent.*`. Never log speech,
source, secrets, prompts.

---

## Testing Strategy

| Layer | How |
|---|---|
| Types / apply() | `KnurlAgentsTests` fixtures: start → work → wait → permission → complete / fail |
| Metrics / timing | Deterministic clocks in tests |
| Persistence | Temp directory, restart, stale, malformed file |
| Bridge | Invalid JSON, oversized body, unknown provider, concurrent POSTs |
| Simulator | `scripts/simulate-agent-event.sh` |
| Adapters | Parser tests against checked-in sample hook payloads (redact secrets) |
| Manual | Notched + non-notched, keyboard, VoiceOver, Reduce Motion, energy |

No live Cursor/Claude required until Phase 6–7.

---

## File Plan

**Phase 1 (Hub workstation — chassis, no live adapters):**

- Six-page Hub sidebar + Context Engine (`DeskContext`)
- Knurl Flow, Smart Notch shelf, Battery Coding, Window Manager v1
- Honest-empty Agents / Receipts. Live hooks are Phase 2+
- `PRODUCT.md`, `AGENTS.md` — workstation north star

**Phase 2+ (do not create yet):**

- `Sources/KnurlAgents/Core/*.swift`
- `Sources/KnurlAgents/Store/SessionStore.swift`
- `Sources/KnurlAgents/Bridge/EventBridge.swift`
- `Sources/KnurlAgents/Adapters/{Cursor,ClaudeCode,Codex,Xcode,Simulator}/*.swift`
- `Tests/KnurlAgentsTests/*.swift`
- `scripts/simulate-agent-event.sh`
- `scripts/install-cursor-hooks.sh` (merge-only)
- `Package.swift` — add `KnurlAgents` target

Do not reorganize App/Core/Services folders to match a fantasy tree.

---

## Risks

- Cursor `beforeShellExecution` can block. Knurl hooks must fail open and
  never become a silent approval proxy until Guardrails is an explicit product.
- Cursor has no `PermissionRequest` / `Notification` (Claude does). Pulse
  for Cursor will be weaker until we infer wait from idle + `stop`.
- Codex observe-only API may not exist. Do not fake it.
- Xcode has no agent hooks. Say “Limited support.”
- User hooks already installed. Merge or we break Vibe / nectar guards.
- `DialState` pollution — the failure mode of rushing Phase 2.
- App Intents metadata still needs `swiftconstvalues`; SPM debug builds
  often omit them. Not a Session Layer blocker.
- DisplayServices is a private symbol load already in-tree for brightness.
  Do not spread that pattern to agent APIs.

---

## Phase order (locked)

0 Audit + this plan — done
1 Hub design foundation — next
2 Session core + tests (no providers)
3 Local bridge + simulator
4 Agent Pulse on simulated data
5 Notch attention
6 Cursor adapter (merge hooks)
7 Claude Code adapter
8 Codex adapter (or honest stub)
9 Talk routing
10 Session Receipts
11 Worktree Guard
12 Desk Profiles
13 Polish and hardening

Do not skip to adapters. Do not add a sixth face.
