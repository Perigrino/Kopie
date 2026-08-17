import SwiftUI

struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var destructive: Bool = false
    /// When set, the user must type this phrase to enable the confirm button.
    var requiresTyping: String? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var typed = ""

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
            if let phrase = requiresTyping {
                TextField("Type “\(phrase)” to confirm", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { if typed == phrase { onConfirm() } }
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? Color.red : Color.accentColor)
                    .disabled(requiresTyping.map { typed != $0 } ?? false)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320)
    }
}
