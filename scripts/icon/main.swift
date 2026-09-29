import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Brightern app icon: a sun, with a badge in the corner showing two monitors
// kept in sync. Everything is drawn on a 1024-point canvas with the origin at the top left.
//
//   icon --preview <dir>   a 1024 px PNG plus a sheet of the small sizes, to check the design
//   icon --iconset <dir>   every size macOS needs, for `iconutil -c icns` (see scripts/make-icon.sh)

/// How a shape is painted.
enum Paint {
    case flat(CGColor)
    /// Top to bottom.
    case linear([CGColor])
    /// Around the shape's centre, like light catching machined metal.
    case conic([CGColor])
}

struct Palette {
    let background: Paint
    let sun: Paint
    let sunEdge: CGColor
    let badge: Paint
    let badgeRim: CGColor
    let glyph: Paint
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Light and dark bands alternating around a circle: the look of turned metal.
let machinedMetal = [0xFBFBFC, 0xA8A8AE, 0xF2F2F4, 0x8E8E94, 0xFBFBFC, 0xA8A8AE, 0xF2F2F4, 0x8E8E94, 0xFBFBFC].map { rgb($0) }

/// Graphite: a dark background, a machined-metal sun and a light badge.
let graphite = Palette(
    background: .linear([rgb(0x5C5C61), rgb(0x2A2A2D)]),
    sun: .conic(machinedMetal), sunEdge: rgb(0x151517),
    badge: .linear([rgb(0xF4F4F6), rgb(0xBDBDC3)]), badgeRim: rgb(0xFFFFFF),
    glyph: .linear([rgb(0x55555A), rgb(0x2A2A2D)]))

// MARK: Shapes

/// Apple's icon shape: a squircle (superellipse) rather than a plain rounded rectangle.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(
            x: rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
            y: rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func sunShape(center: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: center.x - 135, y: center.y - 135, width: 270, height: 270))
    let rays = CGMutablePath()
    // The bottom-right ray would sit behind the badge, so it's left out.
    for index in 0..<8 where index != 1 {
        let angle = CGFloat(index) * .pi / 4
        rays.move(to: CGPoint(x: center.x + 192 * cos(angle), y: center.y + 192 * sin(angle)))
        rays.addLine(to: CGPoint(x: center.x + 262 * cos(angle), y: center.y + 262 * sin(angle)))
    }
    path.addPath(rays.copy(strokingWithWidth: 46, lineCap: .round, lineJoin: .round, miterLimit: 1))
    return path
}

/// Two arcs chasing each other around the badge, like the system "sync" arrows.
func syncArrows(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for (start, end) in [(207.0, 318.0), (27.0, 138.0)] {
        let from = CGFloat(start) * .pi / 180, to = CGFloat(end) * .pi / 180
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: r, startAngle: from, endAngle: to, clockwise: false)
        path.addPath(arc.copy(strokingWithWidth: 19, lineCap: .round, lineJoin: .round, miterLimit: 1))

        // Arrowhead at the end of the arc, pointing along the direction of travel.
        let tip = to + 0.2
        let tangent = CGPoint(x: -sin(tip), y: cos(tip))
        let normal = CGPoint(x: cos(tip), y: sin(tip))
        let point = CGPoint(x: c.x + r * cos(tip), y: c.y + r * sin(tip))
        let head = CGMutablePath()
        head.move(to: CGPoint(x: point.x + tangent.x * 14, y: point.y + tangent.y * 14))
        head.addLine(to: CGPoint(
            x: point.x - tangent.x * 22 + normal.x * 25, y: point.y - tangent.y * 22 + normal.y * 25))
        head.addLine(to: CGPoint(
            x: point.x - tangent.x * 22 - normal.x * 25, y: point.y - tangent.y * 22 - normal.y * 25))
        head.closeSubpath()
        path.addPath(head.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round, miterLimit: 1))
        path.addPath(head)
    }
    return path
}

func monitor(center c: CGPoint) -> (bezel: CGPath, screen: CGPath) {
    let bezel = CGMutablePath()
    let body = CGRect(x: c.x - 39, y: c.y - 28, width: 78, height: 54)
    bezel.addRoundedRect(in: body, cornerWidth: 10, cornerHeight: 10)
    bezel.addRect(CGRect(x: c.x - 6, y: body.maxY - 2, width: 12, height: 14))
    bezel.addRoundedRect(in: CGRect(x: c.x - 20, y: body.maxY + 10, width: 40, height: 9), cornerWidth: 4.5, cornerHeight: 4.5)
    let screen = CGPath(roundedRect: body.insetBy(dx: 8, dy: 8), cornerWidth: 4, cornerHeight: 4, transform: nil)
    return (bezel, screen)
}

// MARK: Drawing

func fill(_ ctx: CGContext, _ path: CGPath, _ paint: Paint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let box = path.boundingBoxOfPath
    switch paint {
    case .flat(let color):
        ctx.setFillColor(color)
        ctx.fill(box)
    case .linear(let colors):
        let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
    case .conic(let colors):
        // Core Graphics has no conic gradient, so paint thin wedges, blending between the colours.
        let center = CGPoint(x: box.midX, y: box.midY), radius = max(box.width, box.height)
        let slices = 360
        ctx.setShouldAntialias(false)  // antialiased seams between wedges show up as moiré
        for slice in 0..<slices {
            let position = CGFloat(slice) / CGFloat(slices) * CGFloat(colors.count - 1)
            let lower = colors[Int(position)].components!, upper = colors[min(Int(position) + 1, colors.count - 1)].components!
            let t = position - floor(position)
            let mixed = (0..<4).map { lower[$0] + (upper[$0] - lower[$0]) * t }
            let from = CGFloat(slice) / CGFloat(slices) * 2 * .pi + .pi / 8, to = from + 2 * .pi / CGFloat(slices) + 0.002
            let wedge = CGMutablePath()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
            wedge.closeSubpath()
            ctx.addPath(wedge)
            ctx.setFillColor(CGColor(srgbRed: mixed[0], green: mixed[1], blue: mixed[2], alpha: mixed[3]))
            ctx.fillPath()
        }
    }
    ctx.restoreGState()
}

func stroke(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, width: CGFloat) {
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.strokePath()
}

func drawIcon(_ ctx: CGContext, size: CGFloat, palette p: Palette) {
    let scale = size / 1024
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: scale, y: -scale)  // top-left origin, 1024-point canvas

    // Body: Apple's grid puts an 824-point squircle in the middle of the canvas, with the standard soft shadow.
    let body = squircle(in: CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: rgb(0x000000, 0.25))
    fill(ctx, body, .flat(rgb(0x808080)))
    ctx.restoreGState()
    fill(ctx, body, p.background)
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    stroke(ctx, body, rgb(0x000000, 0.12), width: 4)
    ctx.restoreGState()

    // Sun in machined metal, raised off the surface: a darker edge sits slightly below it.
    let sun = sunShape(center: CGPoint(x: 455, y: 455))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 14 * scale, color: rgb(0x000000, 0.3))
    ctx.translateBy(x: 0, y: 7)
    fill(ctx, sun, .flat(p.sunEdge))
    ctx.restoreGState()
    fill(ctx, sun, p.sun)
    ctx.saveGState()
    ctx.addPath(sun)
    ctx.clip()
    stroke(ctx, sun, rgb(0xFFFFFF, 0.6), width: 5)
    ctx.restoreGState()

    // Badge: two monitors with sync arrows around them, set into a recess cut out of the sun.
    let center = CGPoint(x: 718, y: 718)
    let recess = CGPath(ellipseIn: CGRect(x: center.x - 184, y: center.y - 184, width: 368, height: 368), transform: nil)
    let badge = CGPath(ellipseIn: CGRect(x: center.x - 160, y: center.y - 160, width: 320, height: 320), transform: nil)
    ctx.saveGState()
    ctx.addPath(recess)
    ctx.clip()
    fill(ctx, body, p.background)  // the body's own gradient, so the gap blends in
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 14 * scale, color: rgb(0x000000, 0.3))
    fill(ctx, badge, p.badge)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(badge)
    ctx.clip()
    stroke(ctx, badge, p.badgeRim, width: 8)
    ctx.restoreGState()

    fill(ctx, syncArrows(center: center, radius: 112), p.glyph)
    for dx: CGFloat in [-44, 44] {
        let parts = monitor(center: CGPoint(x: center.x + dx, y: center.y - 10))
        fill(ctx, parts.bezel, p.glyph)
        fill(ctx, parts.screen, p.badge)
    }
}

func writePNG(size: Int, palette: Palette, to url: URL) {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(ctx, size: CGFloat(size), palette: palette)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

/// The icon large and at the small sizes Finder and the Dock use.
func writeSheet(to url: URL) {
    let width = 440, height = 560
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(rgb(0xECECEC))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    do {
        let x: CGFloat = 0
        for (size, origin) in [(400, CGPoint(x: x + 20, y: 140)), (64, CGPoint(x: x + 110, y: 40)),
                               (32, CGPoint(x: x + 220, y: 56)), (16, CGPoint(x: x + 300, y: 64))] {
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            drawIcon(ctx, size: CGFloat(size), palette: graphite)
            ctx.restoreGState()
        }
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

// MARK: Main

let args = CommandLine.arguments
switch args.dropFirst().first {
case "--preview" where args.count == 3:
    let dir = URL(fileURLWithPath: args[2])
    writePNG(size: 1024, palette: graphite, to: dir.appendingPathComponent("icon.png"))
    writeSheet(to: dir.appendingPathComponent("sheet.png"))
case "--iconset" where args.count == 3:
    let dir = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        writePNG(size: points, palette: graphite, to: dir.appendingPathComponent("icon_\(points)x\(points).png"))
        writePNG(size: points * 2, palette: graphite, to: dir.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
default:
    print("usage: icon --preview <dir> | icon --iconset <dir>")
    exit(1)
}
