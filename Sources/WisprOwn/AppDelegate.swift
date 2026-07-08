import Cocoa
import Combine
import SwiftUI

/// Spec 06 — menu bar UI via NSStatusItem (AppKit): more predictable than
/// SwiftUI's MenuBarExtra and it can report its own visibility for debugging.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var statusItem: NSStatusItem!
    private var historyWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(for: appState.phase)
        rebuildMenu(for: appState.phase)
        dlog("ui: status item created, visible=\(statusItem.isVisible)")

        appState.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.updateIcon(for: phase)
                self?.rebuildMenu(for: phase)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for phase: AppPhase) {
        let image = NSImage(systemSymbolName: phase.menuBarSymbol,
                            accessibilityDescription: "WisprOwn: \(phase.statusText)")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func rebuildMenu(for phase: AppPhase) {
        let menu = NSMenu()

        let status = NSMenuItem(title: phase.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if case .needsPermissions(let mic, let accessibility) = phase {
            if mic {
                menu.addItem(item("Grant Microphone Access…", #selector(openMicSettings)))
            }
            if accessibility {
                menu.addItem(item("Grant Accessibility Access…", #selector(openAxSettings)))
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("History…", #selector(openHistory), key: "h"))

        let sounds = item("Play Sounds", #selector(toggleSounds))
        sounds.state = appState.playSounds ? .on : .off
        menu.addItem(sounds)

        menu.addItem(.separator())
        menu.addItem(item("Quit WisprOwn", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openHistory() {
        appState.refreshRecent()
        if historyWindow == nil {
            let hosting = NSHostingController(rootView: HistoryView(app: appState))
            let window = NSWindow(contentViewController: hosting)
            window.title = "WisprOwn History"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 480))
            window.isReleasedWhenClosed = false
            window.center()
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleSounds() {
        appState.playSounds.toggle()
        rebuildMenu(for: appState.phase)
    }

    @objc private func openMicSettings() { Permissions.openMicrophoneSettings() }
    @objc private func openAxSettings() { Permissions.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
