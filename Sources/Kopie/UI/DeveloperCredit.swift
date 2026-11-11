import SwiftUI

/// The running app's marketing version and build number, read from the bundle
/// so they can never drift from what `scripts/build.sh` stamped into
/// `Info.plist`. Headless runs (bare binary, `swift test`) have no bundle
/// metadata, hence the dash rather than a made-up version.
enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

/// The quiet personal signature: "Made with ♥ by Perigrino".
///
/// Deliberately one line, tertiary, 10pt — it should read as a maker's mark
/// tucked into a corner, never as a footer bar. No fill, no stroke, no
/// background; it inherits whatever canvas it is placed on and resolves
/// correctly in both Ember appearances.
struct DeveloperCredit: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            Text("Made with")
            Image(systemName: "heart.fill")
                // The one warm pixel in the line: accent at low strength so it
                // reads as a tint, not a badge.
                .font(.system(size: 8))
                .foregroundStyle(Theme.accent.opacity(scheme == .dark ? 0.65 : 0.55))
            Text("by Perigrino")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Theme.textTertiary(for: scheme))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Made with love by Perigrino")
        .help("Kopie is made by Perigrino")
    }
}
