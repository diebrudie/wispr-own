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
        // Menu-bar-only: no Dock icon. (The .app also sets LSUIElement;
        // this covers `swift run` during development.)
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
