import SwiftUI

struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var destructive: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: destructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(destructive ? Color.red : Color.accentColor)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? Color.red : Color.accentColor)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320)
    }
}
