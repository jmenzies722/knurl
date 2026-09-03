# Knurl

Product: `PRODUCT.md`. Architecture: `docs/KNURL_SESSION_LAYER_PLAN.md`.

Knurl is the live desk for Mac developers. The editor
does the work. Knurl runs the room. Five faces. Three surfaces.
Six Hub pages (Home, Tools, Workspace, Flow, System, Sessions).
One Context Engine. Never a sixth face. Tools is Hour and the room
— not an agent dashboard. Agent UI is Pulse / Attention / Receipts
when those pings are real.

Fun Mac desk — a Tahoe Hub with a hand-built rail (not a
NavigationSplitView), a side dial, and a notch that grows out of the
black camera housing on notched Macs (M1 14/16-inch and later). The
notch is the parked state there: `NotchStage` is rest / glance / hover /
shelf / flow, and `rest` must stay exactly the cutout, one shape with concave top corners, one fixed panel frame — do
not animate the window frame, the window server and the layout race
and the black tears. The floating pill is the parked state only on Macs
with no housing. Dock, ⌘-tab, and Open Knurl open the Hub. Settings
live in the Hub. App Intents switch faces, swap output, start Flow.

Design tokens are in `KnurlCore/KnurlDesign.swift` and are shared with
the phone. Do not add a second palette. Desk tools live in
`Knurl/DeskTools.swift`; the machine-reading half is in
`KnurlCore/MachineVitals.swift` so it can be tested, and is guarded
`#if os(macOS)` because IOKit power management is not on iOS.
Five faces: Media, Volume, Bright, Output, Mic. Swift 6. macOS 26+ /
iOS 26+, Apple Silicon only. No Electron. No Catalyst.
No SkyLight — housing geometry is `auxiliaryTopLeftArea` /
`auxiliaryTopRightArea`.

Media follows Music.app. The dial is the playhead (`player position` /
`duration`); drag and scroll seek. Play / pause / skip use Music Apple
Events. Shuffle, repeat, album, genre, artwork, and user playlists also
use Apple Events — not ScriptingBridge, not `ApplicationMusicPlayer`.
Genre is Music.app’s raw string, shown as its own chip. No score.
MediaRemote, SystemMusicPlayer (unavailable on macOS), SkyLight, Polar,
Input Monitoring, Screen Recording, keystroke storage, and screenshots
are not.

Flow lives on Mic and in the notch. Hold Flow or ⌃⌥M. On a notched
Mac the housing is the detent — do not pop the HUD. `SpeechAnalyzer` +
`DictationTranscriber` on-device. Text goes to the clipboard and one
synthetic ⌘V. No AI rewrite, no cloud Whisper, no always-on mic, no
sixth face.

Window Manager is an opt-in desk capability, not a face. It may use
public Accessibility window attributes after the user enables it.
Faces never request Accessibility. Do not require Screen Recording.

The iPhone app is `Sources/KnurlPhone` + `project.yml` (XcodeGen). It is
the mobile crown of this Mac desk: same five faces, `_knurl._tcp`, no
pairing store. Do not add a Catalyst destination. Relay is a different
product — do not point this phone at `_relay._tcp`.

Output lists Core Audio default-output devices (Bluetooth, HDMI,
AirPlay-after-the-system-has-one) and hosts Apple’s `AVRoutePickerView`
for HomePods / TVs. Knurl does not browse the LAN or pair Bluetooth.

⌃⌥ arrows present Volume. ⌃⌥K summons the last face. ⌃⌥M is Flow.

Do not grow a gesture editor. Polar, landing page, and pricing wait
until the Mac dial is worth buying. KnurlPhone is the iPhone half of
this desk — keep it on the same LAN as the Mac process.

Performance rules learned the hard way, all of them measured:

- `@Observable` invalidates on **assignment**, not on change. The meters
  loop runs 3.5×/second; writing an unchanged value there rebuilt every
  view that read it. Use `set(\.keyPath, value)` in `DialState`.
- Never call AppleScript on the main thread. `MusicScript` owns one
  serial queue; Apple Events to Music.app take tens of milliseconds.
- Prefer `com.apple.Music.playerInfo` over polling. Poll only while
  something is actually moving.
- A hidden window still runs its `TimelineView`s. Gate them on
  `\.knurlOnScreen`, which each surface sets from real visibility.
- Do not put an animated layer behind translucent content, and do not
  draw a full-window gradient that only shows through a 244-point rail.

System callbacks on a `@MainActor` type must be `nonisolated`. macOS calls
`AVCaptureDevice.requestAccess` and `SFSpeechRecognizer.requestAuthorization`
back on a TCC XPC reply queue. A closure that inherits main-actor isolation
there fails Swift's executor check, and the failure mode is
`_dispatch_assert_queue_fail`: instant SIGABRT, no message, no stderr, no
crash report — the app just disappears. Flow did exactly this every time the
mic key was held. Mark the enclosing method `nonisolated`, touch no actor
state in the closure, and let the `await` hop back.
