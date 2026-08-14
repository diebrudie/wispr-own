import AppKit
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

    /// How much audio from *before* the key press is kept. Measured on this
    /// machine, `AVAudioEngine.start()` costs ~220 ms — long enough to swallow
    /// the first syllable or two, since people start talking as they press.
    /// Half a second covers that with room to spare.
    static let preRollSeconds: Double = 0.5

    /// Same floor the transcriber uses to decide a clip is silent.
    static let speechFloor: Float = Transcriber.speechFloor

    /// How long a warm mic may go without delivering a single buffer before it
    /// is treated as dead. A healthy tap hands over 4096 frames at a time —
    /// roughly twelve buffers a second — so a whole second of nothing is not a
    /// slow moment, it is an engine that has stopped feeding us.
    static let warmSilenceTimeout: TimeInterval = 1.0

    private let engine = AVAudioEngine()
    private let bufferQueue = DispatchQueue(label: "com.diebrudie.wisprown.audio")
    private var samples: [Float] = []
    private var preRoll: [Float] = []
    private var converter: AVAudioConverter?
    private var capFired = false
    private(set) var isRecording = false
    /// True while the engine is held open between dictations.
    private(set) var isWarm = false
    private var interruptionObservers: [NSObjectProtocol] = []
    /// When the tap last handed over real audio. Guarded by `bufferQueue`.
    private var lastBufferAt: Date?

    /// Keeps the engine running so a dictation starts instantly, at the cost of
    /// holding the microphone open — macOS shows its recording indicator the
    /// whole time the app runs. Audio still only lives in memory, and anything
    /// older than `preRollSeconds` is continuously discarded.
    /// The current input, when it is one we must never hold open.
    ///
    /// Holding a Bluetooth mic open pins the headset profile for as long as the
    /// app runs, and the profile flipping mid-dictation is what silently
    /// truncated takes — full-length audio that went quiet after a second or
    /// two. Those inputs use the cold path, where the switch happens before
    /// recording rather than during it.
    private func bluetoothInput() -> AudioInputDevice? {
        guard let device = AudioDevices.currentInputDevice(),
              AudioDevices.isBluetooth(device) else { return nil }
        return device
    }

    func startContinuous() throws {
        guard !isWarm, !isRecording else { return }
        if let device = bluetoothInput() {
            dlog("audio: \(device.name) is Bluetooth — not holding it open, using cold starts")
            return
        }
        try beginCapture()
        isWarm = true
        observeInterruptions()
        dlog("audio: mic held warm, \(Int(Self.preRollSeconds * 1000)) ms pre-roll")
    }

    func stopContinuous() {
        guard isWarm, !isRecording else { return }
        endCapture()
        isWarm = false
        stopObserving()
        bufferQueue.sync { preRoll.removeAll() }
        dlog("audio: mic released")
    }

    /// A held engine does not survive everything: sleeping the Mac, changing
    /// output device, unplugging headphones and swapping the default input all
    /// stop it. Nothing tells the app, so without this the mic stayed "warm"
    /// while capturing nothing and every dictation came back empty until the
    /// app was restarted.
    private func observeInterruptions() {
        guard interruptionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        interruptionObservers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.recoverWarmCapture("audio configuration changed")
        })

        let workspace = NSWorkspace.shared.notificationCenter
        interruptionObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isWarm, !self.isRecording else { return }
            // Release it deliberately rather than letting sleep tear it down —
            // holding a dead engine across sleep is what broke it.
            self.endCapture()
            dlog("audio: mic released for sleep")
        })
        interruptionObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.recoverWarmCapture("woke from sleep")
        })
    }

    private func stopObserving() {
        for observer in interruptionObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        interruptionObservers.removeAll()
    }

    /// Rebuilds the capture after an interruption.
    ///
    /// This deliberately runs *during* a dictation too. Skipping while
    /// recording seemed safe and was the opposite: a Bluetooth device changing
    /// profile — which is exactly what happens when the mic opens on AirPods —
    /// stops the engine mid-take, and ignoring it meant the rest of the
    /// sentence was never captured. The take survives because `samples` lives
    /// on the buffer queue and is untouched here; only the engine is rebuilt,
    /// so audio resumes appending to the same take.
    private func recoverWarmCapture(_ reason: String) {
        guard isWarm || isRecording else { return }
        let midTake = isRecording
        // The Bluetooth rule has to be re-checked on every rebuild, not only at
        // startup. Connecting AirPods to a running app arrives here as a
        // configuration change, and rebuilding blindly put the warm mic back
        // onto the profile-pinning device the rule exists to keep it off —
        // which is how a session that started on the built-in mic ended up
        // silently capturing nothing hours later.
        if !midTake, let device = bluetoothInput() {
            dlog("audio: \(device.name) is Bluetooth — releasing the warm mic, using cold starts")
            stopContinuous()
            return
        }
        endCapture()
        do {
            try beginCapture()
            dlog("audio: capture rebuilt after \(reason)\(midTake ? " — mid-dictation, take preserved" : "")")
        } catch {
            if !midTake { isWarm = false }
            dlog("audio: could not rebuild after \(reason) (\(error.localizedDescription))")
        }
    }

    /// Share of 100 ms frames loud enough to be speech. A healthy dictation
    /// runs well above this; near-zero means the microphone was delivering
    /// silence even though buffers kept arriving.
    static func voicedFraction(_ samples: [Float]) -> Double {
        let frame = Int(targetSampleRate / 10)
        guard samples.count >= frame else { return 0 }
        var voiced = 0, total = 0
        for start in stride(from: 0, to: samples.count - frame, by: frame) {
            let chunk = samples[start..<start + frame]
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            total += 1
            if rms >= speechFloor { voiced += 1 }
        }
        return total == 0 ? 0 : Double(voiced) / Double(total)
    }

    /// Whether a warm mic has gone too long without delivering audio. Never
    /// having delivered any counts as stale — that is the state a rebuilt-but-
    /// dead engine sits in. Uses wall clock deliberately: the monotonic clock
    /// stops while the Mac sleeps, and sleeping is exactly when this happens.
    static func warmIsStale(lastBufferAt: Date?, now: Date) -> Bool {
        guard let lastBufferAt else { return true }
        return now.timeIntervalSince(lastBufferAt) > warmSilenceTimeout
    }

    /// Drops everything older than `preRollSeconds` from the rolling buffer.
    static func trimmed(_ buffer: [Float], seconds: Double = preRollSeconds) -> [Float] {
        let limit = Int(targetSampleRate * seconds)
        guard buffer.count > limit else { return buffer }
        return Array(buffer.suffix(limit))
    }

    func start() throws {
        guard !isRecording else { return }
        let began = DispatchTime.now()

        // Never trust `isRunning`. It reports the engine's own opinion, and a
        // warm mic that has quietly stopped feeding us still says yes: after a
        // long idle, a sleep, or a Bluetooth profile flip, three dictations in
        // a row came back 0.0s while the engine claimed to be running. Buffers
        // actually arriving is the only honest signal, so that is what decides.
        if isWarm {
            let silence = bufferQueue.sync { lastBufferAt }
            if !engine.isRunning || Self.warmIsStale(lastBufferAt: silence, now: Date()) {
                dlog("audio: warm mic was not delivering audio, rebuilding it")
                recoverWarmCapture("it went silent")
            }
        }

        if isWarm, engine.isRunning {
            // The mic is already live, so the audio from just before the key
            // press is already captured — seed the take with it.
            let seeded = bufferQueue.sync { () -> Int in
                samples = preRoll
                preRoll.removeAll(keepingCapacity: true)
                capFired = false
                return samples.count
            }
            let ms = Double(seeded) / Self.targetSampleRate * 1000
            dlog("audio: recording started instantly (\(String(format: "%.0f", ms)) ms of pre-roll)")
            isRecording = true // set last, and once — see below
            return
        }

        bufferQueue.sync {
            samples.removeAll(keepingCapacity: true)
            capFired = false
        }
        try beginCapture()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - began.uptimeNanoseconds) / 1_000_000
        dlog("audio: recording started in \(String(format: "%.0f", ms)) ms — first words may be clipped")
        // This assignment went missing when the warm path was added, and the
        // damage was silent and total: the tap routed every buffer into the
        // pre-roll instead of the take, `stop()` returned early at its
        // `isRecording` guard so the engine was never torn down, and the next
        // press installed a second tap on an occupied bus — which throws.
        // One missing line produced both "nothing was transcribed" and the crash.
        isRecording = true
    }

    private func beginCapture() throws {
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
        // AVAudioEngine allows one tap per bus and throws — fatally — on a
        // second. Removing first makes this idempotent, so a state slip can
        // never take the app down with it again.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, targetFormat: targetFormat, ratio: ratio)
        }
        engine.prepare()
        try engine.start()
        // A freshly started engine has not delivered anything yet and would
        // otherwise read as stale on the very next press.
        bufferQueue.sync { lastBufferAt = Date() }
        dlog("audio: capture running (\(Int(inputFormat.sampleRate)) Hz input)")
    }

    private func endCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }

    /// Stops and returns the captured 16 kHz mono samples. When the mic is held
    /// warm the engine keeps running — only this take ends.
    func stop(heldFor seconds: Double? = nil) -> [Float] {
        guard isRecording else {
            // Nothing was being recorded, yet a cold engine is running: state
            // has slipped somewhere. Release it rather than leaving the mic on.
            if !isWarm, engine.isRunning {
                dlog("audio: engine was running without a take — releasing")
                endCapture()
            }
            return []
        }
        isRecording = false
        if !isWarm { endCapture() }
        let captured = bufferQueue.sync { samples }
        // A take much shorter than the key hold means the engine dropped out
        // mid-dictation. Silent truncation is what made this so hard to see.
        if let seconds, seconds > 1 {
            let ratio = Double(captured.count) / Self.targetSampleRate / seconds
            if ratio < 0.7 {
                dlog("audio: WARNING captured only \(Int(ratio * 100))% of the \(String(format: "%.1f", seconds))s you held — the input dropped out")
            }
        }
        // Full-length but silent audio looks identical to a healthy take in the
        // logs, and transcribes to almost nothing. Reporting the voiced share
        // separates "we recorded silence" from "the transcriber gave up".
        if captured.count > Int(Self.targetSampleRate) {
            let voiced = Self.voicedFraction(captured)
            if voiced < 0.25 {
                dlog("audio: WARNING only \(Int(voiced * 100))% of the take had speech in it — the input went quiet")
            }
        }
        dlog("audio: stopped, \(String(format: "%.1f", Double(captured.count) / Self.targetSampleRate))s captured")
        return captured
    }

    func cancel() {
        _ = stop()
        bufferQueue.sync { samples.removeAll(); preRoll.removeAll() }
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
            // Proof of life, recorded only once real converted audio exists —
            // this is what `start()` trusts instead of the engine's own flag.
            self.lastBufferAt = Date()
            guard self.isRecording else {
                // Not recording but the mic is warm: keep only the most recent
                // slice, so nothing older than the pre-roll window is retained.
                self.preRoll.append(contentsOf: chunk)
                self.preRoll = Self.trimmed(self.preRoll)
                return
            }
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
