import AppKit
import Foundation

// MARK: - Drawing helpers

let size: CGFloat = 1024

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

func fillGradient(_ colors: [NSColor], in rect: NSRect, vertical: Bool = true) {
    let grad = NSGradient(colors: colors)!
    let start = vertical ? NSPoint(x: rect.midX, y: rect.maxY) : NSPoint(x: rect.minX, y: rect.midY)
    let end = vertical ? NSPoint(x: rect.midX, y: rect.minY) : NSPoint(x: rect.maxX, y: rect.midY)
    grad.draw(in: rect, angle: vertical ? 270 : 0)
    _ = start; _ = end
}

/// Standard macOS squircle base.
func drawBase(_ colors: [NSColor]) {
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 230, yRadius: 230)
    fillGradient(colors, in: bg.bounds)
    bg.addClip()
}

func drawClipboardBody(_ fill: NSColor, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat) {
    // Paper
    let body = roundedRect(x, y, w, h, radius)
    fill.set()
    body.fill()
    // Clip
    let clipH: CGFloat = h * 0.16
    let clip = roundedRect(x + w * 0.18, y + h - clipH * 0.55, w * 0.64, clipH, clipH * 0.4)
    fill.set()
    clip.fill()
}

func drawLines(_ color: NSColor, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, count: Int, gap: CGFloat) {
    color.set()
    let lineH: CGFloat = h * 0.045
    for i in 0..<count {
        let lineY = y + h - (CGFloat(i + 1) * (lineH + gap))
        let lineW = w * (i == count - 1 ? 0.45 : 1.0)
        let path = NSBezierPath(roundedRect: NSRect(x: x + (i == count - 1 ? (w - lineW) / 2 : 0), y: lineY, width: lineW, height: lineH), xRadius: lineH / 2, yRadius: lineH / 2)
        path.fill()
    }
}

func drawStar(_ color: NSColor, at center: NSPoint, radius: CGFloat) {
    color.set()
    let path = NSBezierPath()
    let points = 5
    for i in 0..<(points * 2) {
        let r = i % 2 == 0 ? radius : radius * 0.45
        let angle = -CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / CGFloat(points)
        let p = NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    path.fill()
}

func render(_ name: String, _ draw: () -> Void) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icons", code: 1)
    }
    let outDir = URL(fileURLWithPath: "assets/icon-sources", isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try png.write(to: outDir.appendingPathComponent("\(name).png"))
    try buildIconset(name: name, png: png)
    print("generated \(name).png")
}

func buildIconset(name: String, png: Data) throws {
    let base = URL(fileURLWithPath: "assets/icon-sources")
    let iconset = base.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let image = NSImage(data: png)!
    let specs: [(String, CGFloat)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for (filename, px) in specs {
        let resized = NSImage(size: NSSize(width: px, height: px))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        resized.unlockFocus()
        guard let t = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: t),
              let out = rep.representation(using: .png, properties: [:]) else { continue }
        try out.write(to: iconset.appendingPathComponent(filename))
    }
    let icns = base.appendingPathComponent("\(name).icns")
    try? FileManager.default.removeItem(at: icns)
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try proc.run()
    proc.waitUntilExit()
}

// MARK: - Designs

// 1. "Classic Clipboard" — blue gradient squircle, white clipboard + clip, gray lines.
func design1() {
    drawBase([NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.98, alpha: 1),
              NSColor(calibratedRed: 0.30, green: 0.60, blue: 1.00, alpha: 1)])
    let w: CGFloat = 520, h: CGFloat = 640
    let x = (size - w) / 2, y = (size - h) / 2
    drawClipboardBody(.white, x: x, y: y, w: w, h: h, radius: 70)
    drawLines(NSColor(calibratedRed: 0.72, green: 0.78, blue: 0.86, alpha: 1), x: x + 80, y: y + 120, w: w - 160, h: h - 190, count: 4, gap: 30)
    drawStar(NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.0, alpha: 1), at: NSPoint(x: x + w - 100, y: y + h - 110), radius: 70)
}

// 2. "Monogram" — dark slate squircle, bold gradient K, small clipboard hint.
func design2() {
    drawBase([NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.16, alpha: 1),
              NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.26, alpha: 1)])
    let grad = NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 1),
                                   NSColor(calibratedRed: 0.60, green: 0.42, blue: 1.0, alpha: 1)])!
    let kRect = NSRect(x: 130, y: 180, width: 764, height: 664)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 620, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "K", attributes: attrs)
    let strSize = str.size()
    str.draw(at: NSPoint(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2))
    // Clipboard line hint under the K
    let hint = roundedRect((size - 460) / 2, 150, 460, 46, 23)
    grad.draw(in: hint.bounds, angle: 270)
    hint.fill()
    _ = kRect
}

// 3. "Copy Stack" — teal gradient, two overlapping sheets + spark.
func design3() {
    drawBase([NSColor(calibratedRed: 0.0, green: 0.62, blue: 0.58, alpha: 1),
              NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.68, alpha: 1)])
    // Back sheet (offset, slightly darker)
    let back = roundedRect(180, 210, 520, 620, 60)
    NSColor(calibratedRed: 0.95, green: 0.98, blue: 0.98, alpha: 0.55).set()
    back.fill()
    // Front sheet
    let front = roundedRect(320, 180, 540, 640, 60)
    NSColor.white.set()
    front.fill()
    drawLines(NSColor(calibratedRed: 0.60, green: 0.72, blue: 0.72, alpha: 1), x: 390, y: 240, w: 400, h: 500, count: 4, gap: 26)
    // Spark badge
    let badge = NSBezierPath(ovalIn: NSRect(x: 210, y: 660, width: 210, height: 210))
    NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.0, alpha: 1).set()
    badge.fill()
    drawStar(NSColor.white, at: NSPoint(x: 315, y: 765), radius: 55)
}

// 4. "Doc Lines" — indigo gradient, plain white doc, colored lines.
func design4() {
    drawBase([NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.85, alpha: 1),
              NSColor(calibratedRed: 0.55, green: 0.46, blue: 0.95, alpha: 1)])
    let w: CGFloat = 560, h: CGFloat = 660
    let x = (size - w) / 2, y = (size - h) / 2
    let body = roundedRect(x, y, w, h, 60)
    NSColor.white.set()
    body.fill()
    let colors = [NSColor.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
    let lineH: CGFloat = 42, gap: CGFloat = 26
    for i in 0..<6 {
        colors[i].set()
        let lineY = y + h - 110 - CGFloat(i) * (lineH + gap)
        let lineW = w * (i == 5 ? 0.5 : 0.78)
        let path = NSBezierPath(roundedRect: NSRect(x: x + (i == 5 ? (w - lineW) / 2 : 70), y: lineY, width: lineW, height: lineH), xRadius: lineH / 2, yRadius: lineH / 2)
        path.fill()
    }
}

// 5. "Minimal Clip" — soft pink/orange gradient, outline clipboard.
func design5() {
    drawBase([NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.42, alpha: 1),
              NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.55, alpha: 1)])
    let w: CGFloat = 500, h: CGFloat = 640
    let x = (size - w) / 2, y = (size - h) / 2
    let body = roundedRect(x, y, w, h, 90)
    NSColor.white.withAlphaComponent(0.92).set()
    body.fill()
    // Outline inner clip
    let inner = roundedRect(x + 46, y + 46, w - 92, h - 110, 60)
    NSColor(calibratedRed: 0.90, green: 0.34, blue: 0.40, alpha: 1).set()
    inner.lineWidth = 24
    inner.stroke()
    // Clip bar
    let clip = roundedRect(x + w * 0.20, y + h - 90, w * 0.60, 110, 42)
    NSColor(calibratedRed: 0.88, green: 0.30, blue: 0.36, alpha: 1).set()
    clip.fill()
    // Spark
    drawStar(NSColor.white, at: NSPoint(x: x + w - 130, y: y + 150), radius: 72)
}

// MARK: - Main

try render("design1") { design1() }
try render("design2") { design2() }
try render("design3") { design3() }
try render("design4") { design4() }
try render("design5") { design5() }
print("done")
