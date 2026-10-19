import SwiftUI

/// Kopie "Ember" theme — mirrors docs/redesign/prototype.html token table 1:1.
/// The *mechanics* come from Airpisode (near-black canvas, two radial glows,
/// translucent cards with a gradient hairline, capsule chips, one spring
/// vocabulary). The *palette* is Kopie's own, read off the peach→rose board in
/// its app icon:
///     accent        #E9622F   tangerine
///     accentMagenta #C42A63   raspberry
/// Every token resolves per `ColorScheme` so no component ever branches on
/// appearance — the dark set and the warm-paper light set are both spelled out.
enum Theme {
    // MARK: Gradient stops (same in both appearances)

    static let accent = Color(red: 233 / 255, green: 98 / 255, blue: 47 / 255)        // #E9622F
    static let accentMagenta = Color(red: 196 / 255, green: 42 / 255, blue: 99 / 255) // #C42A63

    // Appears-as-text accents get darkened in light mode (--accent-ink).
    // The spec's 18% ink mix only reaches ~4.4:1 on the card surface — too
    // faint for 11px labels like the "Rich" tag. 35% ink keeps the burnt
    // tangerine hue and clears 5:1 on warm paper.
    static func accentInk(for scheme: ColorScheme) -> Color {
        scheme == .dark ? accent
            // Color(red:green:blue:) takes 0–1 components; the mix helpers work
            // in 0–255, so divide here (before this, everything clamped to
            // white — the "Rich" tag and pin literally vanished on light cards).
            : Color(red: accentInkMix(233) / 255, green: accentInkMix(98) / 255, blue: accentInkMix(47) / 255)
    }
    /// 65% accent + 35% dark-ember ink (#2B1408): color-mix(65% accent, 35% ink)
    private static func accentInkMix(_ component: Double) -> Double {
        0.65 * component + 0.35 * inkComponent(component)
    }
    /// The dark ember base mixed into accent text in light mode.
    private static func inkComponent(_ accentComponent: Double) -> Double {
        // proportional share of #2B1408 (43,20,8) following the accent channel ratio
        accentComponent * (43.0 / 233.0)
    }

    // MARK: Semantic colors (per scheme, straight from the HTML)

    static func star(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 210 / 255, blue: 74 / 255)        // #FFD24A
            : Color(red: 217 / 255, green: 155 / 255, blue: 0)                     // #D99B00
    }
    /// The `.skel` sheen band: white .22 on the near-black canvas, white .85
    /// on warm paper.
    static func sheen(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.85)
    }
    static func danger(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 107 / 255, blue: 107 / 255)       // #FF6B6B
            : Color(red: 179 / 255, green: 38 / 255, blue: 30 / 255)               // #B3261E
    }
    static func dangerBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? danger(for: scheme).opacity(0.16)
            : Color(red: 179 / 255, green: 38 / 255, blue: 30 / 255).opacity(0.10)
    }
    static func warn(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 162 / 255, blue: 58 / 255)        // #FFA23A
            : Color(red: 169 / 255, green: 90 / 255, blue: 8 / 255)                // #A95A08
    }
    static func ok(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 61 / 255, green: 220 / 255, blue: 132 / 255) // #3DDC84
            : Color(red: 17 / 255, green: 120 / 255, blue: 74 / 255)               // #11784A
    }

    // MARK: Surfaces

    /// The canvas base — `--bg`: pure black in dark, warm paper #FBF8F4 in light.
    static func bg(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .black
            : Color(red: 251 / 255, green: 248 / 255, blue: 244 / 255)
    }
    /// The window chrome base — `--win-bg`: #0A0A0E dark, #FFFDFA light.
    static func winBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 10 / 255, green: 10 / 255, blue: 14 / 255)
            : Color(red: 1, green: 253 / 255, blue: 250 / 255)
    }

    /// Translucent card fill — `--card`: white .05 dark, white .90 light.
    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05)
            : Color.white.opacity(0.90)
    }
    /// Chip / subtle-control fill — `--chip`.
    static func chipColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08)
            : Color(red: 31 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.06)
    }
    /// 1px stroke color — `--hairline`.
    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08)
            : Color(red: 31 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.10)
    }
    /// Gradient hairline endpoints — `--edge-a` / `--edge-b`.
    static func edgeA(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14)
            : Color(red: 31 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.13)
    }
    static func edgeB(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.02)
            : Color(red: 31 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.05)
    }

    /// Hover and selection fills for rows — `--row-hover` / `--row-sel`.
    static func rowHover(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : .white
    }
    static func rowSelected(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09)
            : Color(red: 253.5 / 255, green: 244 / 255, blue: 240.7 / 255) // accent 7% over white
    }
    /// Content well behind preview text — `--content-bg`.
    static func contentBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.04)
            : Color(red: 31 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.035)
    }
    /// Search/text fields — `--field-bg`: white .06 dark, solid white light.
    static func fieldBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : .white
    }

    // MARK: Text

    /// Base text color the opacities sit on — white dark, #1A130E light.
    private static func textBase(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white
            : Color(red: 26 / 255, green: 19 / 255, blue: 14 / 255)
    }
    static func textPrimary(for scheme: ColorScheme) -> Color  { textBase(for: scheme).opacity(0.94) }
    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : textBase(for: scheme).opacity(0.64)
    }
    static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.40) : textBase(for: scheme).opacity(0.44)
    }

    // MARK: Canvas glows

    /// The two glow tints — `--accent-soft` / `--magenta-soft`.
    static func accentSoft(for scheme: ColorScheme) -> Color {
        scheme == .dark ? accent.opacity(0.20) : accent.opacity(0.10)
    }
    static func magentaSoft(for scheme: ColorScheme) -> Color {
        scheme == .dark ? accentMagenta.opacity(0.16) : accentMagenta.opacity(0.08)
    }

    // MARK: Gradient

    /// `--grad` — runs top-to-bottom through chips, tiles, buttons, selection.
    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accentMagenta], startPoint: .top, endPoint: .bottom)
    }
    /// `--grad-h` — horizontal variant for display flourishes.
    static var gradientHorizontal: LinearGradient {
        LinearGradient(colors: [accent, accentMagenta], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Radii

    static let cardRadius: CGFloat = 16
    static let rowRadius: CGFloat = 14
    static let tileRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8

    // MARK: Type (≤4 sizes / 2 weights rule)

    static let tPage: CGFloat = 26
    static let tSection: CGFloat = 17
    static let tRow: CGFloat = 14
    static let tMeta: CGFloat = 11
}

// MARK: - Canvas view

/// The canvas itself: `--bg` with two radial glows exactly where the CSS puts
/// them — accent circle 640px at 10% -6%, magenta circle 720px at 108% 112%.
/// Scaled to the window so both glows stay proportionally placed at any size.
struct EmberCanvas: View {
    let scheme: ColorScheme
    // The HTML's radial glows are FIXED 640px/720px circles — never scaled to
    // the window. (Scaling them made the tints wash over the whole canvas.)
    var body: some View {
        ZStack {
            Theme.bg(for: scheme)
                .ignoresSafeArea()
            RadialGradient(
                colors: [Theme.accentSoft(for: scheme), .clear],
                center: UnitPoint(x: 0.10, y: -0.06),
                startRadius: 0,
                endRadius: 640)
                .ignoresSafeArea()
            RadialGradient(
                colors: [Theme.magentaSoft(for: scheme), .clear],
                center: UnitPoint(x: 1.08, y: 1.12),
                startRadius: 0,
                endRadius: 720)
                .ignoresSafeArea()
        }
    }
}

extension Theme {
    /// Drop-in canvas for callers that just want "the background".
    static func canvas(for scheme: ColorScheme) -> some View {
        EmberCanvas(scheme: scheme)
    }
}
