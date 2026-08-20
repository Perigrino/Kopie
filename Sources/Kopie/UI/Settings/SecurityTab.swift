import SwiftUI
import KopieCore

/// Settings tab explaining at-rest encryption and offering a typed-confirmation
/// wipe of all history.
struct SettingsSecurityTab: View {
    @EnvironmentObject var state: AppState
    @State private var showClearAllConfirm = false

    private var active: Bool { state.store.encryptionAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("At-rest Encryption").font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: active ? "lock.shield.fill" : "lock.shield")
                        .font(.system(size: 16))
                        .foregroundStyle(active ? Color.green : Color.secondary)
                    Text(active ? "Active" : "Not available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(active ? Color.green : Color.secondary)
                }
                Text(active
                     ? "Copied text and images are stored encrypted (AES-256-GCM) on disk, so clipboard history can't be read from the files. The key lives in your login Keychain and only your user account can use it."
                     : "A Keychain encryption key couldn't be created, so history is being stored in plaintext. Try unlocking your Keychain and relaunching Kopie.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Keychain key").font(.headline).padding(.top, 6)
                Text("On first use, Kopie generates a random 256-bit key and stores it as a Keychain item (com.kopie.app / history-encryption-key). The key never touches disk outside the Keychain, which is why encryption can't be turned off without deleting your history — and why the key isn't exposed here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Encrypted search").font(.headline).padding(.top, 6)
                Text("Search matches against keyed hashes of text fragments stored in the index, so searching never decrypts your full history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 6)

                HStack {
                    Button("Clear All Data…", role: .destructive) { showClearAllConfirm = true }
                    Spacer()
                }
                Text("Permanently removes every saved clipboard item and stored image. Type \"clear\" to confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .sheet(isPresented: $showClearAllConfirm) {
            ConfirmDialog(
                title: "Clear all data?",
                message: "This permanently removes every saved clipboard item and stored image file. This cannot be undone.",
                confirmTitle: "Clear All",
                destructive: true,
                requiresTyping: "clear",
                onConfirm: { state.clearAllData(); showClearAllConfirm = false },
                onCancel: { showClearAllConfirm = false })
        }
    }
}
