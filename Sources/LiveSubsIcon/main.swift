// Renders the app icon (logo C: sound bars turning into lines of text, on orange)
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

    // Design space is the 100-unit logo (y down); map it onto the body.
    let u = 824 * s / 92, ox = body.minX - 4 * u, top = body.maxY + 4 * u
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: ox + x * u, y: top - (y + h) * u, width: w * u, height: h * u)
    }
    func bar(_ rect: NSRect, alpha: CGFloat = 1) {
        NSColor.white.withAlphaComponent(alpha).setFill()
        let radius = min(rect.width, rect.height) / 2
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    bar(r(20, 42, 7, 16))
    bar(r(31, 34, 7, 32))
    bar(r(42, 40, 7, 20))
    bar(r(57, 40, 24, 7))
    bar(r(57, 53, 16, 7), alpha: 0.7)

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
