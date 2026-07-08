import SwiftUI

/// Violet palette derived from the app icon gradient (#5933BF → #291461).
/// Accents only — backgrounds stay system-adaptive for light/dark support.
enum Theme {
    static let accent = Color(red: 0.35, green: 0.20, blue: 0.75)
    static let accentDeep = Color(red: 0.16, green: 0.08, blue: 0.38)
    /// Subtle fill for cards/badges that reads in both appearances.
    static let tintedFill = accent.opacity(0.12)
}
