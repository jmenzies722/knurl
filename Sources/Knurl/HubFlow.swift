import KnurlCore
import SwiftUI

struct HubFlow: View {
    @Bindable var state: DialState

    var body: some View {
        HubPageScroll {
            Text("Knurl Flow")
                .font(.largeTitle.weight(.semibold))
            Text("Speak. Words land where you were.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {
                FlowWaveform(
                    levels: state.voice.levels,
                    tint: HubTint.face(.mic, progress: state.controlProgress, muted: state.isMicMuted)
                )
                .frame(maxWidth: .infinity)

                Text(liveLine)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(state.voice.isListening ? .primary : .secondary)

                Text("→ \(state.harnessName)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                HubGlassButton(
                    title: state.voice.isListening ? "Release" : "Hold",
                    symbol: state.voice.isListening ? "waveform" : "mic.fill",
                    tint: HubTint.face(.mic, progress: 0.6, muted: false),
                    selected: state.voice.isListening
                ) {}
                .overlay(
                    ImmediateHold(
                        down: { state.beginTalk(presentHUD: false) },
                        up: { state.endTalk() }
                    )
                )
                HubGlassButton(
                    title: state.voice.isListening ? "Stop" : "Toggle",
                    symbol: "record.circle"
                ) {
                    state.toggleTalk(presentHUD: false)
                }
                if state.voice.isListening {
                    HubGlassButton(title: "Cancel", symbol: "xmark") {
                        state.cancelTalk()
                    }
                }
                if !state.voice.lastTranscript.isEmpty, !state.voice.isListening {
                    HubGlassButton(title: "Resend", symbol: "arrow.uturn.up") {
                        state.resendTalk()
                    }
                }
            }

            if let message = state.voice.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HubDivider()

            HubSection(title: "Destination") {
                HubFact(label: "Words land", value: state.harnessName)
                HubFact(label: "Language", value: state.voice.languageName)
                Text("Hold or toggle. Release pastes into the remembered app. Speech stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HubDivider()

            HubSection(title: "Recent") {
                if state.voice.lastTranscript.isEmpty {
                    HubEmpty(title: "No transcript yet", detail: "The last dictation stays here. Audio is never kept.")
                } else {
                    Text(state.voice.lastTranscript)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            HubDivider()

            HubSection(title: "Developer vocabulary") {
                Text(FlowLexicon.phrases.prefix(12).joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("On-device hints only. No downloaded language model in this pass.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var liveLine: String {
        if state.voice.isListening || !state.voice.preview.isEmpty {
            return state.voice.preview.isEmpty ? "Listening…" : state.voice.preview
        }
        if !state.voice.lastTranscript.isEmpty {
            return state.voice.lastTranscript
        }
        return "Hold, speak, release."
    }
}
