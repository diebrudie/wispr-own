import ServiceManagement
import SwiftUI

/// Settings as a sheet overlay (Flow-style popup over the main window).
struct SettingsOverlayView: View {
    @ObservedObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var devices: [AudioInputDevice] = []

    /// Curated subset of Whisper's languages — the ones plausibly dictated.
    static let languageCatalog: [(code: String, name: String)] = [
        ("en", "English"), ("de", "Deutsch"), ("es", "Español"),
        ("fr", "Français"), ("it", "Italiano"), ("pt", "Português"),
        ("nl", "Nederlands"), ("pl", "Polski"), ("uk", "Українська"),
        ("ru", "Русский"), ("tr", "Türkçe"), ("sv", "Svenska"),
        ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"), ("ar", "العربية"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Form {
                profileSection
                shortcutSection
                microphoneSection
                languagesSection
                appearanceSection
                generalSection
                Section {
                    LabeledContent("Version", value: "0.3.3")
                    LabeledContent("Engine", value: "whisper large-v3-turbo · CoreML")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 620)
        .tint(Theme.accent)
        .onAppear { devices = AudioDevices.inputDevices() }
    }

    private var profileSection: some View {
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

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $app.appearance) {
                ForEach(AppearanceOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var shortcutSection: some View {
        Section("Shortcut") {
            Picker("Push-to-talk key", selection: $app.hotkeyOption) {
                ForEach(HotkeyOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            if let caveat = app.hotkeyOption.caveat {
                Label(caveat, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var microphoneSection: some View {
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
    }

    private var languagesSection: some View {
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

    private var generalSection: some View {
        Section("General") {
            Toggle("Play sound when recording starts", isOn: Binding(
                get: { app.playSounds },
                set: { app.playSounds = $0 }
            ))
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
            LabeledContent("Data folder") {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ModelManager.supportDir])
                }
            }
        }
    }
}
