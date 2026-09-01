# Knurl

The workstation layer for agentic engineering on macOS.

The coding harness does the coding. Knurl runs the desk: project,
agents, windows, voice, hardware, and the human-attention loop.

> Run your agents. Control your Mac. Stay in flow.

> Five faces. Three surfaces. Six Hub pages. One Context Engine.

> Surface exceptions, not activity.

Someone buys Knurl to stay in Cursor, Xcode, Claude Code, or Codex
while Knurl handles the room — Music, volume, brightness, output, mic,
Knurl Flow, windows, power, and one quiet cue when an agent needs a
human.

Knurl is not an IDE, chatbot, coding agent, terminal, Git client,
PR board, Raycast clone, or Control Center clone.

Architecture: `docs/KNURL_SESSION_LAYER_PLAN.md`.
Build rules: `AGENTS.md`.

---

## Context Engine

One shared understanding, many views:

- what project you are in
- which harness is active
- which agents are running
- which windows belong to the workspace
- where voice should go
- what the Mac hardware is doing
- what needs attention
- what happened this session

Hub, dial, notch, menu bar, and eventually iPhone read that state.
They are not separate apps in a shell.

---

## Five faces (exactly five)

Media · Volume · Bright · Output · Mic

Never add Agent, Focus, Git, Terminal, Tasks, or Windows as a face.
Agent work is the Session Layer. Window Manager is an opt-in desk
capability. Both live in the Hub, not on the crown.

Turn / click. 1–5. Tab / arrows / scroll / Space. ⌃⌥K dial. ⌃⌥M
Knurl Flow. Escape parks the HUD.

## Three surfaces

1. **Hub** — titled Mac window with a six-page sidebar: Home, Agents,
   Workspace, Flow, System, Sessions. Dock, ⌘-tab, Open Knurl. Cold
   start parked. Close does not quit.
2. **Side dial** — physical input for the five faces. Contextual
   “needs you” may appear. Never an Agent face.
3. **Notch** — a whisper in the black camera housing. Click expands
   a glass shelf from the housing. Not a miniature Hub. No glass on
   the housing.

## Hub pages

Home · Agents · Workspace · Flow · System · Sessions

Six is enough. Do not grow a seventeenth item.

## Session Layer (not a face)

Answers only:

1. What agents are working?
2. Does any need the human?
3. Why?
4. Where should I jump?
5. Where do dictated words go?
6. What happened this session?

Live harness hooks are a later pass. The chassis is honest when empty.
Unlabeled simulator rows are a bug.

## Knurl Flow

Hold or toggle → speak → release → paste into the remembered
non-Knurl app. On-device `SpeechAnalyzer` + `DictationTranscriber`.
Always show the destination. When an agent is waiting, words land
there — never silently.

## Window Manager

Off by default. Enabling it is the first moment Knurl may ask for
Accessibility. Public AX move / resize only. No Screen Recording,
no keystroke tiling, no SkyLight.

## Design

Notion information architecture + Apple physicality.

Glass on faces, Flow, transport, toolbar, snap controls. Not on
session rows, not on every card, not on the notch housing.

## Stack

Swift 6. Native Mac. Apple Silicon. macOS 26. No Electron. No
Catalyst. Repo: `~/Developer/labs/knurl`. Do not touch Puck.

Banned: Input Monitoring, Screen Recording, keystrokes (except the
documented Flow ⌘V), screenshots, SkyLight, MediaRemote,
ScriptingBridge, private Focus APIs, SMC / pmset thermal hacks.

Music means Music.app. Brightness is the built-in display.

## How to run

```bash
cd ~/Developer/labs/knurl
swift test
scripts/package-app.sh
open .build/Knurl.app
```
