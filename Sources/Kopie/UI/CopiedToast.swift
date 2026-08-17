import SwiftUI

struct CopiedToast: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Copied").font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
