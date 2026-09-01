import AppKit
@preconcurrency import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class Voice {
    var isListening = false
    var preview = ""
    var message: String?

    var isActive: Bool { wantsListen || isListening }

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
        generation += 1
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
        preview = ""
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
        node.installTap(onBus: 0, bufferSize: 1024, format: source) { buffer, _ in
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

    private func askMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func paste(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        editor?.activate()
        postPaste()
        message = "Copied — ⌘V if it didn’t land"
    }

    private func postPaste() {
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
        return "Couldn’t start talk."
    }
}

private enum VoiceError: Error {
    case noFormat
    case unavailable
}
