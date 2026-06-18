import AppKit

// Draws the Stretch app icon (a person mid-stretch on a calming teal squircle)
// and writes a 1024x1024 master PNG. Run with:  swift tools/IconGen.swift <out.png>

func color(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1).cgColor
}

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let S = CGFloat(size)
let full = CGRect(x: 0, y: 0, width: S, height: S)

// Rounded-square (squircle-ish) background with a vertical teal gradient.
ctx.saveGState()
let bg = CGPath(roundedRect: full, cornerWidth: 228, cornerHeight: 228, transform: nil)
ctx.addPath(bg)
ctx.clip()
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(56, 214, 170), color(22, 150, 128)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// Soft highlight arc in the upper area for a bit of depth.
ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
ctx.fillEllipse(in: CGRect(x: -200, y: 620, width: 1400, height: 900))
ctx.restoreGState()

// The figure: thick white rounded strokes + a filled head.
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setFillColor(NSColor.white.cgColor)
ctx.setLineWidth(82)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let cx: CGFloat = 512
// Torso
ctx.move(to: CGPoint(x: cx, y: 405))
ctx.addLine(to: CGPoint(x: cx, y: 640))
ctx.strokePath()
// Arms raised in a wide V (the stretch)
ctx.move(to: CGPoint(x: 352, y: 832))
ctx.addLine(to: CGPoint(x: cx, y: 640))
ctx.addLine(to: CGPoint(x: 672, y: 832))
ctx.strokePath()
// Legs
ctx.move(to: CGPoint(x: 416, y: 232))
ctx.addLine(to: CGPoint(x: cx, y: 405))
ctx.addLine(to: CGPoint(x: 608, y: 232))
ctx.strokePath()
// Head
let hr: CGFloat = 84
ctx.fillEllipse(in: CGRect(x: cx - hr, y: 712, width: hr * 2, height: hr * 2))

NSGraphicsContext.restoreGraphicsState()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
