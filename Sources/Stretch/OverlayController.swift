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

    // Medication doses riding this break. The user presses T to mark them taken
    // (the break keeps going); the final outcome is committed once when the break
    // ends, based on whether T was pressed and how the break was dismissed.
    private var reminders: [DoseInstance] = []
    private var onDoseAction: ((DoseInstance, MedicationManager.Action) -> Void)?
    private var medLabels: [(label: NSTextField, dose: DoseInstance)] = []
    private var medsTaken = false
    private var medsCommitted = false

    private enum EndReason { case skip, snooze, complete }

    private var isShown: Bool { activeType != nil }

    func show(type: BreakType,
              duration: TimeInterval,
              reminders: [DoseInstance] = [],
              onSkip: @escaping () -> Void,
              onSnooze: @escaping () -> Void,
              onDoseAction: ((DoseInstance, MedicationManager.Action) -> Void)? = nil) {
        hide()
        self.onSkip = onSkip
        self.onSnooze = onSnooze
        self.activeType = type
        self.activeTip = Self.tip(for: type)
        self.reminders = reminders
        self.onDoseAction = onDoseAction
        self.medsTaken = false
        self.medsCommitted = false

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
        commitMeds(.complete)        // natural end (or any path not already committed)
        removeScreenObserver()
        removeKeyMonitor()
        tearDownWindows()
        activeType = nil
        reminders = []
        onDoseAction = nil
        medLabels.removeAll()
        medsTaken = false
    }

    // MARK: - Window lifecycle

    /// Create one overlay window per current screen and bring them up front.
    private func buildWindows() {
        guard let type = activeType else { return }
        medLabels.removeAll()
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
            case 36, 76:                       // Return / Enter -> skip break
                self.commitMeds(.skip); self.onSkip?(); return nil
            case 53:                           // Esc -> remind later
                self.commitMeds(.snooze); self.onSnooze?(); return nil
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "t":                      // mark meds taken; break continues
                    if self.reminders.isEmpty { return event }
                    self.medsTaken.toggle(); self.refreshMedLabels(); return nil
                case "s": self.commitMeds(.skip);   self.onSkip?();   return nil
                case "p": self.commitMeds(.snooze); self.onSnooze?(); return nil
                default:  return event
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Commit each due dose's outcome exactly once, when the break ends:
    /// T pressed → taken; otherwise skip→skipped, snooze/complete→still due.
    private func commitMeds(_ reason: EndReason) {
        guard !medsCommitted, let onDoseAction else { medsCommitted = true; return }
        medsCommitted = true
        for dose in reminders {
            let action: MedicationManager.Action = medsTaken ? .took
                : (reason == .skip ? .skip : .notYet)
            onDoseAction(dose, action)
        }
    }

    private func refreshMedLabels() {
        let color = medsTaken ? NSColor.systemGreen : NSColor.white
        for (label, dose) in medLabels {
            label.stringValue = Self.medText(dose, taken: medsTaken)
            label.textColor = color
        }
    }

    private static func medText(_ dose: DoseInstance, taken: Bool) -> String {
        let mark = taken ? "✓  " : "○  "
        let notes = dose.notes.isEmpty ? "" : "   ·   \(dose.notes)"
        return mark + dose.medName + notes
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

        var stackViews: [NSView] = [title, tipLabel, countdown, buttons, hint]
        if !reminders.isEmpty {
            let header = Self.label("Medications due", size: 15, weight: .semibold,
                                    color: NSColor.white.withAlphaComponent(0.85))
            let rows = reminders.map { dose -> NSTextField in
                let l = Self.label(Self.medText(dose, taken: medsTaken), size: 19,
                                   weight: .semibold, color: medsTaken ? .systemGreen : .white)
                medLabels.append((l, dose))
                return l
            }
            let medHint = Self.label("Press  T  when taken — your break keeps going",
                                     size: 13, weight: .regular,
                                     color: NSColor.white.withAlphaComponent(0.5))
            let meds = NSStackView(views: [header] + rows + [medHint])
            meds.orientation = .vertical
            meds.alignment = .centerX
            meds.spacing = 10
            meds.setCustomSpacing(16, after: rows.last ?? header)
            stackViews.append(meds)
        }

        let stack = NSStackView(views: stackViews)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 24
        stack.setCustomSpacing(36, after: countdown)
        stack.setCustomSpacing(18, after: buttons)
        if !reminders.isEmpty { stack.setCustomSpacing(44, after: hint) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return win
    }

    @objc private func skipTapped()   { commitMeds(.skip);   onSkip?() }
    @objc private func snoozeTapped() { commitMeds(.snooze); onSnooze?() }

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

    private static func tip(for type: BreakType) -> String {
        MessageStore.shared.randomMessage(for: type)
    }
}
