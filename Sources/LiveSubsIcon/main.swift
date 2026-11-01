// Renders the app icon (logo H1: a cicada's eyes and wings peeking over a subtitle bar, on orange)
// into an .iconset. `LiveSubsIcon [--dev] <out.iconset>`; --dev adds a "DEV" band.
import AppKit

let orange = NSColor(srgbRed: 0.91, green: 0.33, blue: 0.17, alpha: 1)   // #E8552B
let ink = NSColor(srgbRed: 0.082, green: 0.09, blue: 0.11, alpha: 1)     // #15171C

func render(_ px: Int, dev: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: an 824 pt body inset 100 pt, corner ≈ 185 pt.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.set()
    orange.setFill()
    squircle.fill()
    NSShadow().set()

    // Design space is the 100-unit logo, y down, mapped onto the body (same geometry as
    // CicadaLogo in Sources/LiveSubs/Onboarding.swift and site/icon.svg; keep them in step).
    let c = NSGraphicsContext.current!.cgContext
    c.saveGState()
    c.translateBy(x: body.minX, y: body.maxY)
    c.scaleBy(x: body.width / 100, y: -body.height / 100)
    c.setLineCap(.round)
    c.setStrokeColor(NSColor.white.cgColor)
    c.setLineWidth(6)
    c.move(to: CGPoint(x: 18, y: 36)); c.addQuadCurve(to: CGPoint(x: 45, y: 20), control: CGPoint(x: 26, y: 10))
    c.move(to: CGPoint(x: 82, y: 36)); c.addQuadCurve(to: CGPoint(x: 55, y: 20), control: CGPoint(x: 74, y: 10))
    c.strokePath()
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { c.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
    c.setFillColor(NSColor.white.cgColor); circle(36, 46, 13); circle(64, 46, 13); c.fillPath()
    c.setFillColor(ink.cgColor); circle(39, 49, 6); circle(67, 49, 6); c.fillPath()
    c.addPath(CGPath(roundedRect: CGRect(x: 12, y: 58, width: 76, height: 28), cornerWidth: 9, cornerHeight: 9, transform: nil)); c.fillPath()
    c.setLineWidth(5)
    c.setStrokeColor(NSColor.white.cgColor); c.move(to: CGPoint(x: 21, y: 68)); c.addLine(to: CGPoint(x: 65, y: 68)); c.strokePath()
    c.setStrokeColor(orange.cgColor); c.move(to: CGPoint(x: 21, y: 77)); c.addLine(to: CGPoint(x: 47, y: 77)); c.strokePath()
    c.restoreGState()

    if dev {
        // Dev builds: a dark "DEV" band across the bottom, so the Dock, Finder and
        // Spotlight tell them apart from the installed app.
        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        ink.setFill()
        NSRect(x: body.minX, y: body.minY, width: body.width, height: 170 * s).fill()
        let font = NSFont.systemFont(ofSize: 110 * s, weight: .heavy)
        let text = NSAttributedString(string: "DEV", attributes: [
            .font: font, .foregroundColor: NSColor.white, .kern: 14 * s,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: body.midX - size.width / 2 + 7 * s, y: body.minY + (170 * s - size.height) / 2 + 6 * s))
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = Array(CommandLine.arguments.dropFirst())
let dev = args.contains("--dev")
let out = URL(fileURLWithPath: args.first { $0 != "--dev" } ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size, dev: dev).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, dev: dev).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
