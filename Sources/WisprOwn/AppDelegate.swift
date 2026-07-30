import Cocoa
import Combine
import SwiftUI

/// Spec 06 — menu bar UI via NSStatusItem (AppKit): more predictable than
/// SwiftUI's MenuBarExtra and it can report its own visibility for debugging.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
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

        setupFlowBar()
        appState.$showFlowBar
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                show ? self?.flowBarPanel?.orderFrontRegardless() : self?.flowBarPanel?.orderOut(nil)
            }
            .store(in: &cancellables)

        // Switching Space or activating another app can drop the panel behind
        // whatever is now frontmost, so re-assert it on every phase change —
        // which includes the moment recording starts.
        appState.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.appState.showFlowBar else { return }
                self.flowBarPanel?.orderFrontRegardless()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.appState.showFlowBar else { return }
                self.flowBarPanel?.orderFrontRegardless()
            }
        }
    }

    // MARK: - WisprOwn bar (floating bottom panel)

    private var flowBarPanel: NSPanel?

    private func setupFlowBar() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Level matters twice over. .floating (3) sits *below* the Dock (20),
        // so the bar hid behind it. .screenSaver (1000) sits above system UI and
        // covered the screenshot thumbnail and the ⌘-Tab switcher. .statusBar
        // (25) clears the Dock and stays under system UI — the right shelf.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: FlowBarView(app: appState))
        positionFlowBar(panel)
        if appState.showFlowBar {
            panel.orderFrontRegardless()
        }
        flowBarPanel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let panel = self.flowBarPanel else { return }
            self.positionFlowBar(panel)
        }
    }

    private func positionFlowBar(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 220, height: 46)
        panel.setFrame(NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 4,
            width: size.width,
            height: size.height
        ), display: true)
    }

    private func updateIcon(for phase: AppPhase) {
        let image = NSImage(systemSymbolName: phase.menuBarSymbol,
                            accessibilityDescription: "WisprOwn: \(phase.statusText)")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Main menu

    /// AppKit delivers ⌘X/⌘C/⌘V/⌘Z by matching the *main menu's* key
    /// equivalents — the text field never sees the keystroke itself. Without an
    /// Edit menu you can type into every field in the app but not paste into
    /// one, which is fatal for an API key nobody memorises.
    ///
    /// Actions target nil so they travel the responder chain to whatever field
    /// has focus. Menu titles come from AppKit's standard set so they localise
    /// and behave the way macOS users expect.
    private func setupMainMenu() {
        let appName = ProcessInfo.processInfo.processName
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Plain selector strings: `cut:`/`copy:`/`paste:` live on NSText and
        // friends, and #selector(NSText.copy(_:)) collides with NSObject.copy().
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")

        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main

        // Cheap startup assertion: if this ever stops finding Paste, every text
        // field in the app has silently become type-only again.
        let paste = editMenu.items.first { $0.keyEquivalent == "v" }
        dlog("ui: edit menu installed, paste=\(paste != nil)")
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
        menu.addItem(item("Open WisprOwn…", #selector(openMainWindow), key: "o"))
        menu.addItem(.separator())
        menu.addItem(item("Quit WisprOwn", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        appState.refreshRecent()
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: MainWindowView(app: appState))
            let window = NSWindow(contentViewController: hosting)
            window.title = "WisprOwn"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1100, height: 700))
            // Below this the sidebar plus a page of cards stops fitting and the
            // layout starts wrapping into itself.
            window.contentMinSize = NSSize(width: 900, height: 560)
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openMicSettings() { Permissions.openMicrophoneSettings() }
    @objc private func openAxSettings() { Permissions.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Dock icon click (and app reactivation) opens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openMainWindow()
        return true
    }
}
