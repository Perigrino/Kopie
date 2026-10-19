import SwiftUI

enum DS {
    static let pad: CGFloat = 16
}

/// Full-bleed Ember canvas behind onboarding / windows.
/// In dark: near-black with two radial glows (from Theme.canvas).
/// In light: warm paper (#FBF8F4) with same gradient mechanics.
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Theme.canvas(for: scheme)
            .ignoresSafeArea()
    }
}
/// Full-bleed pastel base behind the onboarding — kept for the landing page.
/// The redesigned onboarding uses ThemeBackground instead; BreathingBackground stays for splash/landing.
struct BreathingBackground: View {
    var reduceMotion: Bool
    /// Seconds per breath cycle; `nil` (or Reduce Motion) keeps the gradient
    /// static while still covering the whole background.
    var cycle: Double? = 30
    @State private var breathe = false
    @Environment(\.colorScheme) private var colorScheme

    /// Pastel gradient base — light in light mode, deep muted pastels in dark
    /// mode so the landing matches the rest of the app in both appearances.
    private var colors: [Color] {
        colorScheme == .dark
            ? [
                Color(red: 0.09, green: 0.09, blue: 0.13),
                Color(red: 0.13, green: 0.10, blue: 0.18),
                Color(red: 0.14, green: 0.10, blue: 0.15),
                Color(red: 0.09, green: 0.11, blue: 0.17)
            ]
            : [
                Color(red: 0.992, green: 0.984, blue: 1.0),
                Color(red: 0.965, green: 0.937, blue: 1.0),
                Color(red: 0.992, green: 0.941, blue: 0.965),
                Color(red: 0.961, green: 0.973, blue: 1.0)
            ]
    }

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                // 200%-sized canvas, like `background-size: 200% 200%`; sliding
                // it diagonally by one viewport sweeps the gradient across the
                // window (background-position 0%→100%).
                .frame(width: geo.size.width * 2, height: geo.size.height * 2)
                .offset(x: breathe ? -geo.size.width : 0, y: breathe ? -geo.size.height : 0)
                .animation(.easeInOut(duration: cycle ?? 30).repeatForever(autoreverses: true), value: breathe)
                .onAppear { if !reduceMotion, let cycle, cycle > 0 { breathe = true } }
        }
        .ignoresSafeArea()
    }
}
/// `.icon-btn` — 28×28 rounded control, transparent at rest; hover fills it
/// with `--chip` and promotes the glyph to the base text color.
struct EmberIconButton: View {
    let systemName: String
    let scheme: ColorScheme
    let action: () -> Void
    /// Accent ("on") state — glyph takes the accent ink.
    var isOn: Bool = false
    /// Star accent variant (`.icon-btn.star.on`).
    var star: Bool = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .background {
                    if hovering {
                        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                            .fill(Theme.chipColor(for: scheme))
                    }
                }
                .foregroundStyle(foreground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    private var foreground: AnyShapeStyle {
        if isOn { return AnyShapeStyle(star ? Theme.star(for: scheme) : Theme.accentInk(for: scheme)) }
        return AnyShapeStyle(Theme.textTertiary(for: scheme))
    }
}

/// The spec's `.toggle`: 38×22 capsule, gradient track when on, 18pt white knob.
struct EmberToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.chipColor(for: scheme)))
                .overlay {
                    Capsule().strokeBorder(Theme.hairline(for: scheme), lineWidth: 1)
                        .opacity(configuration.isOn ? 0 : 1)
                }
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .padding(2)
                        .animation(Motion.quick, value: configuration.isOn)
                }
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// The spec's `.btn.primary`: gradient pill with the primary drop shadow.
struct EmberPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var verticalPadding: CGFloat = 7
    var horizontalPadding: CGFloat = 16
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12)) }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Capsule().fill(Theme.gradient))
            .shadow(color: Theme.accent.opacity(scheme == .dark ? 0.35 : 0.28), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// The spec's `.btn` ghost: transparent, hairline text-level prominence.
struct EmberGhostButton: View {
    let title: String
    var muted: Bool = false /// step-1 "Back" — spec dims it to 45%.
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.chipColor(for: scheme)))
        }
        .buttonStyle(.plain)
        .opacity(muted ? 0.45 : 1)
    }
}

struct EmptyStateView: View {
    let symbol: String; let title: String; let message: String
    /// Optional `.btn.primary` call-to-action (spec shows one under the copy).
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary(for: scheme))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let buttonTitle, let buttonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.gradient))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 56).padding(.horizontal, 24)
    }
}

// MARK: - Skeleton (spec `.skel` + the section-6 "Loading" demo)

/// The spec's `.skel`: chip fill, radius 8 (12 for a tile-sized block), with a
/// 70%-wide sheen band sweeping left→right on a 1.4s linear loop
/// (`--sheen`: white .22 dark, white .85 light).
struct EmberSkeleton: View {
    var cornerRadius: CGFloat = 8
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.15
                : (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4)) / 1.4
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(Theme.chipColor(for: scheme))
                .overlay {
                    // `.skel::after` — sheen band starts fully off-left (-70%)
                    // and parks off-right (100%) at each loop end.
                    GeometryReader { geo in
                        let band = geo.size.width * 0.7
                        let travel = geo.size.width * 1.7
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Theme.sheen(for: scheme), .clear],
                                    startPoint: .leading, endPoint: .trailing))
                            .frame(width: band)
                            .offset(x: -band + t * travel)
                    }
                    .clipped()
                }
        }
    }
}

/// One spec "Loading" row: card + 44×44 tile skeleton + two text bars
/// (13px tall; the demo animates 62%→78% / 34%→28% widths).
struct SkeletonRow: View {
    var titleWidth: CGFloat = 0.62
    var metaWidth: CGFloat = 0.34
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            EmberSkeleton(cornerRadius: 12)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    EmberSkeleton().frame(width: geo.size.width * titleWidth, height: 13)
                }
                .frame(height: 13)
                GeometryReader { geo in
                    EmberSkeleton().frame(width: geo.size.width * metaWidth, height: 10)
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Theme.cardBackground(for: scheme)))
    }
}

/// The spec's section-6 "Loading" card: eyebrow + two skeleton rows on the
/// canvas. (Which is canvas-wrapped by callers needing the fenced demo look.)
struct LoadingRowsCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Loading")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary(for: scheme))
            VStack(spacing: 8) {
                SkeletonRow()
                SkeletonRow(titleWidth: 0.78, metaWidth: 0.28)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.winBackground(for: scheme)))
    }
}
