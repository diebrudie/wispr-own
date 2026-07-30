import Cocoa

/// The push-to-talk key, stored as a raw key code so any modifier can be used —
/// the user records it by pressing it rather than picking it from a list.
///
/// Modifier keys only. A letter or function key emits key-repeat while held and
/// would fire inside whatever the user is typing into, which is the opposite of
/// push-to-talk.
struct HotkeyOption: Equatable, Identifiable {
    let keyCode: Int64

    var id: Int64 { keyCode }

    static let leftOption = HotkeyOption(keyCode: 58)
    static let rightOption = HotkeyOption(keyCode: 61)
    static let fn = HotkeyOption(keyCode: 63)
    static let rightCommand = HotkeyOption(keyCode: 54)

    /// Every modifier macOS reports through `flagsChanged`, with the flag that
    /// distinguishes held from released.
    private static let known: [Int64: (name: String, flag: CGEventFlags)] = [
        54: ("Right Command ⌘", .maskCommand),
        55: ("Left Command ⌘", .maskCommand),
        56: ("Left Shift ⇧", .maskShift),
        60: ("Right Shift ⇧", .maskShift),
        58: ("Left Option ⌥", .maskAlternate),
        61: ("Right Option ⌥", .maskAlternate),
        59: ("Left Control ⌃", .maskControl),
        62: ("Right Control ⌃", .maskControl),
        63: ("Fn / Globe 🌐", .maskSecondaryFn),
    ]

    /// True when this key code is a modifier usable for push-to-talk.
    static func isSupported(keyCode: Int64) -> Bool { known[keyCode] != nil }

    var flag: CGEventFlags { Self.known[keyCode]?.flag ?? .maskAlternate }

    var displayName: String { Self.known[keyCode]?.name ?? "Key \(keyCode)" }

    /// Only surfaced when the conflict is actually present. macOS gives Fn its
    /// own job (input source, emoji, dictation) unless that is switched off, and
    /// warning unconditionally just teaches the user to ignore warnings.
    var caveat: String? {
        guard keyCode == 63, Self.fnKeyHasSystemAction else { return nil }
        return "macOS still uses 🌐 for its own shortcut, so it may not reach WisprOwn."
    }

    /// `AppleFnUsageType`: 0 means "Do Nothing". Absent means the system
    /// default, which is *not* "Do Nothing".
    static var fnKeyHasSystemAction: Bool {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        guard let value = defaults?.object(forKey: "AppleFnUsageType") as? Int else { return true }
        return value != 0
    }

    static func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    static var current: HotkeyOption {
        get {
            if let stored = UserDefaults.standard.object(forKey: "hotkeyCode") as? Int,
               isSupported(keyCode: Int64(stored)) {
                return HotkeyOption(keyCode: Int64(stored))
            }
            // Migrate the old name-based setting so upgrading keeps the key.
            switch UserDefaults.standard.string(forKey: "hotkey") {
            case "rightOption": return .rightOption
            case "fn": return .fn
            case "rightCommand": return .rightCommand
            default: return .leftOption
            }
        }
        set { UserDefaults.standard.set(Int(newValue.keyCode), forKey: "hotkeyCode") }
    }
}

/// Captures the next modifier key the user presses, so choosing a shortcut is
/// pressing it rather than hunting for it in a menu.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var onCapture: ((HotkeyOption) -> Void)?

    func start(_ onCapture: @escaping (HotkeyOption) -> Void) {
        stop()
        self.onCapture = onCapture
        isRecording = true
        // A local monitor is enough: Settings is key while recording, and it
        // needs no permission beyond what the app already holds.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let code = Int64(event.keyCode)
            guard HotkeyOption.isSupported(keyCode: code) else { return event }
            self.onCapture?(HotkeyOption(keyCode: code))
            self.stop()
            return nil // swallowed, so recording a key doesn't also trigger it
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onCapture = nil
    }
}
