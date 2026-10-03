// Draws the Tab Dupes app icon at 1024×1024: a stack of identical browser tabs collapsing into
// one. Usage: swift icon/make-icon.swift icon/AppIcon-1024.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// macOS icon grid: 824pt body centred on the 1024 canvas, continuous-corner radius ≈ 185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35).cgColor)
rgb(0x1E5BD8).setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
NSGradient(colors: [rgb(0x3FA2FF), rgb(0x1D4FCF), rgb(0x16329A)], atLocations: [0, 0.55, 1],
           colorSpace: .sRGB)!.draw(in: body, angle: -90)
// Soft highlight across the top.
NSGradient(colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)])!
    .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

/// A browser window card: a tab strip along the top with the active tab raised, page lines below.
/// `fade` tints the card toward the background so back copies recede without showing through.
func window(at origin: CGPoint, fade: CGFloat) {
    let w: CGFloat = 480, h: CGFloat = 380, r: CGFloat = 40, bar: CGFloat = 92
    let frame = CGRect(x: origin.x, y: origin.y, width: w, height: h)
    let card = NSBezierPath(roundedRect: frame, xRadius: r, yRadius: r)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x0A1A5C, 0.4).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    rgb(0xFFFFFF).setFill()
    card.fill()

    ctx.saveGState()
    card.addClip()
    // Tab strip.
    rgb(0xDCE6F7).setFill()
    CGRect(x: frame.minX, y: frame.maxY - bar, width: w, height: bar).fill()
    // Inactive tab, then the active tab joined to the page below it.
    rgb(0xC3D3EE).setFill()
    NSBezierPath(roundedRect: CGRect(x: frame.minX + 262, y: frame.maxY - 74, width: 150, height: 44),
                 xRadius: 16, yRadius: 16).fill()
    rgb(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: CGRect(x: frame.minX + 34, y: frame.maxY - bar, width: 214, height: 72),
                 xRadius: 18, yRadius: 18).fill()
    CGRect(x: frame.minX + 34, y: frame.maxY - bar, width: 214, height: 30).fill()
    rgb(0x2C6BE8).setFill()
    NSBezierPath(ovalIn: CGRect(x: frame.minX + 58, y: frame.maxY - 66, width: 32, height: 32)).fill()
    rgb(0xB9C9E6).setFill()
    NSBezierPath(roundedRect: CGRect(x: frame.minX + 104, y: frame.maxY - 58, width: 118, height: 16),
                 xRadius: 8, yRadius: 8).fill()
    // Page content.
    rgb(0xCCD8EE).setFill()
    var y = frame.maxY - bar - 66
    for len: CGFloat in [360, 300, 330, 220] {
        NSBezierPath(roundedRect: CGRect(x: frame.minX + 44, y: y, width: len, height: 26), xRadius: 13, yRadius: 13).fill()
        y -= 58
    }
    rgb(0x3F86F2, fade).setFill()
    frame.fill()
    ctx.restoreGState()

    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// Back to front: identical copies fading as they recede up and to the right.
window(at: CGPoint(x: 360, y: 470), fade: 0.62)
window(at: CGPoint(x: 290, y: 390), fade: 0.36)
window(at: CGPoint(x: 200, y: 250), fade: 0)

// Orange "×" badge on the front tab: the duplicates get closed down to one.
let badge = CGRect(x: 570, y: 170, width: 200, height: 200)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: rgb(0x5A2000, 0.4).cgColor)
NSGradient(colors: [rgb(0xFFB23F), rgb(0xFF7A1A)])!.draw(in: NSBezierPath(ovalIn: badge), angle: -90)
ctx.restoreGState()
rgb(0xFFFFFF, 0.9).setStroke()
let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 5, dy: 5))
ring.lineWidth = 10
ring.stroke()
let cross = NSBezierPath()
let c = CGPoint(x: badge.midX, y: badge.midY), arm: CGFloat = 44
cross.move(to: CGPoint(x: c.x - arm, y: c.y - arm)); cross.line(to: CGPoint(x: c.x + arm, y: c.y + arm))
cross.move(to: CGPoint(x: c.x - arm, y: c.y + arm)); cross.line(to: CGPoint(x: c.x + arm, y: c.y - arm))
cross.lineWidth = 30
cross.lineCapStyle = .round
rgb(0xFFFFFF).setStroke()
cross.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
