# Knurl

Product: `PRODUCT.md`. Architecture: `docs/KNURL_SESSION_LAYER_PLAN.md`.

Knurl is the live desk for Mac developers. The editor
does the work. Knurl runs the room. Five faces. Three surfaces.
Six Hub pages (Home, Tools, Workspace, Flow, System, Sessions).
One Context Engine. Never a sixth face. Tools is Hour and the room
— not an agent dashboard. Agent UI is Pulse / Attention / Receipts
when those pings are real.

Fun Mac desk — a Tahoe Hub with a sidebar, a
side dial, and a notch glance that sits in the black camera housing
on notched Macs (M1 14/16-inch and later). The notch is its own
feature: click it to drop a glass shelf from the housing, not the
Hub. Cold start is parked (crown + rail + notch). Dock, ⌘-tab, and
Open Knurl open the Hub. Settings live in the Hub. App Intents
switch faces, swap output, and start or stop Flow.
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
