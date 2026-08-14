import AVFoundation
import Foundation
import SwiftUI

/// Headless pipeline check: `WisprOwn --transcribe <audio-file>`.
/// Loads the model, transcribes one file, prints the result, exits.
enum TranscribeCLI {
    /// `WisprOwn --devices` — list input devices (mic-picker verification).
    static func listDevices() {
        setvbuf(stdout, nil, _IONBF, 0)
        for device in AudioDevices.inputDevices() {
            print("\(device.id)\t\(device.uid)\t\(device.name)")
        }
        _exit(0)
    }

    /// `WisprOwn --stats` — print Home-screen stats (verification against SQL).
    static func printStats() {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let store = try? HistoryStore() else { _exit(1) }
        let stats = store.stats()
        print("totalWords: \(stats.totalWords)")
        print("wpm: \(stats.wordsPerMinute)")
        print("dayStreak: \(stats.dayStreak)")
        _exit(0)
    }

    /// `WisprOwn --selftest` — asserts the silence gate on synthetic buffers,
    /// so a threshold change can't quietly start eating real dictations.
    /// No model or audio files needed; runs in milliseconds.
    static func selfTest() {
        setvbuf(stdout, nil, _IONBF, 0)
        let n = Int(AudioRecorder.targetSampleRate) * 2
        func tone(_ amplitude: Float) -> [Float] {
            (0..<n).map { amplitude * sin(Float($0) * 0.05) }
        }
        // sin RMS is amplitude/√2, so amplitude 0.003 ≈ 0.002 measured room tone.
        precondition(!Transcriber.hasSpeech([Float](repeating: 0, count: n)), "digital silence")
        precondition(!Transcriber.hasSpeech(tone(0.003)), "room tone")
        precondition(!Transcriber.hasSpeech([]), "empty buffer")
        precondition(Transcriber.hasSpeech(tone(0.031)), "quiet talker")
        precondition(Transcriber.hasSpeech(tone(0.25)), "normal speech")
        // One loud word inside otherwise-silent audio must still count.
        var mostlySilent = [Float](repeating: 0, count: n)
        mostlySilent.replaceSubrange(0..<3_200, with: tone(0.25).prefix(3_200))
        precondition(Transcriber.hasSpeech(mostlySilent), "brief word in silence")
        print("selftest: silence gate ok (floor \(Transcriber.speechFloor))")

        // Pre-roll must keep only the most recent window, or a warm mic would
        // grow an unbounded in-memory recording of everything it ever heard.
        let oneSecond = Int(AudioRecorder.targetSampleRate)
        precondition(
            AudioRecorder.trimmed([Float](repeating: 1, count: oneSecond * 5), seconds: 0.5).count
                == oneSecond / 2, "long buffer trimmed to the window")
        precondition(
            AudioRecorder.trimmed([Float](repeating: 1, count: 100), seconds: 0.5).count == 100,
            "short buffer untouched")
        // Trimming keeps the *end* — the audio nearest the key press.
        var tail = [Float](repeating: 0, count: oneSecond)
        tail.append(contentsOf: [Float](repeating: 0.9, count: 8))
        precondition(
            AudioRecorder.trimmed(tail, seconds: 0.5).suffix(8).allSatisfy { $0 == 0.9 },
            "newest audio survives trimming")
        // Voiced share is what separates "we recorded silence" from "the
        // transcriber gave up" — the two look identical in a duration log.
        precondition(
            AudioRecorder.voicedFraction([Float](repeating: 0, count: oneSecond * 3)) == 0,
            "pure silence reads as no speech")
        var half = [Float](repeating: 0, count: oneSecond)
        half.append(contentsOf: (0..<oneSecond).map { 0.2 * sin(Float($0) * 0.05) })
        let share = AudioRecorder.voicedFraction(half)
        precondition(share > 0.4 && share < 0.6, "half-speech reads near 50%, got \(share)")

        // Staleness is what makes a dead warm mic recover by itself. The engine
        // keeps reporting itself as running, so if this check goes soft the app
        // silently records nothing until it is restarted — the exact bug.
        let now = Date()
        precondition(
            AudioRecorder.warmIsStale(lastBufferAt: nil, now: now),
            "a mic that never delivered anything is stale")
        precondition(
            AudioRecorder.warmIsStale(
                lastBufferAt: now.addingTimeInterval(-AudioRecorder.warmSilenceTimeout - 0.5),
                now: now),
            "a mic silent past the timeout is stale")
        precondition(
            !AudioRecorder.warmIsStale(lastBufferAt: now.addingTimeInterval(-0.1), now: now),
            "a mic delivering 100 ms ago is healthy")
        print("selftest: pre-roll ok")

        // Cleanup response parsing — a wrong shape here would silently cost
        // every cleaned dictation, since failures fall back to the raw text.
        func json(_ string: String) -> Data { Data(string.utf8) }
        precondition(
            LLMCleanup.parseAnthropic(json(#"{"content":[{"type":"text","text":" Send an email to Jenn. "}]}"#))
                == .cleaned("Send an email to Jenn."), "anthropic text block")
        precondition(
            LLMCleanup.parseAnthropic(json(#"{"stop_reason":"refusal","content":[]}"#))
                == .failed("Model declined the request"), "anthropic refusal")
        precondition(
            LLMCleanup.parseAnthropic(json(#"{"content":[{"type":"thinking","thinking":"hm"}]}"#))
                == .failed("Empty response"), "no text block")
        precondition(
            LLMCleanup.parseOpenAI(json(#"{"choices":[{"message":{"content":"Send an email to Jenn."}}]}"#))
                == .cleaned("Send an email to Jenn."), "openai choice")
        precondition(
            LLMCleanup.parseOpenAI(json("not json")) == .failed("Unreadable response"), "malformed body")
        precondition(
            LLMCleanup.apiErrorMessage(json(#"{"error":{"message":"invalid x-api-key"}}"#))
                == "invalid x-api-key", "api error message")
        precondition(
            LLMCleanup.systemPrompt(glossary: ["Bruda"]).contains("Bruda"), "glossary in prompt")

        // Model picker: one parser for both wire formats, non-chat models out.
        precondition(
            LLMCleanup.parseModels(json(#"{"data":[{"id":"claude-opus-5"},{"id":"claude-haiku-4-5"}]}"#))
                == ["claude-haiku-4-5", "claude-opus-5"], "anthropic model list, sorted")
        precondition(
            LLMCleanup.parseModels(json(#"{"data":[{"id":"gpt-5"},{"id":"text-embedding-3-small"},{"id":"dall-e-3"}]}"#))
                == ["gpt-5"], "non-chat models filtered")
        precondition(LLMCleanup.parseModels(json("nope")).isEmpty, "malformed model list")

        // Base URLs saved by early versions held the full endpoint; appending
        // to those produced /v1/messages/messages and 404'd every call.
        precondition(
            LLMCleanup.normalisedBase("https://api.anthropic.com/v1/messages")
                == "https://api.anthropic.com/v1", "stored Anthropic endpoint normalised")
        precondition(
            LLMCleanup.normalisedBase("https://api.openai.com/v1/chat/completions")
                == "https://api.openai.com/v1", "stored OpenAI endpoint normalised")
        precondition(
            LLMCleanup.normalisedBase("https://api.anthropic.com/v1/")
                == "https://api.anthropic.com/v1", "trailing slash trimmed")
        precondition(
            LLMCleanup.normalisedBase("http://localhost:11434/v1")
                == "http://localhost:11434/v1", "already-correct base untouched")

        // Every provider must resolve to its real endpoints, not just the one
        // in use today. Anthropic speaks /messages, the rest OpenAI's shape.
        precondition(
            LLMCleanup.chatEndpoint(for: .anthropic) == "https://api.anthropic.com/v1/messages",
            "anthropic chat endpoint")
        precondition(
            LLMCleanup.chatEndpoint(for: .openAI) == "https://api.openai.com/v1/chat/completions",
            "openai chat endpoint")
        precondition(
            LLMCleanup.chatEndpoint(for: .grok) == "https://api.x.ai/v1/chat/completions",
            "grok chat endpoint")
        precondition(
            LLMCleanup.chatEndpoint(for: .custom) == "http://localhost:11434/v1/chat/completions",
            "custom (Ollama) chat endpoint")
        precondition(
            LLMCleanup.modelsEndpoint(for: .openAI) == "https://api.openai.com/v1/models",
            "openai models endpoint")
        precondition(
            LLMCleanup.modelsEndpoint(for: .grok) == "https://api.x.ai/v1/models",
            "grok models endpoint")
        // A custom server given the full endpoint gets the same repair.
        precondition(
            LLMCleanup.chatEndpoint(for: .custom, base: "https://openrouter.ai/api/v1/chat/completions")
                == "https://openrouter.ai/api/v1/chat/completions", "custom full endpoint normalised")
        print("selftest: provider endpoints ok")
        print("selftest: cleanup parsing ok")

        // Dictionary learning. The stub mirrors what the real macOS checker was
        // measured to do — it accepts any capitalised word, so "Bruda" reads as
        // ordinary and only lowercase jargon comes back unknown.
        let unknown: (String) -> Bool = { ["kubectl", "diebrudie"].contains($0) }
        func learned(_ before: String, _ after: String, known: [String] = []) -> [String] {
            TermLearner.learnedTerms(before: before, after: after, known: known, isUnknown: unknown)
        }
        precondition(
            learned("Send this to hupspot today", "Send this to HubSpot today") == ["HubSpot"],
            "internal capital is a personal term")
        precondition(
            learned("Ask brooder about it", "Ask Bruda about it") == ["Bruda"],
            "proper noun mid-sentence, which the system checker calls ordinary")
        precondition(
            learned("run cube control now", "run diebrudie now") == ["diebrudie"],
            "lowercase jargon absent from the system dictionary")
        precondition(
            learned("Their car is red", "There car is red").isEmpty,
            "capitalised first word is not treated as a name")
        precondition(
            learned("I sent teh email", "I sent the email").isEmpty,
            "ordinary typo fix is not vocabulary")
        precondition(
            learned("Send this to hupspot", "Send this to HubSpot", known: ["HubSpot"]).isEmpty,
            "already in the dictionary")
        precondition(
            learned("Call Bruda", "Call Bruda tomorrow morning").isEmpty,
            "added words are not corrections")
        precondition(
            learned("Meeting with Jenn.", "Meeting with Jenn").isEmpty,
            "punctuation-only edit changes nothing")
        precondition(
            learned("run kube control now", "run kubectl now") == ["kubectl"],
            "two words collapsed into one term")
        precondition(
            TermLearner.learnedTerms(
                before: "a b c d", after: "Ay Bee Cee Dee", known: [], isUnknown: { _ in true }
            ).count == TermLearner.maxPerEdit, "a rewrite can't flood the dictionary")
        print("selftest: dictionary learning ok")

        // Hallucinated speaker labels. Whisper learned them from subtitles and
        // opens transcripts with a name nobody said; dictation has one speaker,
        // so a name-plus-colon at the very start is never real.
        func strip(_ text: String) -> String { Transcriber.stripSpeakerLabel(text) }
        precondition(
            strip("Katerina Sánchez: Over explaining a bit") == "Over explaining a bit",
            "accented two-word label")
        precondition(strip("Kareemah Chau: So.") == "So.", "two-word label")
        precondition(
            strip("Dr. Ada King Lovelace: hello there") == "hello there", "three-word label")
        precondition(strip("Note: buy milk") == "Note: buy milk", "single word is not a name")
        precondition(strip("Warning: this is slow") == "Warning: this is slow", "not a name")
        precondition(strip("Ada Lovelace:") == "Ada Lovelace:", "label with nothing behind it")
        precondition(
            strip("I told Ada Lovelace: hello") == "I told Ada Lovelace: hello",
            "only strips at the very start")
        precondition(strip("So I said yes") == "So I said yes", "no colon, untouched")
        print("selftest: speaker-label stripping ok")
        _exit(0)
    }

    /// `WisprOwn --snapshot <path.png> [dark]` — renders the Insights screen
    /// off-screen against the real history. Layout bugs (collisions, overflow,
    /// clipped labels) don't show up in a build or a colour check; this is how
    /// they get seen without a GUI session.
    @MainActor
    static func snapshot(path: String, dark: Bool) {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let store = try? HistoryStore() else {
            print("error: cannot open history")
            _exit(1)
        }
        // Theme colours resolve through NSAppearance, so the mode has to be set
        // on the app, not via SwiftUI's colorScheme.
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApplication.shared.appearance = appearance
        let wide = CommandLine.arguments.contains("wide")
        if CommandLine.arguments.contains("dictionary") {
            renderDictionary(store: store, path: path, dark: dark)
        }
        let view = InsightsContent(analytics: store.analytics())
            .frame(width: wide ? 1500 : 980, height: 1400, alignment: .top)
            .background(Theme.contentBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        // Theme's dynamic NSColors resolve against the *current drawing*
        // appearance; setting it on NSApp alone leaves the render in light mode.
        var rendered: NSImage?
        appearance.performAsCurrentDrawingAppearance { rendered = renderer.nsImage }
        guard let image = rendered,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("error: render failed")
            _exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("snapshot: \(path) (\(dark ? "dark" : "light"))")
        _exit(0)
    }

    @MainActor
    private static func renderDictionary(store: HistoryStore, path: String, dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApplication.shared.appearance = appearance
        // `demo` fills the table with sample rows — with one real entry there
        // are no dividers or hover states to look at.
        let entries = CommandLine.arguments.contains("demo")
            ? ["Wispr Flow", "kyan-webpresentation", "hubSpot-export", "Gothaer", "DKB", "Isabel"]
                .enumerated().map { HistoryStore.DictionaryEntry(id: Int64($0.offset), phrase: $0.element) }
            : store.dictionaryEntries()
        let view = DictionaryContent(entries: entries)
            .frame(width: 980, height: 900, alignment: .top)
            .background(Theme.contentBackground)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var rendered: NSImage?
        appearance.performAsCurrentDrawingAppearance { rendered = renderer.nsImage }
        guard let image = rendered, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("error: render failed")
            _exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("snapshot: \(path) (dictionary)")
        _exit(0)
    }

    /// `WisprOwn --llm-test` — exercises the stored key against the configured
    /// provider and prints exactly what came back. "Not found" in Settings says
    /// nothing about *why*; this does. The key itself is never printed.
    static func llmTest() {
        setvbuf(stdout, nil, _IONBF, 0)
        // The app's domain, explicitly. Run outside the .app bundle,
        // UserDefaults.standard is a *different* domain, so this quietly tested
        // the built-in defaults instead of the user's real settings — and
        // reported everything fine while the app was failing.
        let defaults = UserDefaults(suiteName: "com.diebrudie.wisprown") ?? .standard
        let provider = defaults.string(forKey: "llmProvider")
            .flatMap(LLMProvider.init(rawValue:)) ?? .anthropic
        let model = defaults.string(forKey: "llmModel.\(provider.rawValue)") ?? provider.defaultModel
        let base = defaults.string(forKey: "llmBaseURL.\(provider.rawValue)") ?? provider.defaultBaseURL
        let key = LLMKeychain.read(provider.rawValue) ?? ""

        print("provider:  \(provider.displayName)")
        print("endpoint:  \(base)")
        let normalised = LLMCleanup.normalisedBase(base)
        if normalised != base { print("           → normalised to \(normalised)") }
        print("model:     \(model)")
        print("key:       \(key.isEmpty ? "MISSING" : "present (\(key.count) chars, ends …\(key.suffix(4)))")")
        print("enabled:   \(defaults.object(forKey: "llmEnabled") as? Bool ?? true)")
        guard !key.isEmpty else { _exit(1) }

        let config = LLMConfig(provider: provider, model: model, baseURL: base,
                               apiKey: key, glossary: [])
        let done = DispatchSemaphore(value: 0)
        Task {
            let models = await LLMCleanup.models(config: config)
            print("models:    \(models.count) returned\(models.isEmpty ? "" : ", e.g. \(models.prefix(4).joined(separator: ", "))")")
            print("in list:   \(models.contains(model) ? "yes" : "NO — this model is not one the key can use")")

            switch await LLMCleanup.clean("um so I wanted to to email John, I mean Jenn about the thing", config: config) {
            case .cleaned(let text): print("cleanup:   OK → \(text)")
            case .failed(let message): print("cleanup:   FAILED → \(message)")
            }
            done.signal()
        }
        done.wait()
        _exit(0)
    }

    /// `WisprOwn --audio-test` — exercises both capture paths and reports how
    /// much audio each actually collected. The bug this exists for was a
    /// missing `isRecording = true` on the cold path: every buffer went to the
    /// pre-roll instead of the take, so dictations came back empty while the
    /// UI showed recording. A build check would never have caught it.
    static func audioTest() {
        setvbuf(stdout, nil, _IONBF, 0)
        let recorder = AudioRecorder()

        func take(_ label: String, seconds: Double) -> Double {
            do { try recorder.start() } catch {
                print("\(label): start failed — \(error.localizedDescription)")
                return -1
            }
            Thread.sleep(forTimeInterval: seconds)
            let samples = recorder.stop(heldFor: seconds)
            let captured = Double(samples.count) / AudioRecorder.targetSampleRate
            let ratio = captured / seconds
            print(String(format: "%@: held %.1fs, captured %.2fs (%.0f%%) %@",
                         label, seconds, captured, ratio * 100,
                         ratio > 0.5 ? "OK" : "FAIL — the take is not being filled"))
            return ratio
        }

        let cold = take("cold  ", seconds: 1.5)

        do {
            try recorder.startContinuous()
            Thread.sleep(forTimeInterval: 0.8) // let the pre-roll fill
        } catch {
            print("warm  : could not hold the mic (\(error.localizedDescription))")
            _exit(cold > 0.5 ? 0 : 1)
        }
        let warm = take("warm  ", seconds: 1.5)
        // Back-to-back, the case that crashed: stop then immediately start again.
        let again = take("repeat", seconds: 1.0)
        recorder.stopContinuous()

        let ok = cold > 0.5 && warm > 0.5 && again > 0.5
        print(ok ? "audio-test: both paths capture" : "audio-test: FAILED")
        _exit(ok ? 0 : 1)
    }

    static func run(path: String) {
        // Unbuffered stdout: we exit via _exit(), which skips stream flushing.
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            let samples = try load16kMono(path: path)
            print("audio: \(String(format: "%.1f", Double(samples.count) / 16_000))s")

            let transcriber = Transcriber()
            guard FileManager.default.fileExists(atPath: ModelManager.modelPath.path) else {
                print("error: model missing at \(ModelManager.modelPath.path) — launch the app once to download it")
                exit(1)
            }
            guard FileManager.default.fileExists(atPath: ModelManager.detectModelPath.path) else {
                print("error: detection model missing at \(ModelManager.detectModelPath.path)")
                _exit(1)
            }
            try transcriber.load(
                modelPath: ModelManager.modelPath.path,
                detectModelPath: ModelManager.detectModelPath.path
            )
            // Mirror the app pipeline: dictionary bias + language constraint.
            if let store = try? HistoryStore() {
                transcriber.glossary = store.dictionaryEntries().map(\.phrase)
                if !transcriber.glossary.isEmpty {
                    print("glossary: \(transcriber.glossary.joined(separator: ", "))")
                }
            }
            if let langs = UserDefaults.standard.stringArray(forKey: "dictationLanguages") {
                transcriber.allowedLanguages = langs.sorted()
            }
            guard let cold = transcriber.transcribe(samples: samples) else {
                print("error: transcription failed")
                _exit(1)
            }
            // Second run shows steady-state latency (first includes Metal warm-up);
            // the app keeps the model resident, so warm is what users feel.
            let warm = transcriber.transcribe(samples: samples)
            print("language: \(cold.language)")
            print("time: \(cold.transcribeMs) ms cold, \(warm?.transcribeMs ?? -1) ms warm")
            print("text: \(cold.text)")
            // _exit skips atexit handlers — ggml's Metal static destructors
            // abort inside exit() (upstream issue), and there is nothing to clean up.
            _exit(0)
        } catch {
            print("error: \(error.localizedDescription)")
            _exit(1)
        }
    }

    /// Reads any AVFoundation-supported audio file as 16 kHz mono Float32.
    static func load16kMono(path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let sourceFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw NSError(domain: "WisprOwn", code: 30, userInfo: [
                NSLocalizedDescriptionKey: "Cannot build converter for \(path)",
            ])
        }

        guard let inBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(file.length)
        ) else { throw NSError(domain: "WisprOwn", code: 31) }
        try file.read(into: inBuffer)

        let ratio = 16_000 / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw NSError(domain: "WisprOwn", code: 32)
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return inBuffer
        }
        if let error { throw error }
        guard let channel = outBuffer.floatChannelData?[0] else {
            throw NSError(domain: "WisprOwn", code: 33)
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
    }
}
