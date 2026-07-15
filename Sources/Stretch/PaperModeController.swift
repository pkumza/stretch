import AppKit

/// Click-through paper wash over every display. Soft bedtime cue — does not
/// block interaction (unlike the break overlay). Stays below `.screenSaver`
/// so break windows still cover it.
final class PaperModeController: NSObject {
    private var windows: [NSWindow] = []
    private var toastWindows: [NSWindow] = []
    private var isActive = false
    /// 0…1 wash opacity (driven by AppDelegate’s fade).
    private(set) var opacity: CGFloat = 0
    /// Last layout we built for — avoids tear-down/rebuild on Space swipes.
    private var lastLayoutKey = ""

    private var intensity: Settings.PaperIntensity { Settings.shared.paperIntensity }

    /// Ensure wash windows exist (optionally starting transparent). Does not
    /// change `opacity` unless `initialOpacity` is provided.
    func prepare(initialOpacity: CGFloat = 0) {
        if !isActive {
            isActive = true
            opacity = initialOpacity
            buildWindowsIfNeeded(force: true)
            observeSystemChanges()
        } else if windows.isEmpty {
            buildWindowsIfNeeded(force: true)
        }
        setOpacity(opacity)
    }

    func setActive(_ active: Bool) {
        if active {
            prepare(initialOpacity: opacity > 0 ? opacity : 1)
            setOpacity(opacity > 0 ? opacity : 1)
        } else {
            hideToast()
            removeSystemObservers()
            tearDownWindows()
            lastLayoutKey = ""
            isActive = false
            opacity = 0
        }
    }

    func setOpacity(_ value: CGFloat) {
        opacity = max(0, min(1, value))
        for win in windows {
            win.alphaValue = opacity
            if opacity > 0.001 {
                win.orderFrontRegardless()
            }
        }
    }

    /// Re-apply intensity / rebuild if settings changed while active.
    func refreshAppearance() {
        guard isActive else { return }
        let keep = opacity
        tearDownWindows()
        lastLayoutKey = ""
        buildWindowsIfNeeded(force: true)
        setOpacity(keep)
    }

    // MARK: - Activation toast (fade in → hold → fade out over ~3s)

    private var toastAnim: Timer?

    /// Brief on-screen notice while paper mode fades in.
    func showActivationToast(duration: TimeInterval = 3) {
        hideToast()
        let message = "Bedtime — winding down"
        for screen in NSScreen.screens {
            toastWindows.append(makeToastWindow(on: screen, message: message))
        }
        for win in toastWindows {
            win.alphaValue = 0
            win.orderFrontRegardless()
        }

        let fadeIn: TimeInterval = 0.6
        let fadeOut: TimeInterval = 0.8
        let hold = max(0.4, duration - fadeIn - fadeOut)
        let t0 = Date()

        toastAnim?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(t0)
            let alpha: CGFloat
            if elapsed < fadeIn {
                let u = elapsed / fadeIn
                let eased = u * u * (3 - 2 * u)
                alpha = CGFloat(eased)
            } else if elapsed < fadeIn + hold {
                alpha = 1
            } else if elapsed < duration {
                let u = (elapsed - fadeIn - hold) / fadeOut
                let eased = u * u * (3 - 2 * u)
                alpha = CGFloat(1 - eased)
            } else {
                alpha = 0
                timer.invalidate()
                self.toastAnim = nil
                self.hideToast()
                return
            }
            for win in self.toastWindows {
                win.alphaValue = alpha
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        toastAnim = timer
        timer.fire()
    }

    private func hideToast() {
        toastAnim?.invalidate()
        toastAnim = nil
        toastWindows.forEach { $0.orderOut(nil) }
        toastWindows.removeAll()
    }

    private func makeToastWindow(on screen: NSScreen, message: String) -> NSWindow {
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
        win.isFloatingPanel = true
        win.animationBehavior = .none
        // Above paper wash, still below break overlay (.screenSaver).
        win.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        win.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]
        win.setFrame(screen.frame, display: true)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 28, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.alignment = .center
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        pill.layer?.cornerRadius = 14
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.addSubview(pill)
        win.contentView = content

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -28),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -14),
            pill.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return win
    }

    // MARK: - Windows

    private func buildWindowsIfNeeded(force: Bool) {
        let key = Self.layoutKey()
        if !force, key == lastLayoutKey, !windows.isEmpty {
            frontWindows()
            return
        }
        tearDownWindows()
        lastLayoutKey = key
        for screen in NSScreen.screens {
            windows.append(makeWindow(on: screen))
        }
        setOpacity(opacity)
    }

    private func frontWindows() {
        for win in windows {
            win.alphaValue = opacity
            win.orderFrontRegardless()
        }
    }

    private func tearDownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
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
        win.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 2)
        win.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]
        win.setFrame(screen.frame, display: true)
        win.alphaValue = opacity

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
        perform(#selector(applyScreenLayout), with: nil, afterDelay: 0.25)
    }

    @objc private func applyScreenLayout() {
        guard isActive else { return }
        buildWindowsIfNeeded(force: false)
    }

    @objc private func activeSpaceChanged() {
        guard isActive else { return }
        if Settings.shared.bedtimeUseGamma, opacity > 0.5 {
            DisplayGamma.applyBedtime(intensity: intensity)
        }
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(frontAfterSpaceChange), object: nil)
        perform(#selector(frontAfterSpaceChange), with: nil, afterDelay: 0.05)
    }

    @objc private func frontAfterSpaceChange() {
        guard isActive else { return }
        frontWindows()
    }
}

/// Soft warm wash only — no paper grain/texture (brightness comes from gamma).
private final class PaperWashView: NSView {
    var intensity: Settings.PaperIntensity = .medium {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let paper = NSColor(calibratedRed: 0.78, green: 0.74, blue: 0.64, alpha: intensity.washAlpha)
        paper.setFill()
        bounds.fill()
    }
}
