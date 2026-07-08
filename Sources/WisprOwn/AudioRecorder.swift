import AVFoundation

/// Spec 02 — records the default input device into an in-memory
/// 16 kHz mono Float32 buffer (whisper.cpp's expected input).
final class AudioRecorder {
    static let targetSampleRate: Double = 16_000
    static let maxSeconds: Double = 300

    /// Fired from the main queue when the 5-minute stuck-key cap is hit.
    var onAutoStop: () -> Void = {}

    /// Live loudness (0…~1 RMS) per captured chunk, ~12×/s on the main
    /// queue — drives the WisprOwn bar's waveform.
    var onLevel: (Float) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private let bufferQueue = DispatchQueue(label: "com.diebrudie.wisprown.audio")
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var capFired = false
    private(set) var isRecording = false

    func start() throws {
        guard !isRecording else { return }
        bufferQueue.sync {
            samples.removeAll(keepingCapacity: true)
            capFired = false
        }

        let input = engine.inputNode
        applyPreferredDevice(to: input)
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "WisprOwn", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No audio input device available",
            ])
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "WisprOwn", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Cannot convert \(inputFormat.sampleRate) Hz input to 16 kHz",
            ])
        }
        self.converter = converter

        let ratio = Self.targetSampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, targetFormat: targetFormat, ratio: ratio)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
        dlog("audio: recording started (\(Int(inputFormat.sampleRate)) Hz input)")
    }

    /// Stops and returns the captured 16 kHz mono samples.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        converter = nil
        let captured = bufferQueue.sync { samples }
        dlog("audio: stopped, \(String(format: "%.1f", Double(captured.count) / Self.targetSampleRate))s captured")
        return captured
    }

    func cancel() {
        _ = stop()
        bufferQueue.sync { samples.removeAll() }
        dlog("audio: canceled, buffer discarded")
    }

    /// Points the engine's input AUHAL at the user-chosen microphone.
    /// No stored UID (or a vanished device) means system default.
    private func applyPreferredDevice(to input: AVAudioInputNode) {
        guard let uid = UserDefaults.standard.string(forKey: AudioDevices.defaultsKey),
              !uid.isEmpty else { return }
        guard let device = AudioDevices.device(withUID: uid) else {
            dlog("audio: preferred mic '\(uid)' not connected, using system default")
            return
        }
        guard let unit = input.audioUnit else { return }
        var deviceId = device.id
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
            0, &deviceId, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status == noErr {
            dlog("audio: using mic '\(device.name)'")
        } else {
            dlog("audio: failed to select mic '\(device.name)' (\(status)), using default")
        }
    }

    private func append(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat, ratio: Double) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            dlog("audio: convert error \(error.localizedDescription)")
            return
        }
        guard out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        let rms = sqrt(chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, chunk.count)))
        DispatchQueue.main.async { [weak self] in self?.onLevel(rms) }
        bufferQueue.async { [weak self] in
            guard let self else { return }
            self.samples.append(contentsOf: chunk)
            if !self.capFired,
               Double(self.samples.count) / Self.targetSampleRate >= Self.maxSeconds {
                self.capFired = true
                dlog("audio: 5-minute cap reached, auto-stopping")
                DispatchQueue.main.async { self.onAutoStop() }
            }
        }
    }
}
