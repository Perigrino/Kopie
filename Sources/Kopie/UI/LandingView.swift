import SwiftUI
import AppKit

/// First-run landing — the redesigned page applied natively:
/// calm ambient background (floating orbs, sparkles, rising particles) with a
/// subtle mouse parallax, the liquid-fill glass (Option 2), springy
/// letter-by-letter "Kopie" (Option 8), and the hero copy (greeting, tagline,
/// description). Respects Reduce Motion.
struct LandingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false
    @State private var iconShown = false
    @State private var shineX: CGFloat = -60
    @State private var lettersShown = Array(repeating: false, count: 5)
    @State private var greetingShown = false
    @State private var taglineShown = false
    @State private var subShown = false
    @State private var iconHovered = false
    @State private var hoverPoint: CGPoint?

    private let letters = Array("Kopie")
    private let coral = Color(red: 1.0, green: 0.49, blue: 0.56)
    private let dark = Color(red: 0.12, green: 0.13, blue: 0.19)
    private let slate = Color(red: 0.36, green: 0.36, blue: 0.44)

    var body: some View {
        ZStack {
            // Full-bleed pastel base — always covers the entire background
            // (including Reduce Motion), mirroring the HTML body gradient.
            baseBackground

            if !reduceMotion {
                ambient
            }
            VStack(spacing: 5) {
                glass
                greeting
                word
                tagline
                sub
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hoverPoint = point
            case .ended: hoverPoint = nil
            }
        }
        .onAppear {
            if reduceMotion { revealAll() } else { play() }
        }
    }

    // MARK: - Ambient background

    /// Full-bleed pastel base with the HTML's 30s bgBreath drift. Rendered
    /// under everything, including Reduce Motion (static then), so the landing
    /// never has plain white gaps.
    private var baseBackground: some View {
        BreathingBackground(reduceMotion: reduceMotion)
    }

    @ViewBuilder private var ambient: some View {
        ZStack {
            Orb(color: Color(red: 1.0, green: 0.78, blue: 0.85), size: 200, duration: 8, reduceMotion: reduceMotion)
                .offset(x: -160, y: -130)
            Orb(color: Color(red: 0.76, green: 0.70, blue: 1.0), size: 180, duration: 10, reduceMotion: reduceMotion)
                .offset(x: 160, y: -120)
            Orb(color: Color(red: 1.0, green: 0.70, blue: 0.80), size: 220, duration: 12, reduceMotion: reduceMotion)
                .offset(x: -150, y: 120)
            Orb(color: Color(red: 0.70, green: 0.78, blue: 1.0), size: 190, duration: 9, reduceMotion: reduceMotion)
                .offset(x: 160, y: 130)

            Twinkle(symbol: "sparkle", color: coral.opacity(0.6), duration: 2.6, delay: 0, reduceMotion: reduceMotion)
                .offset(x: -175, y: -60)
            Twinkle(symbol: "sparkle", color: Color.purple.opacity(0.5), duration: 3.1, delay: 1.2, reduceMotion: reduceMotion)
                .offset(x: 170, y: -40)
            Twinkle(symbol: "sparkle", color: coral.opacity(0.55), duration: 2.8, delay: 2.0, reduceMotion: reduceMotion)
                .offset(x: -140, y: 80)
            Twinkle(symbol: "sparkle", color: Color.blue.opacity(0.4), duration: 3.4, delay: 0.6, reduceMotion: reduceMotion)
                .offset(x: 150, y: 90)

            Particle(x: -120, size: 5, duration: 9, delay: 0, reduceMotion: reduceMotion)
            Particle(x: -10, size: 4, duration: 11, delay: 3, reduceMotion: reduceMotion)
            Particle(x: 100, size: 6, duration: 10, delay: 6, reduceMotion: reduceMotion)
            Particle(x: 150, size: 4, duration: 12, delay: 1.5, reduceMotion: reduceMotion)
        }
        // Fill the whole window so orbs/sparkles/particles spread across the
        // entire background instead of a content-sized blob in the middle.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(parallax)
        .allowsHitTesting(false)
        .clipped()
    }

    private var parallax: CGSize {
        guard let point = hoverPoint else { return .zero }
        return CGSize(width: (point.x - 240) * 0.045, height: (point.y - 160) * 0.045)
    }

    // MARK: - Glass (Option 2: liquid fill + emerge + shine)

    private var glass: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.pink.opacity(0.32), .clear],
                                     center: .center, startRadius: 6, endRadius: 70))
                .frame(width: 150, height: 150)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.76, blue: 0.68),
                                              Color(red: 1.0, green: 0.47, blue: 0.55)],
                                     startPoint: .top, endPoint: .bottom))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.92)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.size.width, height: geo.size.height * (filled ? 1 : 0))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 32, height: 90)
                .offset(x: shineX)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Image(nsImage: AppIcon.image(pointSize: 52))
                .scaleEffect(iconShown ? 1 : 0.4)
                .opacity(iconShown ? 1 : 0)
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.pink.opacity(0.35), radius: 12, y: 6)
        .overlay {
            if !reduceMotion {
                // Mirrors the landing page's .hero-icon::before shimmer ring.
                ShimmerRing(hovered: iconHovered, cornerRadius: 16)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.6)) { iconHovered = hovering }
        }
    }

    // MARK: - Hero copy

    private var greeting: some View {
        Text("Hey there! 👋")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(coral)
            .opacity(greetingShown ? 1 : 0)
            .offset(y: greetingShown ? 0 : 7)
    }

    /// Option 8 — "Kopie" springs in letter by letter.
    private var word: some View {
        HStack(spacing: 2) {
            ForEach(0..<letters.count, id: \.self) { i in
                Text(String(letters[i]))
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(dark)
                    .offset(y: lettersShown[i] ? 0 : 24)
                    .scaleEffect(lettersShown[i] ? 1 : 0.4)
                    .opacity(lettersShown[i] ? 1 : 0)
            }
        }
    }

    private var tagline: some View {
        Text("Everything you copy. Always within reach.")
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(slate)
            .opacity(taglineShown ? 1 : 0)
            .offset(y: taglineShown ? 0 : 5)
    }

    /// The description once lived in the welcome card; it now follows the
    /// tagline directly, matching the HTML reference's layout.
    private var sub: some View {
        Text("Text, images, links — whatever you copy, Kopie keeps it close and ready when you need it. ❤️")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .allowsTightening(true)
            .opacity(subShown ? 1 : 0)
            .offset(y: subShown ? 0 : 5)
    }

    // MARK: - Sequence

    /// Runs a main-actor closure on the main queue after a delay.
    private func after(_ delay: Double, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(action)
        }
    }

    private func play() {
        after(0.1) { withAnimation(.easeInOut(duration: 0.9)) { filled = true } }
        after(0.9) { withAnimation(.linear(duration: 0.5)) { shineX = 170 } }
        after(1.0) { withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { iconShown = true } }
        after(0.45) { withAnimation(.easeOut(duration: 0.4)) { greetingShown = true } }
        for i in 0..<letters.count {
            after(1.3 + Double(i) * 0.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
                    lettersShown[i] = true
                }
            }
        }
        after(2.15) { withAnimation(.easeOut(duration: 0.45)) { taglineShown = true } }
        after(2.3) { withAnimation(.easeOut(duration: 0.45)) { subShown = true } }
    }

    private func revealAll() {
        filled = true
        shineX = 170
        iconShown = true
        greetingShown = true
        lettersShown = Array(repeating: true, count: letters.count)
        taglineShown = true
        subShown = true
    }
}

/// Shimmering border ring for the hero icon — mirrors the landing page's
/// `.hero-icon::before`: a pink→lavender band slides along the 1.5pt ring on
/// a 3.2s loop, faded in only while hovered. Rendered only when motion is
/// enabled, mirroring the page's reduced-motion rule.
private struct ShimmerRing: View {
    let hovered: Bool
    var cornerRadius: CGFloat = 14
    @State private var slide = false

    private let pink = Color(red: 1.0, green: 0.69, blue: 0.77)     // #ffb0c4
    private let lavender = Color(red: 0.84, green: 0.72, blue: 1.0) // #d6b8ff

    var body: some View {
        GeometryReader { geo in
            // The band sits mid-gradient on a 3×-wide canvas; sliding it from
            // 0 to -2W sweeps the band across the ring once per loop (the CSS
            // background-position 0%→300% trick).
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: pink, location: 0.42),
                    .init(color: lavender, location: 0.52),
                    .init(color: pink, location: 0.58),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 3)
            .offset(x: slide ? -geo.size.width * 2 : 0)
            .animation(.linear(duration: 3.2).repeatForever(autoreverses: false), value: slide)
            .onAppear { slide = true }
        }
        .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(lineWidth: 1.5))
        .opacity(hovered ? 1 : 0)
        .allowsHitTesting(false)
    }
}

// MARK: - Ambient pieces

private struct Orb: View {
    let color: Color
    let size: CGFloat
    let duration: Double
    let reduceMotion: Bool
    @State private var drift = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.55), .clear],
                                 center: .center, startRadius: 4, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: size / 4)
            .offset(x: drift ? -20 : 16, y: drift ? 12 : -12)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: drift)
            .onAppear { if !reduceMotion { drift = true } }
    }
}

private struct Twinkle: View {
    let symbol: String
    let color: Color
    let duration: Double
    let delay: Double
    let reduceMotion: Bool
    @State private var on = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .opacity(on ? 0.9 : 0.15)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay), value: on)
            .onAppear { if !reduceMotion { on = true } }
    }
}

private struct Particle: View {
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let reduceMotion: Bool
    @State private var risen = false

    var body: some View {
        Circle()
            .fill(Color.pink.opacity(0.4))
            .frame(width: size, height: size)
            .offset(x: x, y: risen ? -120 : 26)
            .opacity(risen ? 0 : 0.55)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay), value: risen)
            .onAppear { if !reduceMotion { risen = true } }
    }
}
