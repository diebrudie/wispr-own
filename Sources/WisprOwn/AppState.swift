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
    @Published var stats = HistoryStore.Stats()
    @Published var analytics = HistoryStore.Analytics()
    @Published var dictionary: [HistoryStore.DictionaryEntry] = []
    @Published var searchQuery: String = "" {
        didSet { refreshRecent() }
    }
    @Published var hotkeyOption: HotkeyOption = .current {
        didSet {
            HotkeyOption.current = hotkeyOption
            hotkey.option = hotkeyOption
            dlog("app: hotkey switched to \(hotkeyOption.displayName) (code \(hotkeyOption.keyCode))")
            // Re-publish so the menu status line picks up the new key name.
            if case .idle = phase { phase = .idle }
        }
    }
    @Published var dictationLanguages: Set<String> {
        didSet {
            // Never allow an empty set — that would break detection.
            if dictationLanguages.isEmpty { dictationLanguages = ["en"] }
            UserDefaults.standard.set(Array(dictationLanguages).sorted(), forKey: "dictationLanguages")
            transcriber.allowedLanguages = Array(dictationLanguages).sorted()
        }
    }
    @Published var micUID: String {
        didSet { UserDefaults.standard.set(micUID, forKey: AudioDevices.defaultsKey) }
    }
    /// Rolling mic-loudness window (0…1) driving the WisprOwn bar waveform.
    @Published var levelHistory: [Float] = Array(repeating: 0, count: 26)
    @Published var showFlowBar: Bool {
        didSet { UserDefaults.standard.set(showFlowBar, forKey: "showFlowBar") }
    }
    @Published var appearance: AppearanceOption {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }
    @Published var firstName: String {
        didSet { UserDefaults.standard.set(firstName, forKey: "firstName") }
    }
    @Published var lastName: String {
        didSet { UserDefaults.standard.set(lastName, forKey: "lastName") }
    }

    // MARK: - Optional LLM cleanup (Spec 12 §G)

    @Published var llmProvider: LLMProvider {
        didSet {
            UserDefaults.standard.set(llmProvider.rawValue, forKey: "llmProvider")
            llmError = nil // a settings change invalidates the last failure
            // Each provider keeps its own model, endpoint, and key.
            llmModel = UserDefaults.standard.string(forKey: modelKey) ?? llmProvider.defaultModel
            llmBaseURL = LLMCleanup.normalisedBase(
                UserDefaults.standard.string(forKey: baseURLKey) ?? llmProvider.defaultBaseURL)
            llmAPIKey = LLMKeychain.read(llmProvider.rawValue) ?? ""
            llmModels = llmProvider.fallbackModels
            refreshLLMModels()
        }
    }
    @Published var llmModel: String {
        didSet {
            UserDefaults.standard.set(llmModel, forKey: modelKey)
            llmError = nil // a settings change invalidates the last failure
        }
    }
    /// Only user-visible for `.custom` — every named provider has one URL.
    @Published var llmBaseURL: String {
        didSet {
            UserDefaults.standard.set(llmBaseURL, forKey: baseURLKey)
            llmError = nil // a settings change invalidates the last failure
        }
    }
    /// Mirrors the Keychain entry so SwiftUI can bind to it. The cleanup pass
    /// runs exactly when this is non-empty — clearing the field deletes the key.
    @Published var llmAPIKey: String {
        didSet {
            LLMKeychain.save(llmAPIKey, account: llmProvider.rawValue)
            llmError = nil // a new key invalidates the last failure
            refreshLLMModels()
        }
    }
    /// Off switch that keeps the key. Storing the key and using it are separate
    /// decisions — this is how cleanup gets turned off for a few dictations
    /// without pasting the key back in afterwards.
    @Published var llmEnabled: Bool {
        didSet {
            UserDefaults.standard.set(llmEnabled, forKey: "llmEnabled")
            llmError = nil
        }
    }
    /// Fetched from the provider so the picker shows their names, not mine.
    @Published var llmModels: [String] = []
    /// Last failure, shown in Settings. A silent fallback to the raw transcript
    /// would otherwise look like the feature just doesn't work.
    @Published var llmError: String?

    /// Reloads the model picker. Cheap and idempotent — safe to call on every
    /// key edit and whenever Settings opens.
    func refreshLLMModels() {
        let key = llmAPIKey.trimmingCharacters(in: .whitespaces)
        let config = key.isEmpty ? nil : LLMConfig(
            provider: llmProvider, model: llmModel, baseURL: llmBaseURL,
            apiKey: key, glossary: []
        )
        guard let config else {
            llmModels = llmProvider.fallbackModels
            return
        }
        Task { [weak self] in
            let ids = await LLMCleanup.models(config: config)
            guard let self,
                  self.llmAPIKey.trimmingCharacters(in: .whitespaces) == config.apiKey
            else { return }
            self.llmModels = ids
            // A model saved earlier may not exist any more — don't leave the
            // picker pointing at something the provider would reject.
            if !ids.isEmpty, !ids.contains(self.llmModel) {
                self.llmModel = ids.contains(self.llmProvider.defaultModel)
                    ? self.llmProvider.defaultModel : ids[0]
            }
        }
    }

    private var modelKey: String { "llmModel.\(llmProvider.rawValue)" }
    private var baseURLKey: String { "llmBaseURL.\(llmProvider.rawValue)" }

    var llmConfig: LLMConfig? {
        let key = llmAPIKey.trimmingCharacters(in: .whitespaces)
        guard llmEnabled, !key.isEmpty else { return nil }
        return LLMConfig(
            provider: llmProvider,
            model: llmModel,
            baseURL: llmBaseURL,
            apiKey: key,
            glossary: dictionary.map(\.phrase)
        )
    }

    /// Name used in the Home greeting: Settings first name, falling back
    /// to the macOS account's first name.
    var greetingName: String {
        let custom = firstName.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty { return custom }
        return NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
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
        let stored = UserDefaults.standard.stringArray(forKey: "dictationLanguages") ?? ["en", "de", "es"]
        dictationLanguages = Set(stored)
        micUID = UserDefaults.standard.string(forKey: AudioDevices.defaultsKey) ?? ""
        transcriber.allowedLanguages = stored.sorted()
        appearance = UserDefaults.standard.string(forKey: "appearance")
            .flatMap(AppearanceOption.init(rawValue:)) ?? .system
        firstName = UserDefaults.standard.string(forKey: "firstName") ?? ""
        lastName = UserDefaults.standard.string(forKey: "lastName") ?? ""
        showFlowBar = UserDefaults.standard.object(forKey: "showFlowBar") as? Bool ?? true

        let provider = UserDefaults.standard.string(forKey: "llmProvider")
            .flatMap(LLMProvider.init(rawValue:)) ?? .anthropic
        llmProvider = provider
        llmModel = UserDefaults.standard.string(forKey: "llmModel.\(provider.rawValue)")
            ?? provider.defaultModel
        let migratedBase = LLMCleanup.normalisedBase(
            UserDefaults.standard.string(forKey: "llmBaseURL.\(provider.rawValue)")
                ?? provider.defaultBaseURL)
        llmBaseURL = migratedBase
        // Persist the corrected form: init assignments don't fire didSet, so
        // without this the old full-endpoint string stays on disk and anyone
        // reading the settings still sees the broken value.
        UserDefaults.standard.set(migratedBase, forKey: "llmBaseURL.\(provider.rawValue)")
        llmAPIKey = LLMKeychain.read(provider.rawValue) ?? ""
        llmModels = provider.fallbackModels
        llmEnabled = UserDefaults.standard.object(forKey: "llmEnabled") as? Bool ?? true

        appearance.apply()

        recorder.onLevel = { [weak self] level in self?.pushLevel(level) }
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
            refreshDictionary()
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
                // Spelled out: this line previously printed the *granted*
                // booleans while the enum beside it uses true = missing, and it
                // sent debugging after the wrong permission.
                let mic = Permissions.microphoneGranted ? "granted" : "MISSING"
                let ax = Permissions.accessibilityGranted ? "granted" : "MISSING"
                dlog("app: waiting for permissions (microphone \(mic), accessibility \(ax))")
                logged = true
            }
            try? await Task.sleep(for: .seconds(2))
        }
        dlog("app: permissions granted")
    }

    // MARK: - Dictation flow

    /// Speech RMS is roughly 0.02–0.3; scale to a 0…1 bar height.
    private func pushLevel(_ raw: Float) {
        guard phase == .recording else { return }
        levelHistory.removeFirst()
        levelHistory.append(min(1, raw * 9))
    }

    private func startRecording() {
        // .error is recoverable — the next dictation attempt clears it.
        guard phase == .idle || isError else { return }
        do {
            levelHistory = Array(repeating: 0, count: levelHistory.count)
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

        let cleanup = llmConfig // nil unless the user stored an API key
        Task.detached(priority: .userInitiated) { [transcriber, weak self] in
            var output = transcriber.transcribe(samples: samples)
            if let cleanup, let raw = output, !raw.text.isEmpty {
                switch await LLMCleanup.clean(raw.text, config: cleanup) {
                case .cleaned(let text):
                    output = Transcriber.Output(
                        text: text,
                        language: raw.language,
                        transcribeMs: raw.transcribeMs
                    )
                    await self?.noteCleanup(error: nil)
                case .failed(let message):
                    // Keep the raw transcript — a failed cleanup must never
                    // cost the user their dictation.
                    await self?.noteCleanup(error: message)
                }
            }
            await self?.finish(output: output, audioMs: audioMs, targetApp: targetApp)
        }
    }

    private func noteCleanup(error: String?) {
        llmError = error
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
        stats = history?.stats() ?? HistoryStore.Stats()
    }

    /// Recomputed when the Analytics screen appears rather than after every
    /// dictation — it's a full scan, and nothing is watching it in the background.
    func refreshAnalytics() {
        analytics = history?.analytics() ?? HistoryStore.Analytics()
    }

    func deleteTranscript(_ transcript: Transcript) {
        history?.delete(id: transcript.id)
        refreshRecent()
    }

    func updateTranscriptText(id: Int64, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let before = recentTranscripts.first { $0.id == id }?.text
        history?.updateText(id: id, text: trimmed)
        if let before { learnTerms(from: before, to: trimmed) }
        refreshRecent()
    }

    /// Corrections the user types by hand are the best vocabulary signal there
    /// is (spec 12 §E). Learned terms land in the Dictionary tab, so anything
    /// picked up wrongly is visible and one click from deleted.
    private func learnTerms(from before: String, to after: String) {
        let terms = TermLearner.learnedTerms(
            before: before, after: after, known: dictionary.map(\.phrase)
        )
        guard !terms.isEmpty else { return }
        for term in terms where history?.dictionaryAdd(term) == true {
            dlog("dictionary: learned \"\(term)\" from an edit")
        }
        refreshDictionary() // re-primes Whisper's glossary for the next dictation
    }

    // MARK: - Dictionary

    func refreshDictionary() {
        dictionary = history?.dictionaryEntries() ?? []
        transcriber.glossary = dictionary.map(\.phrase)
    }

    @discardableResult
    func addDictionaryEntry(_ phrase: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let added = history?.dictionaryAdd(trimmed) ?? false
        refreshDictionary()
        return added
    }

    func updateDictionaryEntry(id: Int64, phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history?.dictionaryUpdate(id: id, phrase: trimmed)
        refreshDictionary()
    }

    func deleteDictionaryEntry(id: Int64) {
        history?.dictionaryDelete(id: id)
        refreshDictionary()
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
