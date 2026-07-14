import AppKit

/// Click-through paper wash over every display. Soft bedtime cue — does not
/// block interaction (unlike the break overlay). Stays below `.screenSaver`
/// so break windows still cover it.
final class PaperModeController: NSObject {
    private var windows: [NSWindow] = []
    private var isActive = false
    /// Last layout we built for — avoids tear-down/rebuild on Space swipes
    /// (which can spuriously fire screen-parameter notifications).
    private var lastLayoutKey = ""

    private var intensity: Settings.PaperIntensity { Settings.shared.paperIntensity }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            buildWindowsIfNeeded(force: true)
            observeSystemChanges()
        } else {
            removeSystemObservers()
            tearDownWindows()
            lastLayoutKey = ""
        }
    }

    /// Re-apply intensity / rebuild if settings changed while active.
    func refreshAppearance() {
        guard isActive else { return }
        tearDownWindows()
        lastLayoutKey = ""
        buildWindowsIfNeeded(force: true)
    }

    // MARK: - Windows

    private func buildWindowsIfNeeded(force: Bool) {
        let key = Self.layoutKey()
        if !force, key == lastLayoutKey, !windows.isEmpty {
            // Same displays — just keep overlays in front (e.g. after a Space swipe).
            frontWindows()
            return
        }
        tearDownWindows()
        lastLayoutKey = key
        for screen in NSScreen.screens {
            windows.append(makeWindow(on: screen))
        }
        frontWindows()
    }

    private func frontWindows() {
        for win in windows {
            win.orderFrontRegardless()
        }
    }

    private func tearDownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        // High level so the panel floats *above* the Space-swipe compositor
        // (lower levels get pulled out of the animation → sudden bright flash).
        // Still one step below `.screenSaver` so break overlays stay on top.
        let win = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.hidesOnDeactivate = false
        win.becomesKeyOnlyIfNeeded = true
        win.isFloatingPanel = true
        win.animationBehavior = .none
        win.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        win.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]
        win.setFrame(screen.frame, display: true)

        let content = PaperWashView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.intensity = intensity
        win.contentView = content
        return win
    }

    private static func layoutKey() -> String {
        NSScreen.screens
            .map { s in
                let f = s.frame
                return String(format: "%.0f,%.0f,%.0f,%.0f", f.origin.x, f.origin.y, f.width, f.height)
            }
            .joined(separator: "|")
    }

    // MARK: - System changes

    private func observeSystemChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private func removeSystemObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        guard isActive else { return }
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(applyScreenLayout), object: nil)
        // Debounce lock/unlock reconnect storms; only rebuild if geometry changed.
        perform(#selector(applyScreenLayout), with: nil, afterDelay: 0.25)
    }

    @objc private func applyScreenLayout() {
        guard isActive else { return }
        buildWindowsIfNeeded(force: false)
    }

    @objc private func activeSpaceChanged() {
        guard isActive else { return }
        DisplayGamma.applyBedtime(intensity: intensity)
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(frontAfterSpaceChange), object: nil)
        perform(#selector(frontAfterSpaceChange), with: nil, afterDelay: 0.05)
    }

    @objc private func frontAfterSpaceChange() {
        guard isActive else { return }
        frontWindows()
    }
}

/// Warm parchment wash with a faint grain so the screen feels quieter / paper-like.
private final class PaperWashView: NSView {
    var intensity: Settings.PaperIntensity = .medium {
        didSet {
            cachedGrain = nil
            needsDisplay = true
        }
    }

    private var cachedGrain: CGImage?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let paper = NSColor(calibratedRed: 0.78, green: 0.74, blue: 0.64, alpha: intensity.washAlpha)
        paper.setFill()
        bounds.fill()

        let dim = NSColor(calibratedWhite: 0.08, alpha: intensity.dimAlpha)
        dim.setFill()
        bounds.fill()

        if intensity.grainAlpha > 0 {
            if cachedGrain == nil {
                cachedGrain = Self.makeGrainImage(size: bounds.size, alpha: intensity.grainAlpha)
            }
            if let grain = cachedGrain {
                NSGraphicsContext.current?.cgContext.draw(grain, in: bounds)
            }
        }
    }

    private static func makeGrainImage(size: CGSize, alpha: CGFloat) -> CGImage? {
        let w = max(1, Int(size.width.rounded(.up)))
        let h = max(1, Int(size.height.rounded(.up)))
        let rgba = CGColorSpaceCreateDeviceRGB()
        guard let rgbaCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: rgba,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let step = 3
        let a = CGFloat(min(1, max(0, alpha)))
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                var hv = x &* 374761393 &+ y &* 668265263
                hv = (hv ^ (hv >> 13)) &* 1274126177
                if (hv & 0x7fff_ffff) % 7 == 0 {
                    rgbaCtx.setFillColor(red: 0.45, green: 0.45, blue: 0.45, alpha: a)
                    rgbaCtx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return rgbaCtx.makeImage()
    }
}
