import SwiftUI
import KopieCore

/// Builds context menus for clipboard items, reusable across HistoryRow, PopoverView, and DetailsPanel.
struct ContextMenuBuilder: View {
    let item: ClipboardItem
    var onCopy: () -> Void
    var onRemove: () -> Void
    var onFavorite: () -> Void
    var onPin: () -> Void
    
    var body: some View {
        // Primary actions
        Button(action: onCopy) {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: .command)
        
        Divider()
        
        // Pin/Unpin
        Button(action: onPin) {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.fill" : "pin")
        }
        .keyboardShortcut("p", modifiers: .command)
        
        // Favorite/Unfavorite
        Button(action: onFavorite) {
            Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.fill" : "star")
        }
        .keyboardShortcut("f", modifiers: .command)
        
        Divider()
        
        // Smart actions based on content type
        if item.kind == .text, let text = item.text {
            if let url = URL(string: text), (url.scheme == "http" || url.scheme == "https") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open URL", systemImage: "safari")
                }
            }
            
            if case .email = ContentDetector.detectContentType(text) {
                Button {
                    if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let mailURL = URL(string: "mailto:\(encoded)") {
                        NSWorkspace.shared.open(mailURL)
                    }
                } label: {
                    Label("Compose Email", systemImage: "envelope")
                }
            }
            
            if case .phoneNumber = ContentDetector.detectContentType(text) {
                Button {
                    let cleaned = text.filter { $0.isNumber || $0 == "+" }
                    if let phoneURL = URL(string: "tel:\(cleaned)") {
                        NSWorkspace.shared.open(phoneURL)
                    }
                } label: {
                    Label("Call", systemImage: "phone")
                }
            }
        }
        
        if item.kind == .file, let paths = item.filePaths, let firstPath = paths.first {
            Button {
                NSWorkspace.shared.selectFile(firstPath, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        
        Divider()
        
        // Delete
        Button(role: .destructive, action: onRemove) {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [])
    }
}
