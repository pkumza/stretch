import AppKit

// Renders a representative Stretch break overlay to a PNG (off-screen), for the
// README. Run with:  swift tools/OverlayShot.swift <out.png>
// It rebuilds the same view layout the app shows during a break, on a dimmed
// "desktop" backdrop, so the image matches the real overlay.

final class Backdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // A subtle "desktop wallpaper" behind the dim, so it reads as full-screen.
        let cs = CGColorSpaceCreateDeviceRGB()
        func c(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
            NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1).cgColor
        }
        let grad = CGGradient(colorsSpace: cs,
                              colors: [c(70, 78, 130), c(34, 110, 102)] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: bounds.height),
                               end: CGPoint(x: bounds.width, y: 0), options: [])
        // The dim layer the real overlay uses.
        NSColor.black.withAlphaComponent(0.80).setFill()
        bounds.fill()
    }
}

/// A custom-drawn pill button (renders reliably off-screen, unlike NSButton).
final class Pill: NSView {
    private let text: String
    private let primary: Bool
    init(_ text: String, primary: Bool, width: CGFloat) {
        self.text = text; self.primary = primary
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 62).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: r, yRadius: r)
        if primary {
            NSColor.white.setFill(); path.fill()
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.5).setStroke(); path.lineWidth = 2; path.stroke()
        }
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 23, weight: .semibold),
            .foregroundColor: primary ? NSColor(white: 0.12, alpha: 1) : NSColor.white,
            .paragraphStyle: para,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let h = s.size().height
        s.draw(in: NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h))
    }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight,
           color: NSColor, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
                  : .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.alignment = .center
    l.backgroundColor = .clear
    l.isBezeled = false
    l.drawsBackground = false
    return l
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let size = NSSize(width: 1600, height: 1000)
let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                      styleMask: .borderless, backing: .buffered, defer: false)
let root = Backdrop(frame: NSRect(origin: .zero, size: size))
window.contentView = root

let title = label("Time for a short break", size: 60, weight: .bold, color: .white)
let tip = label("Look away — focus on something 20 feet away.",
                size: 28, weight: .regular, color: NSColor.white.withAlphaComponent(0.72))
let countdown = label("00:18", size: 96, weight: .semibold, color: .white, mono: true)

let snooze = Pill("Remind me in 2 min", primary: false, width: 300)
let skip = Pill("Skip break", primary: true, width: 200)
let buttons = NSStackView(views: [snooze, skip])
buttons.orientation = .horizontal
buttons.spacing = 18

let hint = label("Skip break:  press  S  or  ⏎       ·       Remind me later:  press  P  or  Esc",
                 size: 17, weight: .regular, color: NSColor.white.withAlphaComponent(0.5))

let stack = NSStackView(views: [title, tip, countdown, buttons, hint])
stack.orientation = .vertical
stack.alignment = .centerX
stack.spacing = 28
stack.setCustomSpacing(40, after: countdown)
stack.setCustomSpacing(22, after: buttons)
stack.translatesAutoresizingMaskIntoConstraints = false
root.addSubview(stack)
NSLayoutConstraint.activate([
    stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
    stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
])
root.layoutSubtreeIfNeeded()

let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
root.cacheDisplay(in: root.bounds, to: rep)

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "overlay.png"
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
