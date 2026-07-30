import AppKit
import SwiftUI

/// Adaptive palette. Light mode borrows Wispr Flow's warm cream surfaces
/// with our violet as the accent; dark mode lifts the accent to lavender so
/// text and icons hit WCAG-AA contrast (deep violet is illegible on dark).
/// Colors are NSColor-dynamic, so they respect the in-app appearance override.
enum Theme {
    /// Accent for text, icons, numbers. Light: deep violet (~9:1 on cream).
    /// Dark: lavender (~7.5:1 on the dark surface).
    static let accent = dynamic(
        light: NSColor(red: 0.31, green: 0.18, blue: 0.72, alpha: 1),
        dark: NSColor(red: 0.72, green: 0.64, blue: 0.97, alpha: 1)
    )

    /// Fixed deep violet — only for the wordmark/icon gradient where the
    /// foreground is always white.
    static let accentDeep = Color(red: 0.16, green: 0.08, blue: 0.38)
    static let accentFixed = Color(red: 0.35, green: 0.20, blue: 0.75)

    /// Fill for chart marks — a different job from `accent`, which is a *text*
    /// colour. The dark accent is deliberately light so text clears WCAG-AA on
    /// the dark surface (L 0.765), and a fill that light glares as a bar; the
    /// data-viz lightness band for dark marks is L 0.48–0.67. This step sits
    /// inside it and still clears 3:1 against the card surface. Both values are
    /// validator-checked, not eyeballed — see spec 14.
    static let chartMark = dynamic(
        light: NSColor(red: 0.31, green: 0.18, blue: 0.72, alpha: 1), // #4F2EB8, L 0.43
        dark: NSColor(red: 0.545, green: 0.435, blue: 0.910, alpha: 1) // #8B6FE8, L 0.60
    )

    /// Recessive fill for the unfilled part of a proportion bar.
    static let chartTrack = dynamic(
        light: NSColor(red: 0.31, green: 0.18, blue: 0.72, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.10)
    )

    /// Subtle fill for badges and selected chips.
    static let tintedFill = dynamic(
        light: NSColor(red: 0.31, green: 0.18, blue: 0.72, alpha: 0.10),
        dark: NSColor(red: 0.72, green: 0.64, blue: 0.97, alpha: 0.18)
    )

    /// Detail-area background. Light: Flow's warm cream page.
    static let windowBackground = dynamic(
        light: NSColor(red: 0.953, green: 0.945, blue: 0.925, alpha: 1),
        dark: NSColor(red: 0.106, green: 0.106, blue: 0.114, alpha: 1)
    )

    /// Cards float on the page: near-white on cream (Flow-style), lifted gray on dark.
    static let cardBackground = dynamic(
        light: NSColor(red: 0.998, green: 0.996, blue: 0.99, alpha: 1),
        dark: NSColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
    )

    /// Row highlight while hovering.
    static let rowHover = dynamic(
        light: NSColor(white: 0, alpha: 0.045),
        dark: NSColor(white: 1, alpha: 0.055)
    )

    /// Hairline separators/borders that read on both surfaces.
    static let border = dynamic(
        light: NSColor(red: 0.31, green: 0.18, blue: 0.72, alpha: 0.15),
        dark: NSColor(white: 1, alpha: 0.12)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
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
