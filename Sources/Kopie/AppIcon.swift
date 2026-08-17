import AppKit

/// Central access to the app icon (AppIcon.icns inside the bundle's Resources).
/// To change the icon everywhere, replace `assets/icon-sources/Kopie.icns`
/// (run `swift scripts/icon-sources/generate-icons-glass.swift`, copy the chosen
/// design over Kopie.icns) and rebuild — no code changes needed anywhere.
enum AppIcon {
    /// The full-color icon at a given point size (16 = menu bar, 18–22 = headers).
    static func image(pointSize: CGFloat) -> NSImage {
        if let icon = NSImage(named: "AppIcon") {
            let sized = icon.copy() as? NSImage ?? icon
            sized.size = NSSize(width: pointSize, height: pointSize)
            return sized
        }
        return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Kopie") ?? NSImage()
    }

    /// Menu-bar icon: the monochrome template glyph, tinted automatically for
    /// light/dark menu bars. Falls back to the full-color icon if missing.
    static func menuBarImage() -> NSImage {
        if let glyph = NSImage(named: "KopieMenuTemplate") {
            glyph.isTemplate = true
            glyph.size = NSSize(width: 18, height: 18)
            return glyph
        }
        return image(pointSize: 16)
    }
}
