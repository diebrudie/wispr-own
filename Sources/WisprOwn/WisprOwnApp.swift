import SwiftUI

@main
enum Entry {
    static func main() {
        // Headless verification path (eval gate G3): WisprOwn --transcribe <audio-file>
        if let index = CommandLine.arguments.firstIndex(of: "--transcribe"),
           CommandLine.arguments.count > index + 1 {
            TranscribeCLI.run(path: CommandLine.arguments[index + 1])
            return
        }
        WisprOwnApp.main()
    }
}

struct WisprOwnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: app)
        } label: {
            Image(systemName: app.phase.menuBarSymbol)
        }

        Window("WisprOwn History", id: "history") {
            HistoryView(app: app)
        }
        .defaultSize(width: 560, height: 480)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon. (The bundled .app also sets
        // LSUIElement; this covers `swift run` during development.)
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuContent: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(app.phase.statusText)

        if case .needsPermissions(let mic, let accessibility) = app.phase {
            if mic {
                Button("Grant Microphone Access…") { Permissions.openMicrophoneSettings() }
            }
            if accessibility {
                Button("Grant Accessibility Access…") { Permissions.openAccessibilitySettings() }
            }
        }

        Divider()

        Button("History…") {
            app.refreshRecent()
            openWindow(id: "history")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("h")

        Toggle("Play Sounds", isOn: Binding(
            get: { app.playSounds },
            set: { app.playSounds = $0 }
        ))

        Divider()

        Button("Quit WisprOwn") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
