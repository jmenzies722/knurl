# Knurl

Engineer desk for the Mac — notch glance, side dial, and a full-screen
desk view (the Hub is that view). Five faces: Media, Volume, Bright,
Output, Mic. Swift 6. macOS 26+ / iOS 26+, Apple Silicon only. Click
the notch chip to expand the same Hub across the visible screen.
Escape collapses it. Menu-bar crown and the edge HUD stay. Agent later.
No Electron. No Catalyst.

Media follows Music.app. The dial is the playhead (`player position` /
`duration`); drag and scroll seek. Play / pause / skip use Music Apple
Events. Shuffle, repeat, album, genre, artwork, and user playlists also
use Apple Events — not ScriptingBridge, not `ApplicationMusicPlayer`.
Genre is Music.app’s raw string, shown as its own chip. No score.
MediaRemote, SystemMusicPlayer (unavailable on macOS), SkyLight, Polar,
Input Monitoring, Screen Recording, keystroke storage, and screenshots
are not.

Talk lives on Mic. Hold Talk or ⌃⌥M. `SpeechAnalyzer` +
`DictationTranscriber` on-device. Text goes to the clipboard and one
synthetic ⌘V. No AI rewrite, no cloud Whisper, no always-on mic, no
sixth face.

Spaces, Tile, and Scrub are gone — they only faked keystrokes and AX.

The iPhone app is `Sources/KnurlPhone` + `project.yml` (XcodeGen). Same
LAN only. No pairing store. Do not add a Catalyst destination.

Output lists Core Audio default-output devices (Bluetooth, HDMI,
AirPlay-after-the-system-has-one) and hosts Apple’s `AVRoutePickerView`
for HomePods / TVs. Knurl does not browse the LAN or pair Bluetooth.

⌃⌥ arrows present Volume. ⌃⌥K summons the last face. ⌃⌥M is hold-to-talk.

Do not grow a gesture editor. Polar, landing page, and pricing wait
until the Mac dial is worth buying. KnurlPhone stays parked until then.
