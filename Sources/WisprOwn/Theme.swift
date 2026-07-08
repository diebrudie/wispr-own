import AppKit
import SwiftUI

/// Violet palette derived from the app icon gradient (#5933BF → #291461).
/// Accents only — backgrounds stay system-adaptive for light/dark support.
enum Theme {
    static let accent = Color(red: 0.35, green: 0.20, blue: 0.75)
    static let accentDeep = Color(red: 0.16, green: 0.08, blue: 0.38)
    /// Subtle fill for cards/badges that reads in both appearances.
    static let tintedFill = accent.opacity(0.12)
}

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// App-wide override; nil follows the system setting.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
