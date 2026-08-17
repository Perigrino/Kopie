import AppKit
import Foundation

let size: CGFloat = 1024

func squircle(_ rect: NSRect, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

func fillGradient(_ colors: [NSColor], in rect: NSRect, angle: CGFloat = 270) {
    let grad = NSGradient(colors: colors)!
    grad.draw(in: rect, angle: angle)
}

// MARK: - Liquid Glass toolkit

/// Glass squircle: vertical gradient + bottom depth + top specular sweep + soft rims.
func drawGlassBase(_ top: NSColor, _ bottom: NSColor) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = squircle(rect, 232)
    path.addClip()

    fillGradient([top, bottom], in: rect, angle: 270)

    // Bottom depth (light sinks toward the edge).
    let depth = NSGradient(colors: [
        NSColor.black.withAlphaComponent(0.0),
        NSColor.black.withAlphaComponent(0.28),
    ])!
    depth.draw(from: NSPoint(x: 0, y: size * 0.55), to: NSPoint(x: 0, y: 0), options: [])

    // Top specular sweep (the "liquid" highlight).
    let sweep = NSBezierPath(ovalIn: NSRect(x: -size * 0.12, y: size * 0.80, width: size * 1.24, height: size * 0.30))
    let sweepGrad = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.50),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    sweepGrad.draw(from: NSPoint(x: 0, y: size * 0.98), to: NSPoint(x: 0, y: size * 0.78), options: [])
    _ = sweep

    // Left-edge sheen.
    let sheen = NSBezierPath(ovalIn: NSRect(x: -size * 0.20, y: size * 0.30, width: size * 0.36, height: size * 0.55))
    let sheenGrad = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    sheenGrad.draw(from: NSPoint(x: size * 0.05, y: size * 0.85), to: NSPoint(x: size * 0.05, y: size * 0.30), options: [])
    _ = sheen

    // Light rim on the upper edge, faint dark rim at the bottom.
    let lightRim = squircle(rect.insetBy(dx: 3, dy: 3), 229)
    lightRim.lineWidth = 6
    NSColor.white.withAlphaComponent(0.30).setStroke()
    lightRim.stroke()

    let darkRim = squircle(rect.insetBy(dx: 7, dy: 7), 225)
    darkRim.lineWidth = 12
    NSColor.black.withAlphaComponent(0.14).setStroke()
    darkRim.stroke()
}

/// A translucent "glass card" for the subject, with its own top highlight.
func drawGlassCard(_ rect: NSRect, radius: CGFloat, fill: NSColor, rim: NSColor) {
    let path = squircle(rect, radius)
    fill.set()
    path.fill()
    path.addClip()
    let hl = NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.maxY - rect.height * 0.34, width: rect.width * 1.4, height: rect.height * 0.30))
    let hlGrad = NSGradient(colors: [NSColor.white.withAlphaComponent(0.42), NSColor.white.withAlphaComponent(0.0)])!
    hlGrad.draw(from: NSPoint(x: rect.midX, y: rect.maxY), to: NSPoint(x: rect.midX, y: rect.maxY - rect.height * 0.4), options: [])
    _ = hl
    rim.withAlphaComponent(0.55).setStroke()
    let rimPath = squircle(rect, radius)
    rimPath.lineWidth = 3
    rimPath.stroke()
}

func drawGlassLines(_ color: NSColor, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, count: Int, gap: CGFloat) {
    color.set()
    let lineH: CGFloat = h * 0.05
    for i in 0..<count {
        let lineY = y + h - (CGFloat(i + 1) * (lineH + gap))
        let lineW = w * (i == count - 1 ? 0.42 : 1.0)
        let path = NSBezierPath(roundedRect: NSRect(x: x + (i == count - 1 ? (w - lineW) / 2 : 0), y: lineY, width: lineW, height: lineH), xRadius: lineH / 2, yRadius: lineH / 2)
        path.fill()
    }
}

func drawStar(_ color: NSColor, at center: NSPoint, radius: CGFloat) {
    color.set()
    let path = NSBezierPath()
    for i in 0..<10 {
        let r = i % 2 == 0 ? radius : radius * 0.45
        let angle = -CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 5
        let p = NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    path.fill()
}

func drawClip(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, color: NSColor) {
    let clip = squircle(NSRect(x: x, y: y, width: w, height: h), h * 0.4)
    color.set()
    clip.fill()
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

// MARK: - Designs (Liquid Glass)

// 6. Glass Clipboard — blue glass, frosted clipboard with glass lines.
func design6() {
    drawGlassBase(NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.98, alpha: 1),
                  NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.82, alpha: 1))
    let w: CGFloat = 520, h: CGFloat = 620
    let x = (size - w) / 2, y = (size - h) / 2
    drawGlassCard(NSRect(x: x, y: y, width: w, height: h), radius: 70,
                  fill: NSColor.white.withAlphaComponent(0.86),
                  rim: NSColor.white)
    drawGlassLines(NSColor(calibratedRed: 0.45, green: 0.55, blue: 0.75, alpha: 0.9),
                   x: x + 76, y: y + 110, w: w - 152, h: h - 190, count: 4, gap: 28)
    drawClip(x + w * 0.20, y + h - 84, w * 0.60, 96, color: NSColor.white.withAlphaComponent(0.95))
    drawStar(NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.15, alpha: 1), at: NSPoint(x: x + w - 96, y: y + h - 104), radius: 64)
}

// 7. Glass K — dark glass monogram.
func design7() {
    drawGlassBase(NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.30, alpha: 1),
                  NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.12, alpha: 1))
    let grad = NSGradient(colors: [NSColor(calibratedRed: 0.45, green: 0.70, blue: 1.0, alpha: 1),
                                   NSColor(calibratedRed: 0.70, green: 0.50, blue: 1.0, alpha: 1)])!
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 640, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "K", attributes: attrs)
    let strSize = str.size()
    str.draw(at: NSPoint(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2 - 30))
    let underline = squircle(NSRect(x: (size - 480) / 2, y: 150, width: 480, height: 44), 22)
    grad.draw(in: underline.bounds, angle: 270)
    underline.fill()
}

// 8. Glass Stack — teal glass, overlapping frosted sheets + spark.
func design8() {
    drawGlassBase(NSColor(calibratedRed: 0.05, green: 0.68, blue: 0.62, alpha: 1),
                  NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.42, alpha: 1))
    drawGlassCard(NSRect(x: 170, y: 205, width: 500, height: 600), radius: 58,
                  fill: NSColor.white.withAlphaComponent(0.45),
                  rim: NSColor.white)
    drawGlassCard(NSRect(x: 320, y: 175, width: 540, height: 620), radius: 60,
                  fill: NSColor.white.withAlphaComponent(0.88),
                  rim: NSColor.white)
    drawGlassLines(NSColor(calibratedRed: 0.35, green: 0.60, blue: 0.58, alpha: 0.9),
                   x: 396, y: 238, w: 390, h: 480, count: 4, gap: 26)
    let badge = NSBezierPath(ovalIn: NSRect(x: 205, y: 645, width: 215, height: 215))
    NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.15, alpha: 1).set()
    badge.fill()
    drawStar(NSColor.white, at: NSPoint(x: 312, y: 752), radius: 56)
}

// 9. Glass Rainbow — indigo glass, white doc with vivid lines.
func design9() {
    drawGlassBase(NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.90, alpha: 1),
                  NSColor(calibratedRed: 0.26, green: 0.18, blue: 0.62, alpha: 1))
    let w: CGFloat = 560, h: CGFloat = 640
    let x = (size - w) / 2, y = (size - h) / 2
    drawGlassCard(NSRect(x: x, y: y, width: w, height: h), radius: 60,
                  fill: NSColor.white.withAlphaComponent(0.92),
                  rim: NSColor.white)
    let colors = [NSColor.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
    let lineH: CGFloat = 44, gap: CGFloat = 24
    for i in 0..<6 {
        colors[i].set()
        let lineY = y + h - 108 - CGFloat(i) * (lineH + gap)
        let lineW = w * (i == 5 ? 0.48 : 0.74)
        let path = NSBezierPath(roundedRect: NSRect(x: x + (i == 5 ? (w - lineW) / 2 : 66), y: lineY, width: lineW, height: lineH), xRadius: lineH / 2, yRadius: lineH / 2)
        path.fill()
    }
}

// 10. Glass Spark — coral glass, outlined clipboard + white star.
func design10() {
    drawGlassBase(NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.38, alpha: 1),
                  NSColor(calibratedRed: 0.85, green: 0.24, blue: 0.40, alpha: 1))
    let w: CGFloat = 500, h: CGFloat = 620
    let x = (size - w) / 2, y = (size - h) / 2
    let body = squircle(NSRect(x: x, y: y, width: w, height: h), 88)
    NSColor.white.withAlphaComponent(0.94).set()
    body.fill()
    let inner = squircle(NSRect(x: x + 44, y: y + 44, width: w - 88, height: h - 108), 56)
    NSColor(calibratedRed: 0.85, green: 0.30, blue: 0.42, alpha: 1).set()
    inner.lineWidth = 22
    inner.stroke()
    drawClip(x + w * 0.20, y + h - 92, w * 0.60, 100, color: NSColor(calibratedRed: 0.85, green: 0.30, blue: 0.42, alpha: 1))
    drawStar(NSColor.white, at: NSPoint(x: x + w - 120, y: y + 140), radius: 64)
}

// 11. Glass Clock — retention/history, blue glass clock with circular arrow.
func design11() {
    drawGlassBase(NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.85, alpha: 1),
                  NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.58, alpha: 1))
    let c = NSPoint(x: size / 2, y: size / 2)
    let r: CGFloat = 300
    let face = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    NSColor.white.withAlphaComponent(0.92).set()
    face.fill()
    let rim = NSBezierPath(ovalIn: NSRect(x: c.x - r + 26, y: c.y - r + 26, width: (r - 26) * 2, height: (r - 26) * 2))
    rim.lineWidth = 20
    NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.68, alpha: 1).setStroke()
    rim.stroke()
    // Hands
    let hand = NSBezierPath()
    hand.move(to: c)
    hand.line(to: NSPoint(x: c.x, y: c.y + r * 0.52))
    hand.lineWidth = 30
    hand.lineCapStyle = .round
    NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.68, alpha: 1).setStroke()
    hand.stroke()
    let hand2 = NSBezierPath()
    hand2.move(to: c)
    hand2.line(to: NSPoint(x: c.x + r * 0.42, y: c.y - r * 0.18))
    hand2.lineWidth = 30
    hand2.lineCapStyle = .round
    hand2.stroke()
    // Circular arrow
    let arrow = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.72, y: c.y + r * 0.30, width: r * 0.5, height: r * 0.5))
    arrow.lineWidth = 18
    NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.15, alpha: 1).setStroke()
    arrow.stroke()
    drawStar(NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.15, alpha: 1), at: NSPoint(x: c.x + r * 0.52, y: c.y + r * 0.56), radius: 60)
}

// 12. Glass Heart — favorites, rose glass heart.
func design12() {
    drawGlassBase(NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.55, alpha: 1),
                  NSColor(calibratedRed: 0.80, green: 0.16, blue: 0.38, alpha: 1))
    let c = NSPoint(x: size / 2, y: size / 2)
    let s: CGFloat = 500
    let path = NSBezierPath()
    path.move(to: NSPoint(x: c.x, y: c.y - s * 0.32))
    path.curve(to: NSPoint(x: c.x - s * 0.55, y: c.y + s * 0.02),
               controlPoint1: NSPoint(x: c.x, y: c.y - s * 0.02),
               controlPoint2: NSPoint(x: c.x - s * 0.55, y: c.y - s * 0.30))
    path.curve(to: NSPoint(x: c.x - s * 0.30, y: c.y + s * 0.48),
               controlPoint1: NSPoint(x: c.x - s * 0.72, y: c.y + s * 0.30),
               controlPoint2: NSPoint(x: c.x - s * 0.55, y: c.y + s * 0.48))
    path.curve(to: NSPoint(x: c.x, y: c.y + s * 0.30),
               controlPoint1: NSPoint(x: c.x - s * 0.10, y: c.y + s * 0.48),
               controlPoint2: NSPoint(x: c.x, y: c.y + s * 0.40))
    path.curve(to: NSPoint(x: c.x + s * 0.30, y: c.y + s * 0.48),
               controlPoint1: NSPoint(x: c.x, y: c.y + s * 0.40),
               controlPoint2: NSPoint(x: c.x + s * 0.10, y: c.y + s * 0.48))
    path.curve(to: NSPoint(x: c.x + s * 0.55, y: c.y + s * 0.02),
               controlPoint1: NSPoint(x: c.x + s * 0.55, y: c.y + s * 0.48),
               controlPoint2: NSPoint(x: c.x + s * 0.72, y: c.y + s * 0.30))
    path.curve(to: NSPoint(x: c.x, y: c.y - s * 0.32),
               controlPoint1: NSPoint(x: c.x + s * 0.55, y: c.y - s * 0.30),
               controlPoint2: NSPoint(x: c.x, y: c.y - s * 0.02))
    path.close()
    let grad = NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.82, alpha: 1),
                                   NSColor(calibratedRed: 0.96, green: 0.30, blue: 0.48, alpha: 1)])!
    grad.draw(in: path.bounds, angle: 270)
    path.addClip()
    path.fill()
    // Specular on the heart
    let hl = NSBezierPath(ovalIn: NSRect(x: c.x - s * 0.34, y: c.y + s * 0.06, width: s * 0.34, height: s * 0.22))
    let hlGrad = NSGradient(colors: [NSColor.white.withAlphaComponent(0.6), NSColor.white.withAlphaComponent(0.0)])!
    hlGrad.draw(from: NSPoint(x: c.x, y: c.y + s * 0.28), to: NSPoint(x: c.x, y: c.y + s * 0.06), options: [])
    _ = hl
}

// 13. Glass Bolt — quick-copy, amber glass lightning.
func design13() {
    drawGlassBase(NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.20, alpha: 1),
                  NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.08, alpha: 1))
    let c = NSPoint(x: size / 2, y: size / 2)
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: c.x + 90, y: c.y + 340))
    bolt.line(to: NSPoint(x: c.x - 230, y: c.y + 60))
    bolt.line(to: NSPoint(x: c.x - 40, y: c.y + 60))
    bolt.line(to: NSPoint(x: c.x - 90, y: c.y - 340))
    bolt.line(to: NSPoint(x: c.x + 230, y: c.y - 60))
    bolt.line(to: NSPoint(x: c.x + 40, y: c.y - 60))
    bolt.close()
    let grad = NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.65, alpha: 1),
                                   NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.25, alpha: 1)])!
    grad.draw(in: bolt.bounds, angle: 270)
    bolt.fill()
    bolt.lineWidth = 10
    NSColor.white.withAlphaComponent(0.6).setStroke()
    bolt.stroke()
}

// 14. Glass Gear — settings, graphite glass gear.
func design14() {
    drawGlassBase(NSColor(calibratedRed: 0.44, green: 0.48, blue: 0.58, alpha: 1),
                  NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1))
    let c = NSPoint(x: size / 2, y: size / 2)
    let r: CGFloat = 260
    let transform = NSAffineTransform()
    // Teeth
    let teeth = NSBezierPath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        let tooth = squircle(NSRect(x: c.x - 46, y: c.y + r - 40, width: 92, height: 120), 20)
        transform.translateX(by: c.x, yBy: c.y)
        transform.rotate(byRadians: angle)
        transform.translateX(by: -c.x, yBy: -c.y)
        teeth.append(transform.transform(to: NSBezierPath(roundedRect: NSRect(x: c.x - 46, y: c.y + r - 40, width: 92, height: 120), xRadius: 20, yRadius: 20)))
        transform.rotate(byRadians: -angle)
    }
    let grad = NSGradient(colors: [NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.78, alpha: 1),
                                   NSColor(calibratedRed: 0.30, green: 0.33, blue: 0.42, alpha: 1)])!
    grad.draw(in: teeth.bounds, angle: 270)
    teeth.fill()
    let body = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    grad.draw(in: body.bounds, angle: 270)
    body.fill()
    let hole = NSBezierPath(ovalIn: NSRect(x: c.x - 80, y: c.y - 80, width: 160, height: 160))
    drawGlassBase(NSColor(calibratedRed: 0.44, green: 0.48, blue: 0.58, alpha: 1), NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1))
    // redraw a dark hole
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.16, alpha: 1).set()
    hole.fill()
    _ = transform
}

// 15. Glass Mirror — two mirrored panes (copy/paste), violet glass.
func design15() {
    drawGlassBase(NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.95, alpha: 1),
                  NSColor(calibratedRed: 0.30, green: 0.20, blue: 0.70, alpha: 1))
    // Back pane
    drawGlassCard(NSRect(x: 210, y: 250, width: 430, height: 540), radius: 54,
                  fill: NSColor.white.withAlphaComponent(0.42),
                  rim: NSColor.white)
    // Front pane
    drawGlassCard(NSRect(x: 390, y: 230, width: 430, height: 560), radius: 54,
                  fill: NSColor.white.withAlphaComponent(0.88),
                  rim: NSColor.white)
    drawGlassLines(NSColor(calibratedRed: 0.48, green: 0.42, blue: 0.72, alpha: 0.9),
                   x: 448, y: 292, w: 314, h: 430, count: 3, gap: 30)
    // Plus badge on the front pane
    let badge = NSBezierPath(ovalIn: NSRect(x: 690, y: 620, width: 180, height: 180))
    NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.25, alpha: 1).set()
    badge.fill()
    let plus = NSBezierPath()
    plus.appendRect(NSRect(x: 748, y: 668, width: 64, height: 84))
    plus.appendRect(NSRect(x: 738, y: 678, width: 84, height: 64))
    plus.windingRule = .evenOdd
    NSColor.white.set()
    plus.fill()
}

// MARK: - Main

try render("design6") { design6() }
try render("design7") { design7() }
try render("design8") { design8() }
try render("design9") { design9() }
try render("design10") { design10() }
try render("design11") { design11() }
try render("design12") { design12() }
try render("design13") { design13() }
try render("design14") { design14() }
try render("design15") { design15() }
print("done")
