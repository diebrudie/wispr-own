import Cocoa

/// User-selectable push-to-talk keys. Modifier keys only: regular keys
/// (like F5) emit key-repeat events and collide with typing, so they're
/// deliberately not offered.
enum HotkeyOption: String, CaseIterable, Identifiable {
    case leftOption
    case rightOption
    case fn
    case rightCommand

    var id: String { rawValue }

    var keyCode: Int64 {
        switch self {
        case .leftOption: return 58
        case .rightOption: return 61
        case .fn: return 63
        case .rightCommand: return 54
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .leftOption, .rightOption: return .maskAlternate
        case .fn: return .maskSecondaryFn
        case .rightCommand: return .maskCommand
        }
    }

    var displayName: String {
        switch self {
        case .leftOption: return "Left Option ⌥"
        case .rightOption: return "Right Option ⌥"
        case .fn: return "Fn / Globe 🌐"
        case .rightCommand: return "Right Command ⌘"
        }
    }

    /// Extra guidance shown in Settings for keys with system-level conflicts.
    var caveat: String? {
        switch self {
        case .fn:
            return "Set System Settings → Keyboard → “Press 🌐 key” to “Do Nothing”, and quit other tools using Fn (e.g. Wispr Flow)."
        default:
            return nil
        }
    }

    static var current: HotkeyOption {
        get {
            UserDefaults.standard.string(forKey: "hotkey")
                .flatMap(HotkeyOption.init(rawValue:)) ?? .leftOption
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotkey") }
    }
}
