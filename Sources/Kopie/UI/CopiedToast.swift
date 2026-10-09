import SwiftUI

/// The capsule that confirms a click did something. The `warning` variant
/// carries the reason a *paste* could not happen — without it a click that
/// stages the clipboard but can't deliver it looks exactly like a dead click.
struct CopiedToast: View {
    var text: String = "Copied"
    var warning: Bool = false
    /// Optional trailing action — used to jump straight to the System Settings
    /// pane a missing permission lives in, so the message tells the user where
    /// to go instead of only what is wrong.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(warning ? Color.orange : Color.green)
            Text(text).font(.callout.weight(.medium))
            if let actionTitle, let action {
                Divider().frame(height: 14)
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
