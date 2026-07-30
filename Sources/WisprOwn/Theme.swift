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

    /// Primary text, NSColor-backed so it still adapts to the appearance
    /// (including increased-contrast) rather than being hard-coded.
    ///
    /// Note: large text on the plain window background ghosts in `--snapshot`
    /// renders under dark mode — `.labelColor` and SwiftUI's `.primary` behave
    /// the same way there. It is an ImageRenderer artifact, not a product bug:
    /// the same text renders correctly in light snapshots and in the app.
    static let primaryText = Color(nsColor: .labelColor)

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

    /// Sequential ramp for the activity calendar — one hue, four steps of
    /// rising intensity. Validator-checked for monotone lightness, visible
    /// gaps between steps, and a faintest step that still clears the card
    /// (2:1); an invisible "some activity" cell is the usual heatmap bug.
    /// Dark runs dark→light because intensity has to read *against* a dark
    /// surface, not toward it.
    static let calendarSteps: [Color] = [
        step(light: 0.737, 0.671, 0.925, dark: 0.345, 0.302, 0.608), // #BCABEC / #584D9B
        step(light: 0.604, 0.494, 0.894, dark: 0.443, 0.376, 0.714), // #9A7EE4 / #7160B6
        step(light: 0.435, 0.318, 0.824, dark: 0.561, 0.451, 0.902), // #6F51D2 / #8F73E6
        step(light: 0.310, 0.180, 0.720, dark: 0.757, 0.682, 0.980), // #4F2EB8 / #C1AEFA
    ]

    /// A day with no dictations — present but recessive, so gaps in the run read
    /// as gaps rather than as missing cells.
    static let calendarEmpty = dynamic(
        light: NSColor(red: 0.31, green: 0.18, blue: 0.72, alpha: 0.07),
        dark: NSColor(white: 1, alpha: 0.07)
    )

    private static func step(light lr: CGFloat, _ lg: CGFloat, _ lb: CGFloat,
                             dark dr: CGFloat, _ dg: CGFloat, _ db: CGFloat) -> Color {
        dynamic(light: NSColor(red: lr, green: lg, blue: lb, alpha: 1),
                dark: NSColor(red: dr, green: dg, blue: db, alpha: 1))
    }

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

    /// The page container — Flow-style, the content sits on a light panel while
    /// the sidebar merges into the window background behind it.
    static let contentBackground = dynamic(
        light: NSColor(red: 0.998, green: 0.996, blue: 0.99, alpha: 1),
        dark: NSColor(red: 0.137, green: 0.137, blue: 0.149, alpha: 1)
    )

    /// Cards *inside* the content panel. They can't be the same near-white as
    /// the panel or they vanish, so they step toward the warm page colour.
    static let insetCard = dynamic(
        light: NSColor(red: 0.957, green: 0.949, blue: 0.933, alpha: 1),
        dark: NSColor(red: 0.196, green: 0.196, blue: 0.212, alpha: 1)
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

/// One size for every interactive control in the app. Buttons and text fields
/// that differ by a few points read as sloppiness, and they were: a bordered
/// "Cancel" next to a filled "Add" came out shorter, and text fields were
/// shorter than both.
enum Control {
    static let height: CGFloat = 38
    static let radius: CGFloat = 9
    static let font = Font.system(size: 14, weight: .semibold)
}

/// Filled accent — the primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Control.font)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: Control.height)
            .background(Theme.accentFixed.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: Control.radius))
            .contentShape(RoundedRectangle(cornerRadius: Control.radius))
    }
}

/// Same geometry, quieter fill — for the action beside a primary one.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Control.font)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .frame(height: Control.height)
            .background(Theme.tintedFill.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: Control.radius))
            .contentShape(RoundedRectangle(cornerRadius: Control.radius))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A text field that matches the buttons: same height, same corner radius.
struct FieldBackground: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: Control.height)
            .background(Theme.insetCard, in: RoundedRectangle(cornerRadius: Control.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Control.radius)
                    .strokeBorder(focused ? Theme.accent : Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func fieldStyle(focused: Bool = false) -> some View {
        modifier(FieldBackground(focused: focused))
    }
}

/// Flow-style page framing: content stops growing past a comfortable reading
/// width and centres, rather than stretching edge to edge on a wide display —
/// a row of text spanning 2000px is genuinely hard to track left to right.
struct PageWidth: ViewModifier {
    static let maximum: CGFloat = 1040

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Self.maximum, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension View {
    func pageWidth() -> some View { modifier(PageWidth()) }
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
