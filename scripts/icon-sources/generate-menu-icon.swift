import AppKit
import Foundation

/// Generates the Kopie menu-bar (status item) glyph candidates.
///
/// Menu-bar icons are *template* images: macOS discards the colour channel and
/// tints the alpha mask to match the menu label, so legibility cannot come from
/// hue. It has to come from filled mass and silhouette. Every concept below is
/// therefore drawn as solid geometry — the previous `KopieMenuTemplate.png` was
/// a hairline outline that went sub-pixel at 18pt and antialiased into grey.
///
/// Run from the repo root:
///     swift scripts/icon-sources/generate-menu-icon.swift
///
/// Output: assets/menu-icon-sources/{concept}-{style}-{state}@{256,36,18}.png
/// The 36px file is 18pt @2x, the 18px file is 18pt @1x.

import AppKit

let canvas: CGFloat = 256
let center = NSPoint(x: canvas / 2, y: canvas / 2)
/// Half-extent a glyph may use. 112 of 128 leaves ~1pt of padding at 18pt,
/// matching the breathing room system menu-bar icons give themselves.
let half: CGFloat = 112

// MARK: - Drawing primitives

func starPath(centre: NSPoint, radius: CGFloat, points: Int = 5, innerRatio: CGFloat = 0.5) -> NSBezierPath {
    let path = NSBezierPath()
    for i in 0..<(points * 2) {
        let r = i % 2 == 0 ? radius : radius * innerRatio
        let angle = -CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / CGFloat(points)
        let p = NSPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    return path
}

/// A clipboard: solid rounded body with the clip tab straddling the top edge.
func clipboardPath(body: NSRect, tab: NSRect, radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    p.append(NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2))
    return p
}

/// A solid downward arrow — the "paste" verb.
func downArrowPath(x: CGFloat, yTop: CGFloat, yShoulder: CGFloat, yTip: CGFloat,
                   shaftHalf: CGFloat, headHalf: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.lineJoinStyle = .round
    p.move(to: NSPoint(x: x - shaftHalf, y: yTop))
    p.line(to: NSPoint(x: x - shaftHalf, y: yShoulder))
    p.line(to: NSPoint(x: x - headHalf, y: yShoulder))
    p.line(to: NSPoint(x: x, y: yTip))
    p.line(to: NSPoint(x: x + headHalf, y: yShoulder))
    p.line(to: NSPoint(x: x + shaftHalf, y: yShoulder))
    p.line(to: NSPoint(x: x + shaftHalf, y: yTop))
    p.close()
    return p
}

/// The ⌘ cloverleaf: four rings at the corners of a square, joined by a cross
/// whose arms run out to the bounding box. Solid parts are returned as two
/// paths because NSBezierPath carries a single winding rule and a ring needs
/// even-odd to punch its own hole.
func commandPaths(centre: NSPoint, half: CGFloat) -> (bars: NSBezierPath, rings: [NSBezierPath]) {
    let d = 0.56 * half      // ring centre offset from the glyph centre
    let r = 0.46 * half      // ring outer radius
    let t = 0.13 * half      // half-thickness of the cross bars
    let ringWidth = 0.22 * half

    let bars = NSBezierPath()
    bars.append(NSBezierPath(rect: NSRect(x: centre.x - half, y: centre.y - t,
                                          width: half * 2, height: t * 2)))
    bars.append(NSBezierPath(rect: NSRect(x: centre.x - t, y: centre.y - half,
                                          width: t * 2, height: half * 2)))

    var rings: [NSBezierPath] = []
    for sx: CGFloat in [-1, 1] {
        for sy: CGFloat in [-1, 1] {
            let c = NSPoint(x: centre.x + sx * d, y: centre.y + sy * d)
            let outer = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            outer.append(NSBezierPath(ovalIn: NSRect(x: c.x - r + ringWidth, y: c.y - r + ringWidth,
                                                     width: (r - ringWidth) * 2, height: (r - ringWidth) * 2)))
            outer.windingRule = .evenOdd
            rings.append(outer)
        }
    }
    return (bars, rings)
}

// MARK: - Knockouts
// A knockout is what makes a small glyph legible: rather than stacking shapes
// on top of each other, we cut a gap so the eye can separate them at 18px.

private func withClearBlend(_ work: () -> Void) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    work()
    ctx.restoreGState()
}

/// Punches `path` straight out of whatever is already drawn.
func eraseFill(_ path: NSBezierPath) {
    withClearBlend {
        NSColor.white.setFill()
        path.fill()
    }
}

/// Cuts a rounded band through what is already drawn — used for the paused
/// slash, which has to stay readable at 18px and so needs a real gap rather
/// than a line laid over the top.
func eraseSlash(from a: NSPoint, to b: NSPoint, width: CGFloat) {
    withClearBlend {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        p.lineWidth = width
        p.lineCapStyle = .round
        NSColor.white.setStroke()
        p.stroke()
    }
}

// MARK: - Concepts

struct Concept {
    let key: String
    let blurb: String
    /// Draws the solid glyph, centred, in `ink`. Call `erase*` inside to knock
    /// shapes out of it. Concepts never pick their own colour — the style owns
    /// that, and a hardcoded white here silently vanishes on a template glyph.
    let draw: (NSColor) -> Void
}

let concepts: [Concept] = [
    // Solid clipboard with the spark knocked out of it. A hole rather than an
    // overlay is what makes this work: at 18pt two solid shapes on top of each
    // other merge into one unreadable blob, while a knockout keeps both readable.
    // It also mirrors the app icon, where the star sits inside the clipboard.
    Concept(key: "clipboard-spark",
            blurb: "Solid clipboard with the spark knocked out of it. Mirrors the app icon, and the knockout keeps both shapes readable at 18px.") { ink in
        let body = NSRect(x: -108, y: -112, width: 196, height: 196)
        let tab = NSRect(x: -52, y: 74, width: 76, height: 36)
        ink.setFill()
        clipboardPath(body: body.offsetBy(dx: center.x, dy: center.y),
                      tab: tab.offsetBy(dx: center.x, dy: center.y),
                      radius: 24).fill()
        eraseFill(starPath(centre: NSPoint(x: center.x + 22, y: center.y - 30), radius: 62))
    },

    // Two offset cards: "history of copies" rather than "clipboard". The
    // diagonal is rare in a menu bar full of upright pictograms.
    Concept(key: "card-stack",
            blurb: "Two offset cards — reads as a history of copies, not a clipboard. Chunky diagonal silhouette, rare in menu bars.") { ink in
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: center.x - 108, y: center.y - 20, width: 144, height: 136),
                     xRadius: 26, yRadius: 26).fill()
        let front = NSBezierPath(roundedRect: NSRect(x: center.x - 36, y: center.y - 108, width: 144, height: 136),
                                 xRadius: 26, yRadius: 26)
        // At 18pt a 15px gap is about one pixel and the two cards merge into a
        // single blob, so the separation has to be almost 2px on the canvas.
        let gap: CGFloat = 30
        eraseFill(NSBezierPath(roundedRect: front.bounds.insetBy(dx: -gap, dy: -gap),
                               xRadius: 26 + gap, yRadius: 26 + gap))
        front.fill()
    },

    // ⌘ alone. A tile would fight every other utility in the bar; the bare
    // cloverleaf is the most distinctive mark available and stays crisp when
    // it is only ~7px wide.
    Concept(key: "cmd",
            blurb: "Bare ⌘ cloverleaf. Maximum distance legibility and unique among menu-bar pictograms, but reads as an action rather than as Kopie.") { ink in
        let (bars, rings) = commandPaths(centre: center, half: 108)
        ink.setFill()
        bars.fill()
        for ring in rings { ring.fill() }
    },

    // Clipboard + paste arrow, the arrow knocked out of the body so both stay
    // readable at this size. It points down, into the clipboard.
    Concept(key: "paste-arrow",
            blurb: "Clipboard with a knocked-out paste arrow pointing into it — action-led, says what the app does.") { ink in
        let body = NSRect(x: -92, y: -108, width: 184, height: 184)
        let tab = NSRect(x: -40, y: 62, width: 80, height: 36)
        ink.setFill()
        clipboardPath(body: body.offsetBy(dx: center.x, dy: center.y),
                      tab: tab.offsetBy(dx: center.x, dy: center.y),
                      radius: 24).fill()
        eraseFill(downArrowPath(x: center.x, yTop: center.y + 76, yShoulder: center.y - 6,
                                yTip: center.y - 78, shaftHalf: 22, headHalf: 50))
    },

    // The spark on its own — the app icon's star, freed of the clipboard.
    Concept(key: "spark",
            blurb: "The app icon's spark alone. Maximally distinctive and very fast to find, but drops the clipboard meaning entirely.") { ink in
        ink.setFill()
        starPath(centre: center, radius: 108).fill()
    },
]

// MARK: - Styles

enum Style: String, CaseIterable {
    case template        // alpha-only; macOS tints it
    case colorLight      // coral, tuned for a light menu bar
    case colorDark       // lifted coral, tuned for a dark menu bar

    var blurb: String {
        switch self {
        case .template:  return "Template — monochrome, macOS tints it to match the menu label. HIG-correct."
        case .colorLight: return "Coral (light bar) — full colour, needs its own dark-bar twin."
        case .colorDark:  return "Coral (dark bar) — lifted coral so it survives a dark menu bar."
        }
    }
}

/// Coral drawn to match the app icon's palette.
func coralColors(_ dark: Bool) -> (top: NSColor, bottom: NSColor) {
    if dark {
        // Lifted further so the badge doesn't sink into a dark menu bar.
        return (NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.62, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.50, blue: 0.44, alpha: 1))
    }
    return (NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.82, green: 0.32, blue: 0.36, alpha: 1))
}

func drawTile(_ dark: Bool) {
    let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    let path = NSBezierPath(roundedRect: rect, xRadius: 60, yRadius: 60)
    path.addClip()
    let c = coralColors(dark)
    NSGradient(colors: [c.top, c.bottom])!.draw(in: rect, angle: 270)
}

// MARK: - State

enum State: String, CaseIterable {
    case idle
    case paused
}

func drawPausedSlash() {
    // Extended past the glyph so both ends of the cut are visible, and wide
    // enough to survive as a real gap at 18pt.
    eraseSlash(from: NSPoint(x: center.x - 122, y: center.y - 122),
               to: NSPoint(x: center.x + 122, y: center.y + 122),
               width: 34)
}

// MARK: - Render + output

let outDir = URL(fileURLWithPath: "assets/menu-icon-sources", isDirectory: true)

func render(_ name: String, _ draw: () -> Void) throws {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "menu-icon", code: 1)
    }
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try png.write(to: outDir.appendingPathComponent("\(name)@256.png"))

    // 18pt @2x and @1x — the sizes that actually reach the menu bar.
    for px in [36, 18] {
        let resized = NSImage(size: NSSize(width: px, height: px))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        resized.unlockFocus()
        guard let t = resized.tiffRepresentation,
              let r = NSBitmapImageRep(data: t),
              let out = r.representation(using: .png, properties: [:]) else { continue }
        try out.write(to: outDir.appendingPathComponent("\(name)@\(px).png"))
    }
    print("  \(name)")
}

for concept in concepts {
    print(concept.key)
    for style in Style.allCases {
        for state in State.allCases {
            let name = "\(concept.key)-\(style.rawValue)-\(state.rawValue)"
            try render(name) {
                let ink: NSColor
                switch style {
                case .template:  ink = .black
                case .colorLight: drawTile(false); ink = .white
                case .colorDark:  drawTile(true);  ink = .white
                }
                concept.draw(ink)
                if state == .paused { drawPausedSlash() }
            }
        }
    }
}

print("\n=> wrote \(concepts.count * Style.allCases.count * State.allCases.count) images to \(outDir.path)")
