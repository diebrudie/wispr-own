import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Dictation") {
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
                Toggle("Play sound when recording starts", isOn: Binding(
                    get: { app.playSounds },
                    set: { app.playSounds = $0 }
                ))
            }

            Section("General") {
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

            Section {
                LabeledContent("Version", value: "0.2.0")
                LabeledContent("Engine", value: "whisper large-v3-turbo · CoreML")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
