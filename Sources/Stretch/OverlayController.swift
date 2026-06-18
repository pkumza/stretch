import AppKit

/// A borderless window that can still receive key/clicks (needed for the buttons).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows a dimmed full-screen overlay on every screen during a break.
final class OverlayController: NSObject {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []

    private var onSkip: (() -> Void)?
    private var onPostpone: (() -> Void)?

    func show(type: BreakType,
              duration: TimeInterval,
              onSkip: @escaping () -> Void,
              onPostpone: @escaping () -> Void) {
        hide()
        self.onSkip = onSkip
        self.onPostpone = onPostpone

        let tip = Self.tip(for: type)
        for screen in NSScreen.screens {
            let win = makeWindow(on: screen, type: type, tip: tip)
            windows.append(win)
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        update(remaining: duration)
    }

    func update(remaining: TimeInterval) {
        let text = MenuBarController.clock(max(0, remaining))
        for label in countdownLabels { label.stringValue = text }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        countdownLabels.removeAll()
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

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        win.contentView = content

        let title = Self.label(type.title, size: 44, weight: .bold, color: .white)
        let tipLabel = Self.label(tip, size: 20, weight: .regular,
                                  color: NSColor.white.withAlphaComponent(0.7))

        let countdown = Self.label("00:00", size: 64, weight: .semibold, color: .white)
        countdown.font = NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
        countdownLabels.append(countdown)

        let skip = NSButton(title: "Skip", target: self, action: #selector(skipTapped))
        let postpone = NSButton(title: "Postpone 5 min", target: self, action: #selector(postponeTapped))
        for b in [skip, postpone] {
            b.bezelStyle = .rounded
            b.controlSize = .large
        }

        let buttons = NSStackView(views: [skip, postpone])
        buttons.orientation = .horizontal
        buttons.spacing = 16

        let stack = NSStackView(views: [title, tipLabel, countdown, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 28
        stack.setCustomSpacing(36, after: countdown)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return win
    }

    @objc private func skipTapped()     { onSkip?() }
    @objc private func postponeTapped() { onPostpone?() }

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
