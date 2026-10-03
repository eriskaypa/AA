// Spec: 03 Appendix C "App icon art" (re-draw at 1024 px: outer ring #1B1B1B, ring #313131, face #4F4F4F, highlight
//       ring #626262, a bold sans "A" in lime #87D639, transparent corners), SHELL-184, BD.3.10 (mac/Resources/
//       AppIcon-1024.png is preferred over the upscaled 256-px ICO frame). Same geometry as the app's
//       ShellXAppIconArt view.
//
// Usage (from mac/):   swift Packaging/make-app-icon.swift Resources/AppIcon-1024.png [size]
// Not a SwiftPM target: a standalone script, run by hand when the art changes; the PNG is committed.
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <out.png> [size]\n".utf8))
    exit(2)
}
let size = args.count >= 3 ? CGFloat(Double(args[2]) ?? 1024) : 1024
let out = URL(fileURLWithPath: args[1])

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let px = Int(size)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
let center = CGPoint(x: size / 2, y: size / 2)

func disc(_ fraction: CGFloat, _ fill: NSColor, shadow: Bool = false) {
    let d = size * fraction
    let r = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
    cg.saveGState()
    if shadow {
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.035,
                     color: NSColor.black.withAlphaComponent(0.35).cgColor)
    }
    cg.setFillColor(fill.cgColor)
    cg.fillEllipse(in: r)
    cg.restoreGState()
}

// Geometry (fractions of the canvas): outer 0.90, ring 0.80, highlight 0.66, face 0.62, letter 0.46.
disc(0.90, color(0x1B1B1B), shadow: true)
disc(0.80, color(0x313131))
disc(0.66, color(0x626262))
disc(0.62, color(0x4F4F4F))

let font = NSFont.systemFont(ofSize: size * 0.46, weight: .heavy)
let text = NSAttributedString(string: "A", attributes: [.font: font, .foregroundColor: color(0x87D639)])
let line = CTLineCreateWithAttributedString(text)
let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
// Centre the glyph's ink box on the disc (baseline = centre − ink midpoint).
cg.textPosition = CGPoint(x: center.x - glyphBounds.midX, y: center.y - glyphBounds.midY)
CTLineDraw(line, cg)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: out)
    print(out.path)
} catch {
    FileHandle.standardError.write(Data("make-app-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
