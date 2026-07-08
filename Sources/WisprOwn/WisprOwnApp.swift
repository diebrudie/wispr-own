import Cocoa

@main
enum Entry {
    static func main() {
        // Headless verification path (eval gate G3): WisprOwn --transcribe <audio-file>
        if let index = CommandLine.arguments.firstIndex(of: "--transcribe"),
           CommandLine.arguments.count > index + 1 {
            TranscribeCLI.run(path: CommandLine.arguments[index + 1])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Regular app with a Dock icon (user decision 2026-07-08): the menu
        // bar item was invisible next to a notch, and a clickable icon that
        // opens History is the wanted UI. Clicking the Dock icon reopens it.
        app.setActivationPolicy(.regular)
        app.run()
    }
}
