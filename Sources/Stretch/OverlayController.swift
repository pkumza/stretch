import AppKit

/// A borderless window that can still become key and accept the first click,
/// so the overlay's buttons and keyboard shortcuts actually work.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A button that responds to the very first click even when the app wasn't active.
final class OverlayButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows a dimmed full-screen overlay on every screen during a break.
final class OverlayController: NSObject {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []

    private var onSkip: (() -> Void)?     // permanent
    private var onSnooze: (() -> Void)?   // temporary — re-alerts soon
    private var keyMonitor: Any?

    // The current break's context, kept so we can rebuild the windows when the
    // screen arrangement changes (an external display is connected, or the
    // system relocates windows across a lock/sleep).
    private var activeType: BreakType?
    private var activeTip = ""
    private var lastCountdownText = "00:00"

    private var isShown: Bool { activeType != nil }

    func show(type: BreakType,
              duration: TimeInterval,
              onSkip: @escaping () -> Void,
              onSnooze: @escaping () -> Void) {
        hide()
        self.onSkip = onSkip
        self.onSnooze = onSnooze
        self.activeType = type
        self.activeTip = Self.tip(for: type)

        buildWindows()
        installKeyMonitor()
        observeScreenChanges()
        update(remaining: duration)
    }

    func update(remaining: TimeInterval) {
        lastCountdownText = MenuBarController.clock(max(0, remaining))
        for label in countdownLabels { label.stringValue = lastCountdownText }
    }

    func hide() {
        removeScreenObserver()
        removeKeyMonitor()
        tearDownWindows()
        activeType = nil
    }

    // MARK: - Window lifecycle

    /// Create one overlay window per current screen and bring them up front.
    private func buildWindows() {
        guard let type = activeType else { return }
        for screen in NSScreen.screens {
            let win = makeWindow(on: screen, type: type, tip: activeTip)
            windows.append(win)
            win.makeKeyAndOrderFront(nil)
        }
        for label in countdownLabels { label.stringValue = lastCountdownText }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    private func tearDownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        countdownLabels.removeAll()
    }

    // MARK: - Reacting to display changes

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func removeScreenObserver() {
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screenParametersChanged() {
        guard isShown else { return }
        // A lock/sleep with an external display fires a disconnect *and* a
        // reconnect in quick succession; coalesce them into a single rebuild.
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(rebuildWindows), object: nil)
        perform(#selector(rebuildWindows), with: nil, afterDelay: 0.2)
    }

    /// Tear down and recreate so there is exactly one correctly-framed window
    /// per current screen — fixes overlapping overlays on the built-in display
    /// and an uncovered external display after a lock/unlock.
    @objc private func rebuildWindows() {
        guard isShown else { return }
        tearDownWindows()
        buildWindows()
    }

    // MARK: - Keyboard shortcuts

    private func installKeyMonitor() {
        // Local monitor catches keys while the overlay is up, regardless of which
        // window is key. Returning nil swallows the event.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 36, 76:                       // Return / Enter -> permanent skip
                self.onSkip?(); return nil
            case 53:                           // Esc -> snooze
                self.onSnooze?(); return nil
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "s": self.onSkip?();   return nil
                case "p": self.onSnooze?(); return nil
                default:  return event
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Building one screen's overlay

    private func makeWindow(on screen: NSScreen, type: BreakType, tip: String) -> NSWindow {
        let win = OverlayWindow(contentRect: screen.frame,
                                styleMask: .borderless,
                                backing: .buffered,
                                defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.black.withAlphaComponent(0.92)
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.setFrame(screen.frame, display: true)
        win.acceptsMouseMovedEvents = true

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        win.contentView = content

        let title = Self.label(type.title, size: 44, weight: .bold, color: .white)
        let tipLabel = Self.label(tip, size: 20, weight: .regular,
                                  color: NSColor.white.withAlphaComponent(0.7))

        let countdown = Self.label("00:00", size: 64, weight: .semibold, color: .white)
        countdown.font = NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
        countdownLabels.append(countdown)

        let skip = OverlayButton(title: "Skip break", target: self, action: #selector(skipTapped))
        let snooze = OverlayButton(title: "Remind me in 2 min", target: self, action: #selector(snoozeTapped))
        for b in [skip, snooze] {
            b.bezelStyle = .rounded
            b.controlSize = .large
        }

        let buttons = NSStackView(views: [snooze, skip])
        buttons.orientation = .horizontal
        buttons.spacing = 16

        let hint = Self.label("Skip break:  press  S  or  ⏎       ·       Remind me later:  press  P  or  Esc",
                              size: 13, weight: .regular,
                              color: NSColor.white.withAlphaComponent(0.5))

        let stack = NSStackView(views: [title, tipLabel, countdown, buttons, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 24
        stack.setCustomSpacing(36, after: countdown)
        stack.setCustomSpacing(18, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return win
    }

    @objc private func skipTapped()   { onSkip?() }
    @objc private func snoozeTapped() { onSnooze?() }

    // MARK: - Helpers

    private static func label(_ text: String, size: CGFloat,
                              weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = .center
        l.maximumNumberOfLines = 0
        return l
    }

    private static let shortTips = [
        "Look away — focus on something 20 feet away.",
        "Blink a few times and relax your eyes.",
        "Roll your shoulders back and breathe.",
        "Unclench your jaw and drop your shoulders.",
        "Stretch your neck gently, side to side.",
    ]
    private static let longTips = [
        "Stand up and walk around for a few minutes.",
        "Get a glass of water and stretch your legs.",
        "Step away from the screen — look out a window.",
        "Do a few stretches and shake out your hands.",
        "Take a short walk. Your back will thank you.",
    ]

    private static func tip(for type: BreakType) -> String {
        let pool = type.isLong ? longTips : shortTips
        return pool.randomElement() ?? ""
    }
}
