import Foundation
import whisper

/// Spec 03 — wraps whisper.cpp. Model loads once and stays resident;
/// `transcribe` must be called off the main thread.
final class Transcriber {
    struct Output {
        let text: String
        let language: String
        let transcribeMs: Int
    }

    private var ctx: OpaquePointer?
    private var detectCtx: OpaquePointer?

    var isLoaded: Bool { ctx != nil }

    /// Personal terms (Spec 10) fed to Whisper as context on every dictation
    /// so names/jargon get spelled the user's way. Set from the main thread;
    /// read on the transcription thread — a plain copy-on-write array is safe
    /// because AppState replaces the whole value, never mutates in place.
    var glossary: [String] = []

    /// Whisper's prompt window is ~224 tokens; cap well below it.
    private func glossaryPrompt() -> String? {
        guard !glossary.isEmpty else { return nil }
        var terms: [String] = []
        var length = 0
        for term in glossary {
            length += term.count + 2
            if length > 700 { break }
            terms.append(term)
        }
        return "Glossary: " + terms.joined(separator: ", ") + "."
    }

    /// Loads the main model plus the tiny language-detection model.
    /// One encoder pass on the big model costs seconds; detecting on
    /// ggml-base first and fixing the language halves total latency.
    func load(modelPath: String, detectModelPath: String) throws {
        guard ctx == nil else { return }
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        let start = DispatchTime.now()
        ctx = whisper_init_from_file_with_params(modelPath, params)
        guard ctx != nil else {
            throw NSError(domain: "WisprOwn", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load Whisper model at \(modelPath)",
            ])
        }
        detectCtx = whisper_init_from_file_with_params(detectModelPath, params)
        guard detectCtx != nil else {
            throw NSError(domain: "WisprOwn", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load detection model at \(detectModelPath)",
            ])
        }
        dlog("whisper: models loaded in \(elapsedMs(since: start)) ms")
    }

    /// Dictation languages the user enabled in Settings. Exactly one entry
    /// skips detection entirely; otherwise detection is constrained to the set.
    var allowedLanguages: [String] = ["en", "de", "es"]

    /// Language detection via the tiny model (~0.2 s), constrained to
    /// `allowedLanguages` by picking the highest-probability enabled language.
    /// Whisper detects from the first 30 s window, so pass at most that much.
    private func detectLanguage(_ audio: [Float]) -> String? {
        let allowed = allowedLanguages
        if allowed.count == 1 { return allowed[0] }
        guard let detectCtx else { return nil }

        let window = Array(audio.prefix(Int(AudioRecorder.targetSampleRate * 30)))
        let melStatus = window.withUnsafeBufferPointer { ptr in
            whisper_pcm_to_mel(detectCtx, ptr.baseAddress, Int32(ptr.count), 4)
        }
        guard melStatus == 0 else { return nil }

        var probs = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let best = probs.withUnsafeMutableBufferPointer { ptr in
            whisper_lang_auto_detect(detectCtx, 0, 4, ptr.baseAddress)
        }
        guard best >= 0 else { return nil }

        let globalBest = String(cString: whisper_lang_str(best))
        guard !allowed.isEmpty, !allowed.contains(globalBest) else { return globalBest }

        // Detected language isn't enabled — take the likeliest enabled one.
        let constrained = allowed.max { a, b in
            probability(of: a, in: probs) < probability(of: b, in: probs)
        }
        if let constrained {
            dlog("whisper: detected '\(globalBest)' not enabled, constraining to '\(constrained)'")
        }
        return constrained
    }

    private func probability(of code: String, in probs: [Float]) -> Float {
        let id = Int(whisper_lang_id(code))
        return probs.indices.contains(id) ? probs[id] : 0
    }

    /// Returns nil on failure; empty text means silence/no speech.
    func transcribe(samples: [Float]) -> Output? {
        guard let ctx else { return nil }
        // whisper.cpp needs at least ~1s of audio to behave; pad short clips.
        var audio = samples
        let minSamples = Int(AudioRecorder.targetSampleRate * 1.1)
        if audio.count < minSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_timestamps = true
        params.n_threads = Int32(min(8, max(4, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let start = DispatchTime.now()
        let detected = detectLanguage(audio) // decision #4: auto-detect EN/DE/ES
        let status = withOptionalCString(detected) { langPtr -> Int32 in
            withOptionalCString(glossaryPrompt()) { promptPtr -> Int32 in
                params.language = langPtr // nil falls back to big-model auto-detect
                params.initial_prompt = promptPtr
                return audio.withUnsafeBufferPointer { ptr in
                    whisper_full(ctx, params, ptr.baseAddress, Int32(ptr.count))
                }
            }
        }
        guard status == 0 else {
            dlog("whisper: whisper_full failed (\(status))")
            return nil
        }
        if ProcessInfo.processInfo.environment["WISPROWN_TIMINGS"] != nil {
            whisper_print_timings(ctx)
        }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            text += String(cString: whisper_full_get_segment_text(ctx, i))
        }
        text = Self.cleaned(text)

        let langId = whisper_full_lang_id(ctx)
        let language = detected ?? (langId >= 0 ? String(cString: whisper_lang_str(langId)) : "unknown")
        let ms = elapsedMs(since: start)
        dlog("whisper: \(ms) ms, lang=\(language), \(text.count) chars")
        return Output(text: text, language: language, transcribeMs: ms)
    }

    /// Keeps an optional C string alive for the duration of whisper_full.
    private func withOptionalCString(_ string: String?, _ body: (UnsafePointer<CChar>?) -> Int32) -> Int32 {
        guard let string else { return body(nil) }
        return string.withCString { body($0) }
    }

    /// Strips whitespace and non-speech markers like "[BLANK_AUDIO]" or "(wind blowing)".
    static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = try! NSRegularExpression(pattern: #"[\[\(][^\]\)]*[\]\)]"#)
        let range = NSRange(text.startIndex..., in: text)
        text = markers.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func elapsedMs(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    deinit {
        if let ctx { whisper_free(ctx) }
        if let detectCtx { whisper_free(detectCtx) }
    }
}
