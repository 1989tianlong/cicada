import AppKit

/// `LiveSubs --render-dmg-background out.png <scale>` draws the installer window's background.
/// Finder places the icons on top of it at `appIcon` and `applicationsIcon`, so the art leaves
/// those spots empty. Keep in step with `scripts/dmg-template.sh`.
enum DMGBackground {
    static let size = CGSize(width: 640, height: 400)
    static let appIcon = CGPoint(x: 170, y: 205)
    static let applicationsIcon = CGPoint(x: 470, y: 205)

    private static let ink = NSColor(srgbRed: 0.082, green: 0.09, blue: 0.11, alpha: 1)       // #15171C
    private static let secondary = NSColor(srgbRed: 0.353, green: 0.373, blue: 0.42, alpha: 1) // #5A5F6B
    private static let orange = NSColor(srgbRed: 0.91, green: 0.33, blue: 0.17, alpha: 1)      // #E8552B

    static func render(to url: URL, scale: Int) throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        guard let cg = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { throw CocoaError(.fileWriteUnknown) }
        // Flip to a y-down point space so coordinates match Finder's icon positions.
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(cg)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }

    private static func draw(_ ctx: CGContext) {
        ctx.setFillColor(CGColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1)) // #F6F7F9
        ctx.fill(CGRect(origin: .zero, size: size))

        text("把 Live Subs 拖进「应用程序」", size: 22, weight: .semibold, color: ink, centerX: size.width / 2, top: 40)
        text("然后在「应用程序」或启动台里打开它", size: 13, weight: .regular, color: secondary, centerX: size.width / 2, top: 76)

        // Dotted arrow from the app to Applications.
        ctx.setStrokeColor(orange.cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [0.1, 9])
        let y = appIcon.y
        ctx.move(to: CGPoint(x: appIcon.x + 84, y: y))
        ctx.addLine(to: CGPoint(x: applicationsIcon.x - 92, y: y))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineJoin(.round)
        let tip = CGPoint(x: applicationsIcon.x - 80, y: y)
        ctx.move(to: CGPoint(x: tip.x - 11, y: y - 9))
        ctx.addLine(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x - 11, y: y + 9))
        ctx.strokePath()

        text("第一次打开被拦住：系统设置 › 隐私与安全性 › 仍要打开", size: 12, weight: .regular,
             color: secondary, centerX: size.width / 2, top: 338)
    }

    private static func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, top: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let w = (s as NSString).size(withAttributes: attrs).width
        (s as NSString).draw(at: CGPoint(x: centerX - w / 2, y: top), withAttributes: attrs)
    }
}
