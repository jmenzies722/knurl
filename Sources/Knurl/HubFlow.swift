import KnurlCore
import SwiftUI

struct HubFlow: View {
    @Bindable var state: DialState
    @Namespace private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HubPageScroll {
            HubHallHeader(title: "Knurl Flow", whisper: "Talk it in. Keep building.") {
                Text("→ \(state.harnessName)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

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
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)

            GlassEffectContainer(spacing: 10) {
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
                    .glassEffectID("flow-hold", in: flow)

                    HubGlassButton(
                        title: state.voice.isListening ? "Stop" : "Toggle",
                        symbol: "record.circle"
                    ) {
                        state.toggleTalk(presentHUD: false)
                    }
                    .glassEffectID("flow-toggle", in: flow)

                    if state.voice.isListening {
                        HubGlassButton(title: "Cancel", symbol: "xmark") {
                            state.cancelTalk()
                        }
                        .glassEffectID("flow-cancel", in: flow)
                    }
                    if !state.voice.lastTranscript.isEmpty, !state.voice.isListening {
                        HubGlassButton(title: "Resend", symbol: "arrow.uturn.up") {
                            state.resendTalk()
                        }
                        .glassEffectID("flow-resend", in: flow)
                    }
                }
            }
            .animation(motion, value: state.voice.isListening)

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

    private var motion: Animation? {
        HubMotion.lively(reduceMotion: reduceMotion, allowed: state.desk.allowsDecorativeMotion)
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
