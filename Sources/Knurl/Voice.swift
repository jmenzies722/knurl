import AppKit
import ApplicationServices
@preconcurrency import AVFoundation
import KnurlCore
import Observation
import Speech

@MainActor
@Observable
final class Voice {
    var isListening = false
    var preview = ""
    var lastTranscript = ""
    var message: String?
    var levels: [Float] = []
    var languageName = Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "System"

    var isActive: Bool { wantsListen || isListening }
    /// Set the moment Cancel / Escape is hit, before any await, so Release
    /// cannot finalize and paste a take that was already discarded.
    private(set) var discarded = false
    /// Desk lands the words in the remembered app. Voice only transcribes.
    var deliver: ((String) async -> Void)?

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finals = ""
    private var editor: NSRunningApplication?
    private var wantsListen = false
    private var generation = 0
    private var stopping = false

    func start(editor: NSRunningApplication?) async {
        if wantsListen { return }
        discarded = false
        wantsListen = true
        let token = generation
        message = nil
        preview = ""
        finals = ""
        self.editor = editor
        guard await askMicrophone() else {
            if token == generation {
                wantsListen = false
                message = "Allow the microphone in Settings."
            }
            return
        }
        guard await askSpeech() else {
            if token == generation {
                wantsListen = false
                message = "Allow Speech in Settings."
            }
            return
        }
        guard wantsListen, token == generation else { return }
        do {
            let session = try await openSession()
            guard wantsListen, token == generation else {
                await session.abandon()
                return
            }
            engine = session.engine
            analyzer = session.analyzer
            transcriber = session.transcriber
            input = session.input
            resultsTask = session.results
            isListening = true
        } catch {
            guard token == generation else { return }
            wantsListen = false
            isListening = false
            message = human(error)
        }
    }

    func stop() async {
        if discarded {
            await cancel()
            return
        }
        generation += 1
        let token = generation
        wantsListen = false
        guard isListening else { return }
        guard !stopping else { return }
        stopping = true
        defer {
            stopping = false
            isListening = false
            engine = nil
            analyzer = nil
            transcriber = nil
            input = nil
            resultsTask = nil
        }
        input?.finish()
        if let analyzer {
            await limited(.milliseconds(1200)) {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            await analyzer.cancelAndFinishNow()
        }
        teardown(engine)
        engine = nil
        if let resultsTask {
            await limited(.milliseconds(400)) {
                _ = await resultsTask.value
            }
            resultsTask.cancel()
        }
        var text = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = finals.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        finals = ""
        guard !text.isEmpty else {
            preview = lastTranscript
            return
        }
        guard generation == token, !discarded else {
            preview = lastTranscript
            return
        }
        lastTranscript = text
        preview = text
        levels = []
        paste(text)
    }

    /// Synchronous. Escape and Cancel must flip this before `endTalk` /
    /// `stop` can run, or the hold-up pastes a discarded take.
    func beginCancel() {
        guard !discarded else { return }
        generation += 1
        discarded = true
        wantsListen = false
        message = "Discarded"
    }

    func cancel() async {
        beginCancel()
        guard isListening else {
            preview = lastTranscript
            return
        }
        input?.finish()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        teardown(engine)
        resultsTask?.cancel()
        engine = nil
        analyzer = nil
        transcriber = nil
        input = nil
        resultsTask = nil
        isListening = false
        stopping = false
        preview = lastTranscript
        levels = []
        message = "Discarded"
    }

    func resend() {
        let text = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        paste(text)
    }

    private struct Session {
        let engine: AVAudioEngine
        let analyzer: SpeechAnalyzer
        let transcriber: DictationTranscriber
        let input: AsyncStream<AnalyzerInput>.Continuation
        let results: Task<Void, Never>

        func abandon() async {
            input.finish()
            await analyzer.cancelAndFinishNow()
            results.cancel()
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func openSession() async throws -> Session {
        let locales = await DictationTranscriber.supportedLocales
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current)
            ?? locales.first
        else {
            throw VoiceError.unavailable
        }
        languageName = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            message = "Downloading speech…"
            try await request.downloadAndInstall()
            message = nil
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.noFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings = [.general: FlowLexicon.phrases]
        try? await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        let engine = try makeEngine(into: continuation, format: format)
        let results = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let chunk = String(result.text.characters)
                    if result.isFinal {
                        self.finals += chunk
                        if !self.finals.hasSuffix(" ") { self.finals += " " }
                        self.preview = self.finals
                    } else {
                        self.preview = self.finals + chunk
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.message = self.human(error)
                }
            }
        }
        return Session(
            engine: engine,
            analyzer: analyzer,
            transcriber: transcriber,
            input: continuation,
            results: results
        )
    }

    private func makeEngine(into continuation: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        let same =
            source.sampleRate == format.sampleRate
            && source.channelCount == format.channelCount
            && source.commonFormat == format.commonFormat
        let converter: AVAudioConverter?
        if same {
            converter = nil
        } else {
            guard let built = AVAudioConverter(from: source, to: format) else {
                throw VoiceError.noFormat
            }
            converter = built
        }
        // installTap's block is not @Sendable in AVFAudio, so without an explicit
        // @Sendable here the closure inherits this type's @MainActor isolation
        // and Swift 6 emits a runtime isolation check at its entry. The block
        // runs on the real-time audio thread, that check fails, and the process
        // takes an EXC_BREAKPOINT. Marking it @Sendable removes the check; the
        // level handoff below is what actually gets us back to the main actor.
        let levelSink: @Sendable (Float) -> Void = { [weak self] rms in
            Task { @MainActor in
                self?.pushLevel(rms)
            }
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: source) { @Sendable buffer, _ in
            levelSink(Self.rms(buffer))
            if let converter {
                let ratio = format.sampleRate / source.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
                guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else { return }
                var error: NSError?
                var eaten = false
                converter.convert(to: out, error: &error) { _, status in
                    if eaten {
                        status.pointee = .endOfStream
                        return nil
                    }
                    eaten = true
                    status.pointee = .haveData
                    return buffer
                }
                if out.frameLength > 0 {
                    continuation.yield(AnalyzerInput(buffer: out))
                }
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }
        engine.prepare()
        try engine.start()
        return engine
    }

    private func teardown(_ engine: AVAudioEngine?) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
    }

    /// `nonisolated` on purpose, and this is load-bearing.
    ///
    /// `Voice` is `@MainActor`, so without it the completion closure inherits
    /// main-actor isolation — and macOS calls these back on its own TCC XPC
    /// reply queue, never the main thread. Swift then inserts an executor
    /// check that fails, which is not a nice error: it is
    /// `_dispatch_assert_queue_fail`, an immediate SIGABRT with no message,
    /// no stderr and no crash report. The app simply vanished the moment you
    /// held the mic key.
    ///
    /// The closure touches no actor state — it resumes with a `Bool` — so
    /// running it off the actor is both correct and necessary. The `await`
    /// hops the caller back to the main actor afterwards.
    nonisolated private func askMicrophone() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Same reason as `askMicrophone`: `SFSpeechRecognizer` replies on a TCC
    /// queue, and a main-actor-isolated closure there is an instant abort.
    nonisolated private func askSpeech() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func paste(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        Task { @MainActor in
            if let deliver {
                await deliver(text)
            } else {
                self.editor?.activate()
                try? await Task.sleep(for: .milliseconds(90))
                self.postPaste()
                self.message = "Copied — ⌘V if it didn’t land"
            }
        }
    }

    /// Whether macOS will actually deliver a synthetic ⌘V to another app.
    ///
    /// Posting to `.cghidEventTap` is Accessibility-gated. Without the
    /// permission the event is dropped *silently* — the words are on the
    /// clipboard, nothing appears in the editor, and Flow looks broken while
    /// reporting success. That is the single worst failure this feature can
    /// have, so it is checked rather than assumed.
    static var canPaste: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility, showing the system prompt once.
    @discardableResult
    static func requestPastePermission() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func postPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func limited(_ duration: Duration, _ work: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await work()
            }
            group.addTask {
                try? await Task.sleep(for: duration)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func human(_ error: Error) -> String {
        if let voice = error as? VoiceError {
            switch voice {
            case .noFormat, .unavailable:
                return "Speech isn’t available on this Mac."
            }
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("not authorized") || text.contains("permission") {
            return "Allow Speech & Microphone in Settings."
        }
        return "Couldn’t start Flow."
    }

    private func pushLevel(_ rms: Float) {
        var next = levels
        next.append(min(1, rms * 8))
        if next.count > 24 { next.removeFirst(next.count - 24) }
        levels = next
    }

    private nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0 ..< count {
            let sample = channel[index]
            sum += sample * sample
        }
        return sqrt(sum / Float(count))
    }
}

private enum VoiceError: Error {
    case noFormat
    case unavailable
}
