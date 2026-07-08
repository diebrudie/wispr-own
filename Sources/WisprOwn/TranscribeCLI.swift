import AVFoundation
import Foundation

/// Headless pipeline check: `WisprOwn --transcribe <audio-file>`.
/// Loads the model, transcribes one file, prints the result, exits.
enum TranscribeCLI {
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
