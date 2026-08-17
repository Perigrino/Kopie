import AppKit
import Foundation

/// Renders the Glass Spark clipboard (design10) as a black-on-transparent
/// template glyph — AppKit tints it automatically for light/dark menu bars.
let renderSize: CGFloat = 128
let scale = renderSize / 1024.0

func sq(_ rect: NSRect, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

func starPath(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let inner = radius * 0.45
    for i in 0..<10 {
        let r = i % 2 == 0 ? radius : inner
        let angle = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 5
        let pt = NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
    }
    path.close()
    return path
}

let image = NSImage(size: NSSize(width: renderSize, height: renderSize))
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.black.set()

// Same geometry as design10 (coral Glass Spark), monochrome:
let w: CGFloat = 500 * scale, h: CGFloat = 620 * scale
let x = (renderSize - w) / 2, y = (renderSize - h) / 2

// Outlined clipboard: outer squircle filled, inner punched out.
let body = sq(NSRect(x: x, y: y, width: w, height: h), 88 * scale)
let inner = sq(NSRect(x: x + 44 * scale, y: y + 44 * scale,
                      width: w - 88 * scale, height: h - 108 * scale), 56 * scale)
body.append(inner)
body.windingRule = .evenOdd
body.fill()

// Clip bar near the top.
sq(NSRect(x: x + w * 0.20, y: y + h - 92 * scale, width: w * 0.60, height: 100 * scale), 50 * scale).fill()

// Star badge.
starPath(center: NSPoint(x: x + w - 120 * scale, y: y + 140 * scale), radius: 64 * scale).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
let outDir = URL(fileURLWithPath: "assets/icon-sources", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let out = outDir.appendingPathComponent("KopieMenuTemplate.png")
try png.write(to: out)
print("wrote \(out.path) (\(png.count) bytes)")
