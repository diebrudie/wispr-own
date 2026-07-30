import ServiceManagement
import SwiftUI

/// Settings sheet with a Flow-style grouped layout: a small nav column
/// (General / API Keys / Profile / System) beside the active pane.
struct SettingsOverlayView: View {
    @ObservedObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pane: Pane = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var devices: [AudioInputDevice] = []
    @StateObject private var recorder = HotkeyRecorder()

    enum Pane: String, CaseIterable, Identifiable {
        case general, apiKeys, profile, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .apiKeys: return "API Keys"
            case .profile: return "Profile"
            case .system: return "System"
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .apiKeys: return "key"
            case .profile: return "person.circle"
            case .system: return "macwindow"
            }
        }
    }

    /// Curated subset of Whisper's languages — the ones plausibly dictated.
    static let languageCatalog: [(code: String, name: String)] = [
        ("en", "English"), ("de", "Deutsch"), ("es", "Español"),
        ("fr", "Français"), ("it", "Italiano"), ("pt", "Português"),
        ("nl", "Nederlands"), ("pl", "Polski"), ("uk", "Українська"),
        ("ru", "Русский"), ("tr", "Türkçe"), ("sv", "Svenska"),
        ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"), ("ar", "العربية"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            navColumn
            Divider()
            detailColumn
        }
        .frame(width: 780, height: 560)
        .tint(Theme.accent)
        .onAppear { devices = AudioDevices.inputDevices() }
        .onDisappear { recorder.stop() }
    }

    private var navColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 8)

            ForEach(Pane.allCases) { item in
                Button {
                    pane = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            pane == item ? AnyShapeStyle(Theme.tintedFill) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .foregroundStyle(pane == item ? Theme.accent : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            Text("WisprOwn v0.5.0 · whisper turbo")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .frame(width: 190)
        .background(Theme.windowBackground)
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(pane.title)
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .top], 22)
            .padding(.bottom, 8)

            Form {
                switch pane {
                case .general: generalPane
                case .apiKeys: apiKeysPane
                case .profile: profilePane
                case .system: systemPane
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.cardBackground)
    }

    // MARK: - General (shortcut, microphone, languages)

    @ViewBuilder
    private var generalPane: some View {
        Section("Shortcut") {
            LabeledContent("Push-to-talk key") {
                HStack(spacing: 8) {
                    Text(recorder.isRecording ? "Press any modifier key…" : app.hotkeyOption.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(recorder.isRecording ? Theme.accent : .primary)
                        .frame(minWidth: 150, alignment: .trailing)
                    Button {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { app.hotkeyOption = $0 }
                        }
                    } label: {
                        Image(systemName: recorder.isRecording ? "xmark" : "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(recorder.isRecording ? "Cancel" : "Change the key")
                }
            }
            if recorder.isRecording {
                Text("Hold the key you want and it's saved — Option, Control, Command, Shift or 🌐.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let caveat = app.hotkeyOption.caveat {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(caveat, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("Open Keyboard Settings…") { HotkeyOption.openKeyboardSettings() }
                        .buttonStyle(.secondary)
                        .fixedSize()
                }
            }
        }

        Section("Microphone") {
            Picker("Input device", selection: $app.micUID) {
                Text("System Default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            if !app.micUID.isEmpty, AudioDevices.device(withUID: app.micUID) == nil {
                Label("The selected microphone isn't connected — the system default is used until it returns.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }

        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                ForEach(Self.languageCatalog, id: \.code) { language in
                    languageChip(language.code, language.name)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Dictation Languages")
        } footer: {
            Text(app.dictationLanguages.count == 1
                 ? "Single language: detection is skipped — slightly faster dictation."
                 : "The language is auto-detected per dictation, restricted to your selection.")
        }
    }

    private func languageChip(_ code: String, _ name: String) -> some View {
        let selected = app.dictationLanguages.contains(code)
        return Button {
            if selected {
                app.dictationLanguages.remove(code) // didSet guards against empty
            } else {
                app.dictationLanguages.insert(code)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text(name).lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.tintedFill : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.accent : Color.secondary.opacity(0.3)))
            .foregroundStyle(selected ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - API Keys (optional LLM pass, Spec 13)

    @ViewBuilder
    private var apiKeysPane: some View {
        Section {
            Picker("Provider", selection: $app.llmProvider) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            SecureField("API key", text: $app.llmAPIKey, prompt: Text("Paste to switch on"))
            // Named providers have exactly one endpoint; only Custom needs it.
            if app.llmProvider == .custom {
                TextField("Server", text: $app.llmBaseURL)
            }
        } header: {
            Text("API Key")
        } footer: {
            Text(app.llmAPIKey.isEmpty
                 ? "Optional. Without a key, dictation stays entirely on this Mac and nothing is sent anywhere."
                 : "Your dictation is sent to \(app.llmProvider.displayName) to be tidied up before it's pasted: filler words like \"um\" removed, punctuation fixed, and when you correct yourself mid-sentence — \"email John, I mean Jenn\" — only what you meant is kept. Delete the key to switch this off and go back to fully local dictation.")
        }
        .onAppear { app.refreshLLMModels() }

        if !app.llmAPIKey.isEmpty {
            Section {
                Toggle("Tidy up my dictation", isOn: $app.llmEnabled)
            } footer: {
                Text(app.llmEnabled
                     ? "On. Turn this off to dictate without sending anything — your key stays saved."
                     : "Off. Nothing is sent anywhere; your key is still saved for when you want it back.")
            }

            Section {
                Picker("Model", selection: $app.llmModel) {
                    ForEach(app.llmModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(app.llmModels.isEmpty || !app.llmEnabled)
            } footer: {
                Text(app.llmModels.isEmpty
                     ? "No models loaded — check the API key above."
                     : "Loaded from \(app.llmProvider.displayName), so the names are always theirs. Smaller models finish faster, and this runs before every paste.")
            }

            Section {
                if let error = app.llmError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    Label("No errors on the last dictation.", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("This gets \(Int(LLMCleanup.timeout)) seconds. If it fails or times out, your original dictation is pasted instead — nothing is ever lost to this.")
            }
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profilePane: some View {
        Section {
            TextField("First name", text: $app.firstName, prompt: Text(defaultFirstName))
            TextField("Last name", text: $app.lastName)
        } header: {
            Text("Your Name")
        } footer: {
            Text("Used for the Home greeting. Empty first name falls back to your macOS account name.")
        }
    }

    private var defaultFirstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
    }

    // MARK: - System

    @ViewBuilder
    private var systemPane: some View {
        Section("Appearance") {
            Picker("Theme", selection: $app.appearance) {
                ForEach(AppearanceOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("App settings") {
            Toggle("Show WisprOwn bar at all times", isOn: $app.showFlowBar)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enable in
                    do {
                        if enable {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError).font(.callout).foregroundStyle(.red)
            }
        }

        Section("Sound") {
            Toggle("Play sound when recording starts", isOn: Binding(
                get: { app.playSounds },
                set: { app.playSounds = $0 }
            ))
        }

        Section("Data") {
            LabeledContent("Data folder") {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ModelManager.supportDir])
                }
            }
        }
    }
}
