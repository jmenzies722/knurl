# Knurl

The live powerhouse desk for Mac developers.

Cursor, Xcode, and the terminal do the work. Knurl runs the room —
music, volume, brightness, speakers, mic, Flow, windows, and power —
so the hour stays fun and the Mac stays fast.

> Have fun. Ship. Stay in the room.

> Five faces. Three surfaces. Six Hub pages. One Context Engine.

> Live desk first. Pings only when they are real.

Someone buys Knurl to enjoy the Mac while they build: a Hub hall,
a side dial, a notch whisper, and one quiet cue if a tool actually
needs a human. Not a chatbot. Not an agent dashboard.

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

1. **Hub** — titled Mac window with a six-page sidebar: Home, Tools,
   Workspace, Flow, System, Sessions. Dock, ⌘-tab, Open Knurl. Cold
   start parked. Close does not quit.
2. **Side dial** — physical input for the five faces. Contextual
   “needs you” may appear. Never an Agent face.
3. **Notch** — the parked state on a notched Mac. One continuous black
   shape that grows downward out of the camera housing, in four stages:
   a compact Live Activity at rest (one glyph, one whisper), the dial
   and glass controls on hover, a shelf on click, and Flow while
   dictating. The top corners are *concave* — the fillet is what makes
   the panel read as the notch itself growing rather than a rectangle
   under it. Not a miniature Hub. No glass on the housing: the cutout
   has no pixels, so material there is material on a bezel.

   On a Mac with no housing the floating pill above the Dock is the
   parked state instead. That is the only reason the pill still exists.

## Hub pages

Home · Tools · Workspace · Flow · System · Sessions

Home leads with the crown, because the crown is what the app is. Under
it the five faces are one compact strip — a lit edge marks where the
dial actually is — then what is playing, then how the machine is
holding up. Feel (tick sound, haptic) lives in Settings only: it is a
preference you set once, not a control of the room, and having it in
two places meant neither was the answer to "where do I change this". Tools is Hour, keep awake, dim the
room, clear the room, swap speakers, Flow, the clipboard shelf, the
app jump strip, and eject.

Six is enough. Do not grow a seventeenth item.

## Desk tools (not faces)

Everything on Tools is a real system call through a public interface,
and none of it asks for a new permission:

- **Keep awake** — `IOPMAssertionCreateWithName`, the mechanism
  `caffeinate` uses. Released on toggle, on timer, and on quit.
- **Vitals** — `host_processor_info`, `host_statistics64`, `getifaddrs`
  and the volume resource keys. CPU per core, memory, disk, network,
  uptime.
- **Clipboard shelf** — `NSPasteboard.changeCount`. Off by default,
  memory only, never written to disk, gone when Knurl quits. It exists
  because Flow already lands text on the clipboard.
- **Clear the room** — `NSWorkspace.hideOtherApplications()`.
- **Jump** — `NSWorkspace.runningApplications` and `activate`.
- **Eject** — `NSWorkspace.unmountAndEjectDevice(at:)`.

Adding a tool costs a tile. It must never cost a face or a permission.

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

Hold ⌃⌥M → speak in the notch → release → paste into the app you were
in. On a notched Mac this is a housing detent, not the
side dial. Black chip while listening; glass shelf drops for levels,
words, destination, Hold / Release / Cancel. On-device
`SpeechAnalyzer` + `DictationTranscriber`. Always show the destination.

## Window Manager

Off by default. Public AX move / resize only. No Screen Recording,
no keystroke tiling, no SkyLight.

## Accessibility, honestly

Two things need it, and both say so on their face rather than failing
quietly:

- **Window Manager**, to move a window.
- **Flow's microphone and speech**, requested the first time you hold it.
- **Flow's paste.** Posting a synthetic ⌘V into another app is
  Accessibility-gated; without it macOS drops the event silently, the
  words stop on the clipboard, and Flow looks broken while reporting
  success. Knurl checks before it claims to have landed anything.

Nothing else asks, and the faces never do.

## Weather

The only part of Knurl that touches the network or your location, and
it is off until you turn it on. Approximate location from CoreLocation,
rounded to about a kilometre, sent to Open-Meteo — no account, no key —
once every half hour. WeatherKit was rejected because it needs a paid
entitlement and would fail silently in a local build.

## Design

Notion information architecture + Apple physicality.

The dial is one luminous ring — a soft bloom, a gradient arc and a grab
handle. It was machined aluminium in an earlier pass; that read as a
photograph of hardware and fought every soft surface near it. Scrubbing
is 1:1 from wherever you grabbed, with ⌥ for quarter-speed.

One design system, in `KnurlCore/KnurlDesign.swift`, shared by the Mac
and the iPhone: `KnurlPalette`, `KnurlSpace`, `KnurlRadius`,
`KnurlMotion`, and the parts built on them (`KnurlSurface`,
`KnurlAtmosphere`, `KnurlBezel`, `KnurlMeter`, `KnurlPip`,
`KnurlSparkline`). It lives in Core so the phone cannot drift from the
Mac — they are two halves of one desk, not two apps that agree by hand.

Glass on faces, Flow, transport, chips, snap controls. Not on session
rows, not on every card, not on the notch housing. Cards get a
`knurlSurface`: a fill, a lit hairline, a specular top edge, a shadow.

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
