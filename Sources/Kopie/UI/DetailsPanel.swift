import SwiftUI
import KopieCore
import AppKit

struct DetailsPanel: View {
    let item: ClipboardItem
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.typeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
            metaGrid
            actions
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        if item.kind == .text {
            ScrollView {
                Text(item.text ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if item.kind == .file {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(path)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let thumb = state.thumbnail(for: item) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text("The image file could not be loaded."))
        }
    }

    private var metaGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow { meta("Copied", item.createdAt.formatted(date: .abbreviated, time: .standard)) }
            if item.kind == .text, let c = item.charCount { GridRow { meta("Characters", "\(c)") } }
            if item.kind == .file, let n = item.filePaths?.count { GridRow { meta("Files", "\(n)") } }
            if item.kind == .image, let d = item.dimensionLabel { GridRow { meta("Dimensions", d) } }
            GridRow { meta("Size", ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file)) }
            if item.isFavorite { GridRow { meta("Favorite", "Yes") } }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meta(_ label: String, _ value: String) -> some View {
        Group {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
        }
        .font(.caption)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                state.copyBack(item)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)

            Button {
                state.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                state.remove(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}
