// Renders the app icon into an .iconset directory: swift make-icon.swift <out.iconset>
// An ensō (the Zen circle of enlightenment) drawn in glowing terminal phosphor on a
// dark screen, with a block cursor waiting at its centre.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// Deterministic random numbers so every build draws the same brush texture.
struct LCG {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
    }
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
             blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let ctx = ns.cgContext

    // Outer bezel (macOS icon grid: ~10% margin).
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    rgb(0x1B1E23).setFill()
    tilePath.fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(0x3A3F4B), rgb(0x16181C)])!.draw(in: tilePath, angle: -90)

    // Inner screen.
    let screen = tile.insetBy(dx: tile.width * 0.045, dy: tile.width * 0.045)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: screen.width * 0.19, yRadius: screen.width * 0.19)
    NSGradient(colors: [rgb(0x2E3440), rgb(0x1F232A)])!
        .draw(in: screenPath, relativeCenterPosition: NSPoint(x: 0, y: 0.15))
    ctx.saveGState()
    screenPath.addClip()

    // Faint blue bloom behind the circle.
    let center = CGPoint(x: screen.midX, y: screen.midY + screen.height * 0.01)
    let bloom = NSGradient(colors: [rgb(0x61AFEF, 0.20), rgb(0x61AFEF, 0)])!
    bloom.draw(fromCenter: center, radius: 0, toCenter: center, radius: screen.width * 0.5, options: [])

    // Ensō in phosphor: thin bristle strokes along a wobbly circle, swelling then
    // fraying into dry-brush streaks, coloured cyan → blue along the stroke.
    let radius = screen.width * 0.3
    let maxWidth = screen.width * 0.075
    let startAngle = CGFloat.pi * 0.58
    let sweep = CGFloat.pi * 1.83
    let bristles = 44
    var rng = LCG(state: 42)
    var segments: [(CGPoint, CGPoint, NSColor)] = []
    for b in 0..<bristles {
        let lane = CGFloat(b) / CGFloat(bristles - 1) - 0.5
        let fray = rng.next()
        let end = 1 - pow(abs(lane) * 2, 1.3) * 0.22 - fray * 0.12
        let steps = 220
        var prev: CGPoint?
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            if t > end { break }
            let press = 0.35 + 0.65 * sqrt(min(1, t / 0.09))
            let width = maxWidth * press * (0.75 + 0.35 * sin(.pi * min(1, t * 1.15))) * (1 - 0.6 * pow(t, 2.2))
            let theta = startAngle - sweep * t
            let r = radius * (1 + 0.025 * sin(theta * 3 + 0.6)) + lane * width
            let p = CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r)
            let dry = t > 0.62 && rng.next() < (t - 0.62) * 2.2 * (0.35 + abs(lane))
            if let prev, !dry {
                // Pale cyan where the brush lands, deepening to blue at the tail.
                segments.append((prev, p, rgb(0xA5F3FF).blended(withFraction: t, of: rgb(0x4F9FE6))!))
            }
            prev = p
        }
    }
    let bristleWidth = max(s * 0.004, maxWidth / CGFloat(bristles) * 1.25)
    ctx.setLineCap(.round)

    // Pass 1: soft phosphor glow. Pass 2: crisp bristles on top, keeping the texture.
    for (glow, alpha, width) in [(true, 0.28, bristleWidth * 1.8), (false, 0.95, bristleWidth)] {
        ctx.saveGState()
        if glow { ctx.setShadow(offset: .zero, blur: s * 0.045, color: rgb(0x61AFEF, 1).cgColor) }
        ctx.setLineWidth(width)
        for (a, b, c) in segments {
            ctx.setStrokeColor(c.withAlphaComponent(alpha).cgColor)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // Block cursor at the centre of the circle.
    let h = screen.width * 0.2
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.025, color: rgb(0xDCDFE4, 0.7).cgColor)
    rgb(0xE6E9EE, 0.95).setFill()
    NSBezierPath(rect: CGRect(x: center.x - h * 0.28, y: center.y - h / 2, width: h * 0.56, height: h)).fill()
    ctx.restoreGState()

    // Glass highlight across the top of the screen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.07), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2), angle: -90)
    ctx.restoreGState()

    // Thin rim light on the screen edge.
    screenPath.lineWidth = max(1, s * 0.004)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    screenPath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
