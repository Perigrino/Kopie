import SwiftUI

/// The capsule that confirms a click did something. The `warning` variant
/// carries the reason a *paste* could not happen — without it a click that
/// stages the clipboard but can't deliver it looks exactly like a dead click.
///
/// Spec (`.toast`): gap 7 · padding 8×14 · pill · tinted blur · hairline
/// border · deep toast-shadow · 13px/500 text; the icon takes `--ok`/`--warn`
/// and the action takes the accent ink at 600.
struct CopiedToast: View {
    var text: String = "Copied"
    var warning: Bool = false
    /// Optional trailing action — used to jump straight to the System Settings
    /// pane a missing permission lives in, so the message tells the user where
    /// to go instead of only what is wrong.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    /// `--toast-bg` — a purple-dark glass in dark mode, near-white in light.
    private var toastTint: Color {
        scheme == .dark ? Color(red: 34 / 255, green: 32 / 255, blue: 42 / 255)
            : Color.white
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(warning ? Theme.warn(for: scheme) : Theme.ok(for: scheme))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            if let actionTitle, let action {
                Rectangle()
                    .fill(Theme.hairline(for: scheme))
                    .frame(width: 1, height: 14)
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentInk(for: scheme))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(toastTint.opacity(scheme == .dark ? 0.88 : 0.94)))
        }
        .overlay {
            Capsule().strokeBorder(Theme.hairline(for: scheme), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.45 : 0.15), radius: 15, x: 0, y: 6)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
