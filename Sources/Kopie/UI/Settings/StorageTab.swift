import SwiftUI

struct SettingsStorageTab: View {
    @EnvironmentObject var state: AppState
    @State private var showClearCacheConfirm = false
    @State private var showClearAllConfirm = false
    @State private var stats: (count: Int64, bytes: Int64) = (0, 0)
    @State private var showExportAlert = false
    @State private var showImportAlert = false
    @State private var alertMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Clipboard Items").font(.headline)
                    Text("\(stats.count)").font(.largeTitle.monospacedDigit())
                    Text("Storage Used").font(.headline).padding(.top, 8)
                    Text(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))
                        .font(.largeTitle.monospacedDigit())
                }
                if let err = state.storageError {
                    Label("Storage error: \(err)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                Divider()
                HStack {
                    Button("Clear Cache…") { showClearCacheConfirm = true }
                    Spacer()
                    Button("Clear All Data…", role: .destructive) { showClearAllConfirm = true }
                }
                Text("Clear Cache removes regenerable thumbnails. Clear All Data removes every item and file.")
                    .font(.caption).foregroundStyle(.secondary)
                
                Divider()
                
                Group {
                    Text("Export / Import").font(.headline)
                    HStack {
                        Button("Export History…") { showExportPanel() }
                        Button("Import History…") { showImportPanel() }
                    }
                    Text("Export saves all clipboard items to a JSON file. Import adds items from a JSON file, skipping duplicates.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear { stats = state.storageStats() }
        .onChange(of: state.items.count) { _ in stats = state.storageStats() }
        .sheet(isPresented: $showClearCacheConfirm) {
            ConfirmDialog(
                title: "Clear cache?",
                message: "Thumbnails will be removed and regenerated on demand. Your clipboard history is untouched.",
                confirmTitle: "Clear Cache",
                onConfirm: { state.clearCache(); stats = state.storageStats(); showClearCacheConfirm = false },
                onCancel: { showClearCacheConfirm = false })
        }
        .sheet(isPresented: $showClearAllConfirm) {
            ConfirmDialog(
                title: "Clear all data?",
                message: "This permanently removes every saved clipboard item and stored image. This action cannot be undone.",
                confirmTitle: "Clear All", destructive: true,
                onConfirm: { state.clearAllData(); stats = state.storageStats(); showClearAllConfirm = false },
                onCancel: { showClearAllConfirm = false })
        }
    }
    
    private func showExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Clipboard History"
        panel.nameFieldStringValue = "kopie-history-\(DateFormatter.exportDateFormatter.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        state.exportHistory(to: url)
    }
    
    private func showImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Clipboard History"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        state.importHistory(from: url)
    }
}

private extension DateFormatter {
    static let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()}
