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

    /// Language detection via the tiny model (~0.2 s). Whisper detects from
    /// the first 30 s window, so pass at most that much audio.
    private func detectLanguage(_ audio: [Float]) -> String? {
        guard let detectCtx else { return nil }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.detect_language = true
        params.language = nil
        params.n_threads = 4
        let window = Array(audio.prefix(Int(AudioRecorder.targetSampleRate * 30)))
        let status = window.withUnsafeBufferPointer { ptr in
            whisper_full(detectCtx, params, ptr.baseAddress, Int32(ptr.count))
        }
        guard status == 0 else { return nil }
        let langId = whisper_full_lang_id(detectCtx)
        return langId >= 0 ? String(cString: whisper_lang_str(langId)) : nil
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
        let status = withLanguageCString(detected) { langPtr -> Int32 in
            params.language = langPtr // nil falls back to big-model auto-detect
            return audio.withUnsafeBufferPointer { ptr in
                whisper_full(ctx, params, ptr.baseAddress, Int32(ptr.count))
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

    /// Keeps the language C string alive for the duration of whisper_full.
    private func withLanguageCString(_ language: String?, _ body: (UnsafePointer<CChar>?) -> Int32) -> Int32 {
        guard let language else { return body(nil) }
        return language.withCString { body($0) }
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
