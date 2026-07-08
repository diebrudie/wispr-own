import Cocoa
import Combine
import SwiftUI

enum AppPhase: Equatable {
    case startingUp
    case needsPermissions(mic: Bool, accessibility: Bool) // true = missing
    case downloadingModel(progress: Double)
    case loadingModel
    case idle
    case recording
    case transcribing
    case error(String)

    var menuBarSymbol: String {
        switch self {
        case .startingUp, .loadingModel: return "hourglass"
        case .needsPermissions, .error: return "mic.slash"
        case .downloadingModel: return "arrow.down.circle"
        case .idle: return "mic"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        }
    }

    var statusText: String {
        switch self {
        case .startingUp: return "Starting…"
        case .needsPermissions: return "Permissions needed"
        case .downloadingModel(let p): return "Downloading model… \(Int(p * 100))%"
        case .loadingModel: return "Loading model…"
        case .idle: return "Ready — hold \(HotkeyOption.current.displayName) to dictate"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .error(let message): return "Error: \(message)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .startingUp
    @Published var recentTranscripts: [Transcript] = []
    @Published var searchQuery: String = "" {
        didSet { refreshRecent() }
    }
    @Published var hotkeyOption: HotkeyOption = .current {
        didSet {
            HotkeyOption.current = hotkeyOption
            hotkey.option = hotkeyOption
            dlog("app: hotkey switched to \(hotkeyOption.rawValue)")
            // Re-publish so the menu status line picks up the new key name.
            if case .idle = phase { phase = .idle }
        }
    }

    private let hotkey = HotkeyListener()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let modelManager = ModelManager()
    private var history: HistoryStore?
    private var permissionPoll: Timer?

    private var isError: Bool {
        if case .error = phase { return true }
        return false
    }

    var playSounds: Bool {
        get { UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "playSounds") }
    }

    init() {
        hotkey.onStart = { [weak self] in self?.startRecording() }
        hotkey.onStop = { [weak self] in self?.stopAndTranscribe() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        recorder.onAutoStop = { [weak self] in self?.stopAndTranscribe() }
        modelManager.onProgress = { [weak self] progress in
            Task { @MainActor in self?.phase = .downloadingModel(progress: progress) }
        }
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        do {
            history = try HistoryStore()
            refreshRecent()
        } catch {
            phase = .error(error.localizedDescription)
            return
        }

        // 1. Permissions — both prompts up front, then poll until granted.
        if !Permissions.microphoneGranted {
            _ = await Permissions.requestMicrophone()
        }
        if !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
        }
        await waitForPermissions()

        // 2. Model — download on first launch, then load into memory.
        do {
            if !modelManager.modelReady {
                phase = .downloadingModel(progress: 0)
            }
            try await modelManager.ensureModel()
        } catch {
            phase = .error("Model download failed: \(error.localizedDescription)")
            return
        }
        phase = .loadingModel
        let modelPath = ModelManager.modelPath.path
        let detectPath = ModelManager.detectModelPath.path
        do {
            try await Task.detached(priority: .userInitiated) { [transcriber] in
                try transcriber.load(modelPath: modelPath, detectModelPath: detectPath)
            }.value
        } catch {
            phase = .error(error.localizedDescription)
            return
        }

        // 3. Hotkey — needs Accessibility; granted above.
        guard hotkey.start() else {
            phase = .error("Could not listen for the hotkey. Grant Accessibility, then restart the app.")
            return
        }
        phase = .idle
        dlog("app: ready")
    }

    private func waitForPermissions() async {
        var logged = false
        while !(Permissions.microphoneGranted && Permissions.accessibilityGranted) {
            phase = .needsPermissions(
                mic: !Permissions.microphoneGranted,
                accessibility: !Permissions.accessibilityGranted
            )
            if !logged {
                dlog("app: waiting for permissions (mic=\(Permissions.microphoneGranted), ax=\(Permissions.accessibilityGranted))")
                logged = true
            }
            try? await Task.sleep(for: .seconds(2))
        }
        dlog("app: permissions granted")
    }

    // MARK: - Dictation flow

    private func startRecording() {
        // .error is recoverable — the next dictation attempt clears it.
        guard phase == .idle || isError else { return }
        do {
            try recorder.start()
            phase = .recording
            if playSounds { NSSound(named: "Pop")?.play() }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        recorder.cancel()
        phase = .idle
    }

    private func stopAndTranscribe() {
        guard phase == .recording else { return }
        let samples = recorder.stop()
        // Target app is captured NOW — before transcription — because focus
        // could change during the wait.
        let targetApp = Paster.frontmostAppBundleID
        let audioMs = Int(Double(samples.count) / AudioRecorder.targetSampleRate * 1000)

        guard audioMs > 200 else {
            phase = .idle
            return
        }
        phase = .transcribing

        Task.detached(priority: .userInitiated) { [transcriber, weak self] in
            let output = transcriber.transcribe(samples: samples)
            await self?.finish(output: output, audioMs: audioMs, targetApp: targetApp)
        }
    }

    private func finish(output: Transcriber.Output?, audioMs: Int, targetApp: String?) {
        guard let output else {
            // Stay in .error until the next successful dictation attempt.
            phase = .error("Transcription failed")
            return
        }
        guard !output.text.isEmpty else {
            dlog("app: empty transcript, skipping")
            phase = .idle
            return
        }
        // Zero-loss rule (Spec 05/G6): persist BEFORE attempting to paste.
        history?.insert(
            text: output.text,
            language: output.language,
            audioDurationMs: audioMs,
            transcribeMs: output.transcribeMs,
            targetApp: targetApp
        )
        refreshRecent()
        Paster.paste(output.text)
        phase = .idle
    }

    func refreshRecent() {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        recentTranscripts = q.isEmpty
            ? (history?.recent(limit: 20) ?? [])
            : (history?.search(q) ?? [])
    }

    func deleteTranscript(_ transcript: Transcript) {
        history?.delete(id: transcript.id)
        refreshRecent()
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
