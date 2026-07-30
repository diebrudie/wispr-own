import Cocoa

@main
enum Entry {
    static func main() {
        // Headless verification paths (eval gates): --transcribe / --devices / --stats
        if let index = CommandLine.arguments.firstIndex(of: "--transcribe"),
           CommandLine.arguments.count > index + 1 {
            TranscribeCLI.run(path: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--devices") {
            TranscribeCLI.listDevices()
            return
        }
        if CommandLine.arguments.contains("--stats") {
            TranscribeCLI.printStats()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > index + 1 {
            MainActor.assumeIsolated {
                TranscribeCLI.snapshot(path: CommandLine.arguments[index + 1],
                                       dark: CommandLine.arguments.contains("dark"))
            }
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            TranscribeCLI.selfTest()
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
