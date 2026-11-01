import AppKit
let w = 1920, h = 1080
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
NSColor(srgbRed: 0.23, green: 0.25, blue: 0.29, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 560, y: 400, width: 280, height: 280)).fill()
let accent = NSColor(srgbRed: 0.91, green: 0.33, blue: 0.17, alpha: 1)
accent.setStroke(); let ring = NSBezierPath(ovalIn: NSRect(x: 548, y: 388, width: 304, height: 304)); ring.lineWidth = 10; ring.stroke()
("M" as NSString).draw(at: NSPoint(x: 648, y: 470), withAttributes: [.font: NSFont.systemFont(ofSize: 130, weight: .semibold), .foregroundColor: NSColor.white])
("Mia" as NSString).draw(at: NSPoint(x: 920, y: 580), withAttributes: [.font: NSFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: NSColor.white])
("Live stream · English" as NSString).draw(at: NSPoint(x: 922, y: 500), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor(white: 0.7, alpha: 1)])
accent.setFill(); NSBezierPath(roundedRect: NSRect(x: 80, y: 960, width: 150, height: 56), xRadius: 28, yRadius: 28).fill()
("LIVE" as NSString).draw(at: NSPoint(x: 112, y: 968), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.white])
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
