import AVFoundation
import Foundation

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
        print("selftest: cleanup parsing ok")
        _exit(0)
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
