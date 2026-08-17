import SwiftUI

enum DS {
    static let pad: CGFloat = 16
}

/// Full-bleed pastel base behind the onboarding — mirrors the HTML reference's
/// body gradient plus its 30s `bgBreath` drift (background-position 0%→100%
/// over a 200% canvas), so the whole background subtly breathes.
/// Skipped under Reduce Motion (the gradient itself still covers everything).
struct BreathingBackground: View {
    var reduceMotion: Bool
    /// Seconds per breath cycle; `nil` (or Reduce Motion) keeps the gradient
    /// static while still covering the whole background.
    var cycle: Double? = 30
    @State private var breathe = false

    private let colors = [
        Color(red: 0.992, green: 0.984, blue: 1.0),
        Color(red: 0.965, green: 0.937, blue: 1.0),
        Color(red: 0.992, green: 0.941, blue: 0.965),
        Color(red: 0.961, green: 0.973, blue: 1.0)
    ]

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
struct EmptyStateView: View {
    let symbol: String; let title: String; let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}
