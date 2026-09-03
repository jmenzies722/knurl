import KnurlCore
import KnurlLink
import SwiftUI

struct CrownView: View {
    @Bindable var session: PhoneSession
    @Namespace private var faces
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            KnurlAtmosphere(
                tint: phoneTint(
                    mode: session.currentMode,
                    progress: session.hello?.progress ?? 0.5,
                    muted: session.hello?.muted == true
                ),
                energy: energy,
                lively: !reduceMotion
            )
            if session.isConnected {
                room
            } else {
                looking
            }
        }
        // Nothing animates while the app is in the background. On the Mac
        // remote this matters as much as on the phone: a window behind your
        // editor was still driving a twelve-frame-a-second crown.
        .environment(\.knurlOnScreen, scenePhase == .active)
        .sensoryFeedback(.selection, trigger: session.detentTick)
        .sensoryFeedback(.selection, trigger: session.faceTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: session.confirmTick)
        .animation(PhoneMotion.spring(reduceMotion: reduceMotion), value: session.face)
        .animation(PhoneMotion.spring(reduceMotion: reduceMotion), value: session.isListening)
        .onAppear { session.start() }
    }

    /// How lit the room is. Same rule as the Mac: something actually
    /// happening makes the field glow, so the phone in your hand and the Hub
    /// on the desk are never telling you different stories.
    private var energy: Double {
        var value = 0.20
        if session.hello?.playing == true { value += 0.30 }
        if session.isListening { value += 0.35 }
        return min(1, value)
    }

    private var room: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            PhoneHallHeader(title: session.currentMode.title, whisper: whisper) {
                flowHold
            }
            .padding(.horizontal, KnurlSpace.room)
            .padding(.top, KnurlSpace.snug)

            ScrollView {
                VStack(alignment: .leading, spacing: KnurlSpace.room) {
                    PhoneCrown(session: session)
                        .frame(maxWidth: .infinity)
                        .padding(.top, KnurlSpace.tight)
                    Text(session.currentMode.hint)
                        .font(.system(size: 12))
                        .foregroundStyle(KnurlPalette.inkFaint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    stage
                }
                .padding(.horizontal, KnurlSpace.room)
                .padding(.bottom, KnurlSpace.room)
            }
            .scrollIndicators(.never)

            faceChips
                .padding(.horizontal, KnurlSpace.step)
                .padding(.bottom, KnurlSpace.tight)
        }
    }

    private var whisper: String {
        let host = session.hello?.host ?? session.connectedName ?? "Mac"
        if session.isListening {
            return "Flow → \(session.destination)"
        }
        return "\(host) · \(session.wordsLand)"
    }

    private var flowHold: some View {
        HStack(spacing: KnurlSpace.tight) {
            if session.isListening {
                PhoneChip(title: "Cancel", symbol: "xmark", tint: KnurlPalette.alert) {
                    session.cancelTalk()
                }
                .accessibilityLabel("Cancel Flow")
            }
            PhoneHold(
                down: { session.beginTalk() },
                up: { session.endTalk() }
            ) {
                HStack(spacing: KnurlSpace.tight) {
                    Image(systemName: session.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .symbolEffect(
                            .variableColor.iterative,
                            isActive: session.isListening && !reduceMotion
                        )
                    Text(session.isListening ? "Release" : "Hold")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(session.isListening ? .white : KnurlPalette.ink)
                .padding(.horizontal, KnurlSpace.step)
                .frame(height: 38)
                .background {
                    Capsule().fill(
                        session.isListening
                            ? KnurlPalette.live
                            : KnurlPalette.control
                    )
                }
                .overlay {
                    Capsule().strokeBorder(
                        session.isListening ? .clear : KnurlPalette.hairline,
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: session.isListening ? KnurlPalette.live.opacity(0.5) : .clear,
                    radius: 14,
                    y: 3
                )
            }
            .accessibilityLabel(session.isListening ? "Release to paste" : "Hold to talk")
            .accessibilityHint(session.wordsLand)
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch session.currentMode {
        case .media:
            mediaStage
        case .output:
            outputStage
        case .mic:
            micStage
        case .volume, .brightness:
            EmptyView()
        }
    }

    private var mediaStage: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            TransportBar(session: session)
            PhoneSection(title: "Track") {
                VStack(spacing: 0) {
                    PhoneFact(label: "Track", value: session.hello?.title ?? "Music")
            if let artist = session.hello?.target, !artist.isEmpty {
                PhoneFact(label: "Artist", value: artist)
            }
            if let album = session.hello?.album, !album.isEmpty {
                PhoneFact(label: "Album", value: album)
            }
            if let genre = session.hello?.genre, !genre.isEmpty {
                PhoneFact(label: "Genre", value: genre)
            }
                }
                .padding(KnurlSpace.step)
                .knurlSurface()
            }
            if let playlists = session.hello?.playlists, !playlists.isEmpty {
                PhoneSection(title: "Playlist", accessory: "\(playlists.count)") {
                    ChipScroller(items: playlists.map { ($0, $0, false) }) { session.pick($0) }
                }
            }
        }
    }

    private var outputStage: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            if let devices = session.hello?.devices, !devices.isEmpty {
                PhoneSection(title: "Speakers", accessory: "\(devices.count)") {
                    VStack(spacing: 3) {
                        ForEach(devices) { device in
                            PhoneDeviceRow(
                                name: device.name,
                                detail: device.kind,
                                selected: device.id == session.hello?.deviceUID
                            ) {
                                session.pick(device.id)
                            }
                        }
                    }
                }
            }
            PhoneChip(
                title: "Swap",
                symbol: "arrow.triangle.2.circlepath",
                tint: phoneTint(mode: .output, progress: 0.5, muted: false),
                selected: true
            ) {
                session.confirm()
            }
            .accessibilityLabel("Swap speakers")
        }
    }

    private var micStage: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            PhoneSection(title: "Flow") {
                VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                    HStack(spacing: KnurlSpace.tight) {
                        KnurlPip(
                            tint: KnurlPalette.live,
                            live: session.isListening,
                            lively: !reduceMotion,
                            size: 7
                        )
                        Text(session.wordsLand)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KnurlPalette.ink)
                    }
                    Text(talkStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(KnurlPalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KnurlSpace.step)
                .knurlSurface(
                    session.isListening ? .raised : .card,
                    tint: session.isListening ? KnurlPalette.live : nil,
                    glow: session.isListening ? 0.4 : 0
                )
            }
            if let devices = session.hello?.devices, !devices.isEmpty {
                PhoneSection(title: "Input", accessory: "\(devices.count)") {
                    VStack(spacing: 3) {
                        ForEach(devices) { device in
                            PhoneDeviceRow(
                                name: device.name,
                                detail: device.kind,
                                selected: device.id == session.hello?.deviceUID
                            ) {
                                session.pick(device.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var talkStatus: String {
        if session.isListening {
            return session.hello?.preview?.isEmpty == false ? (session.hello?.preview ?? "Listening…") : "Listening…"
        }
        if let preview = session.hello?.preview, !preview.isEmpty {
            return preview
        }
        return "Hold, speak, release. Speech stays on the Mac."
    }

    private var looking: some View {
        VStack(spacing: KnurlSpace.room) {
            Spacer()
            ZStack {
                Circle()
                    .fill(KnurlPalette.calm)
                    .blur(radius: 40)
                    .opacity(session.lastError == nil ? 0.30 : 0.10)
                    .frame(width: 160, height: 160)
                Circle()
                    .strokeBorder(KnurlPalette.hairline, lineWidth: 1)
                    .frame(width: 128, height: 128)
                Image("KnurlMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)
            }
            .frame(height: 160)

            VStack(spacing: KnurlSpace.tight) {
                Text(emptyTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(KnurlPalette.ink)
                    .multilineTextAlignment(.center)
                Text(emptyDetail)
                    .font(.system(size: 14))
                    .foregroundStyle(KnurlPalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.macs.count > 1 {
                VStack(spacing: KnurlSpace.tight) {
                    ForEach(session.macs) { mac in
                        Button {
                            session.connect(mac)
                        } label: {
                            HStack(spacing: KnurlSpace.snug) {
                                Image(systemName: "laptopcomputer")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(KnurlPalette.calm)
                                Text(mac.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(KnurlPalette.ink)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(KnurlPalette.inkFaint)
                            }
                            .padding(.horizontal, KnurlSpace.step)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .knurlSurface()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ImmediatePressStyle())
                    }
                }
                .frame(maxWidth: 340)
            }

            PhoneChip(
                title: "Look again",
                symbol: "arrow.clockwise",
                tint: KnurlPalette.calm
            ) {
                session.refresh()
            }
            Spacer()
        }
        .padding(KnurlSpace.hall)
    }

    private var emptyTitle: String {
        if session.lastError != nil { return "Couldn’t reach the Mac desk." }
        if session.macs.isEmpty { return "Looking for the Mac desk…" }
        if session.macs.count > 1 { return "Which Mac?" }
        return "Connecting…"
    }

    private var emptyDetail: String {
        session.lastError
            ?? "Open Knurl on this Mac. Allow Local Network if this stays empty."
    }

    private var faceChips: some View {
        HStack(spacing: KnurlSpace.tight) {
            ForEach(Array(DialMode.allCases.enumerated()), id: \.element.id) { index, mode in
                faceChip(mode, number: index + 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func faceChip(_ mode: DialMode, number: Int) -> some View {
        let selected = session.face == mode.rawValue
        let tint = phoneTint(
            mode: mode,
            progress: session.hello?.progress ?? 0.5,
            muted: chipMuted(mode)
        )
        return Button {
            if selected {
                session.confirm()
            } else {
                session.select(mode.rawValue)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: chipSymbol(mode))
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? .white : tint)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : (selected ? session.faceTick : 0))
                    .symbolEffectsRemoved(reduceMotion)
                Text(mode.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? .white : KnurlPalette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // Each key carries its own level, so the strip says where
                // every face is sitting without being tapped.
                KnurlMeter(
                    progress: selected ? (session.hello?.progress ?? 0.5) : 0,
                    tint: selected ? .white.opacity(0.85) : tint.opacity(0.5),
                    height: 2.5,
                    showsTrack: false
                )
                .padding(.horizontal, 8)
                .opacity(selected ? 1 : 0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background {
                RoundedRectangle(cornerRadius: KnurlRadius.chip + 3, style: .continuous)
                    .fill(selected ? tint : KnurlPalette.control)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KnurlRadius.chip + 3, style: .continuous)
                    .strokeBorder(selected ? .clear : KnurlPalette.hairline, lineWidth: 1)
            }
            .shadow(color: selected ? tint.opacity(0.45) : .clear, radius: 12, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(ImmediatePressStyle())
        .accessibilityLabel(mode.title)
        .accessibilityValue("Key \(number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? mode.confirmTitle : "Switch face")
    }

    private func chipSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume:
            (session.hello?.muted == true && session.face == "volume") ? "speaker.slash.fill" : mode.symbol
        case .mic:
            session.isListening
                ? "waveform"
                : ((session.hello?.muted == true && session.face == "mic") ? "mic.slash.fill" : mode.symbol)
        case .media:
            session.hello?.playing == true ? "pause.fill" : "play.fill"
        case .brightness, .output:
            mode.symbol
        }
    }

    private func chipMuted(_ mode: DialMode) -> Bool {
        session.hello?.muted == true && session.face == mode.rawValue
    }
}

private struct TransportBar: View {
    @Bindable var session: PhoneSession

    private var tint: Color { phoneTint(mode: .media, progress: 0.6, muted: false) }

    var body: some View {
        HStack(spacing: KnurlSpace.tight) {
            icon("shuffle", on: session.hello?.shuffle == true) { session.shuffle() }
                .accessibilityLabel("Shuffle")
            icon("backward.fill", on: false) { session.skip(-1) }
                .accessibilityLabel("Previous")
            Button {
                session.confirm()
            } label: {
                Image(systemName: session.hello?.playing == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 44)
                    .background { Capsule().fill(tint) }
                    .shadow(color: tint.opacity(0.5), radius: 14, y: 3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ImmediatePressStyle())
            .accessibilityLabel(session.hello?.playing == true ? "Pause" : "Play")
            icon("forward.fill", on: false) { session.skip(1) }
                .accessibilityLabel("Next")
            icon(
                session.hello?.repeat == "one" ? "repeat.1" : "repeat",
                on: session.hello?.repeat != "off" && session.hello?.repeat != nil
            ) {
                session.cycleRepeat()
            }
            .accessibilityLabel("Repeat")
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? tint : KnurlPalette.inkSoft)
                .frame(width: 44, height: 44)
                .background { Circle().fill(KnurlPalette.control) }
                .overlay {
                    Circle().strokeBorder(
                        on ? tint.opacity(0.7) : KnurlPalette.hairline,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(ImmediatePressStyle())
        .accessibilityAddTraits(.isButton)
    }
}

private struct ChipScroller: View {
    var items: [(id: String, title: String, selected: Bool)]
    var pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KnurlSpace.tight) {
                ForEach(items, id: \.id) { item in
                    PhoneChip(
                        title: item.title,
                        tint: phoneTint(mode: .media, progress: 0.6, muted: false),
                        selected: item.selected
                    ) {
                        pick(item.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }
}
