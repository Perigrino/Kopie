import SwiftUI

/// Themed confirmation per the prototype's "confirm dialog with
/// `.btn.danger`" state: icon tile, 14/600 title, 12pt message, ghost Cancel
/// and a danger / primary pill confirm. All behaviour (typing gate,
/// keyboard shortcuts) is unchanged.
struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var destructive: Bool = false
    /// When set, the user must type this phrase to enable the confirm button.
    var requiresTyping: String? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 14) {
            iconTile
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let phrase = requiresTyping {
                TextField("Type “\(phrase)” to confirm", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary(for: scheme))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldBackground(for: scheme)))
                    .overlay { if scheme == .light { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline(for: scheme)) } }
                    .frame(width: 240)
                    .onSubmit { if typed == phrase { onConfirm() } }
            }
            HStack(spacing: 8) {
                EmberGhostButton(title: "Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                confirmButton
                    .keyboardShortcut(.defaultAction)
                    .disabled(requiresTyping.map { typed != $0 } ?? false)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
        .background(Theme.winBackground(for: scheme))
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            .fill(destructive
                  ? AnyShapeStyle(Theme.danger(for: scheme).opacity(0.16))
                  : AnyShapeStyle(Theme.accentSoft(for: scheme)))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: destructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(destructive ? Theme.danger(for: scheme) : Theme.accentInk(for: scheme))
            }
    }

    @ViewBuilder private var confirmButton: some View {
        if destructive {
            Button(action: onConfirm) {
                Text(confirmTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.danger(for: scheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.danger(for: scheme).opacity(0.16)))
            }
            .buttonStyle(.plain)
        } else {
            EmberPrimaryButton(title: confirmTitle, action: onConfirm)
        }
    }
}
