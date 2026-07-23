import AppKit

/// Owns the status-bar item and its menu, and keeps the countdown label fresh.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let scheduler: BreakScheduler
    private let bedtime: BedtimeScheduler
    private var statusLine: NSMenuItem!
    private var bedtimeStatusLine: NSMenuItem!
    private var bedtimeToggleItem: NSMenuItem!

    var onPreferences: (() -> Void)?
    var onHistory: (() -> Void)?
    var onMedications: (() -> Void)?
    var onBedtimeSettingsChanged: (() -> Void)?

    init(scheduler: BreakScheduler, bedtime: BedtimeScheduler) {
        self.scheduler = scheduler
        self.bedtime = bedtime
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        if let button = statusItem.button {
            applyStatus(symbol: "figure.mind.and.body", clock: nil, tint: nil, on: button)
        }
        updateBedtime(active: bedtime.isActive)
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(item("Take a short break now", #selector(shortNow)))
        menu.addItem(item("Take a long break now", #selector(longNow)))
        menu.addItem(item("Reset timer", #selector(resetTimer)))
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        let pauseMenu = NSMenu()
        pauseMenu.addItem(item("For 30 minutes", #selector(pause30)))
        pauseMenu.addItem(item("For 1 hour", #selector(pause60)))
        pauseMenu.addItem(item("Indefinitely", #selector(pauseInf)))
        pauseMenu.addItem(.separator())
        pauseMenu.addItem(item("Resume", #selector(resumeNow)))
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        bedtimeStatusLine = NSMenuItem(title: "Bedtime paper: off", action: nil, keyEquivalent: "")
        bedtimeStatusLine.isEnabled = false
        menu.addItem(bedtimeStatusLine)
        bedtimeToggleItem = item("Turn on paper mode", #selector(toggleBedtime))
        menu.addItem(bedtimeToggleItem)

        let snoozeItem = NSMenuItem(title: "Snooze paper mode", action: nil, keyEquivalent: "")
        let snoozeMenu = NSMenu()
        snoozeMenu.addItem(item("For 15 minutes", #selector(snooze15)))
        snoozeMenu.addItem(item("For 30 minutes", #selector(snooze30)))
        snoozeMenu.addItem(item("For 1 hour", #selector(snooze60)))
        snoozeItem.submenu = snoozeMenu
        menu.addItem(snoozeItem)

        let hotkeyHint = NSMenuItem(
            title: "Shortcuts: ⌘⇧B toggle · ⌘⇧S snooze 15m",
            action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)

        menu.addItem(.separator())
        menu.addItem(item("Medications…", #selector(openMeds)))
        menu.addItem(item("History…", #selector(openHistory)))
        menu.addItem(item("Preferences…", #selector(openPrefs), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("About Stretch", #selector(about)))
        menu.addItem(item("Quit Stretch", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: - Live updates

    func update(state: SchedulerState, micHeld: Bool = false) {
        guard let button = statusItem.button else { return }
        let strain = scheduler.eyeStrainSeconds
        let tint = Self.strainColor(strain)
        // Avoid contentTintColor — on recent macOS it often forces the item black.
        button.contentTintColor = nil

        switch state {
        case .working(let nextBreak, let type):
            let remaining = nextBreak.timeIntervalSinceNow
            let overdue = remaining < 0
            let workTint = overdue ? (tint ?? Self.strainColor(1)) : tint
            let symbol: String
            if micHeld {
                symbol = "figure.mind.and.body.circle"
            } else if bedtime.isActive && !overdue && strain <= 0 {
                symbol = "moon.fill"
            } else {
                symbol = "figure.mind.and.body"
            }
            applyStatus(symbol: symbol, clock: Self.clock(remaining), tint: workTint, on: button)

            if overdue {
                statusLine.title = "Overdue " + Self.clock(abs(remaining))
            } else if type.isLong {
                statusLine.title = "Next " + Self.clock(remaining) + " · long"
            } else {
                statusLine.title = "Next " + Self.clock(remaining)
            }

        case .breaking(let type, let ends):
            let r = max(0, ends.timeIntervalSinceNow)
            applyStatus(symbol: "cup.and.saucer.fill", clock: Self.clock(r), tint: nil, on: button)
            statusLine.title = (type.isLong ? "Long break — " : "Short break — ")
                + Self.clock(r) + " left"

        case .paused(let until):
            applyStatus(
                symbol: bedtime.isActive ? "moon.fill" : "pause.circle",
                clock: nil,
                tint: tint,
                on: button)
            if let until {
                statusLine.title = "Paused until " + Self.timeOfDay(until)
            } else {
                statusLine.title = "Paused"
            }
        }
    }

    func updateBedtime(active: Bool) {
        let settings = Settings.shared
        if active {
            bedtimeStatusLine.title = "Bedtime paper: on · until "
                + BedtimeScheduler.formatMinutes(settings.bedtimeEndMin)
            bedtimeToggleItem.title = "Turn off until morning"
        } else if settings.bedtimeEnabled {
            bedtimeStatusLine.title = "Bedtime paper: scheduled "
                + BedtimeScheduler.formatMinutes(settings.bedtimeStartMin)
                + "–"
                + BedtimeScheduler.formatMinutes(settings.bedtimeEndMin)
            bedtimeToggleItem.title = "Turn on paper mode"
        } else {
            bedtimeStatusLine.title = "Bedtime paper: off (enable in Preferences)"
            bedtimeToggleItem.title = "Turn on paper mode"
        }
    }

    // MARK: - Actions

    @objc private func shortNow()   { scheduler.takeBreakNow(.short) }
    @objc private func longNow()    { scheduler.takeBreakNow(.long) }
    @objc private func resetTimer() { scheduler.resetTimer() }
    @objc private func pause30()    { scheduler.pause(for: 30 * 60) }
    @objc private func pause60()    { scheduler.pause(for: 60 * 60) }
    @objc private func pauseInf()   { scheduler.pause(for: nil) }
    @objc private func resumeNow()  { scheduler.resume() }
    @objc private func openPrefs()  { onPreferences?() }
    @objc private func openHistory() { onHistory?() }
    @objc private func openMeds()   { onMedications?() }
    @objc private func quit()       { NSApp.terminate(nil) }

    @objc private func toggleBedtime() {
        if bedtime.isActive {
            bedtime.dismissUntilMorning()
        } else {
            bedtime.activateNow()
        }
        onBedtimeSettingsChanged?()
        updateBedtime(active: bedtime.isActive)
    }

    @objc private func snooze15() { bedtime.snooze(minutes: 15); updateBedtime(active: bedtime.isActive) }
    @objc private func snooze30() { bedtime.snooze(minutes: 30); updateBedtime(active: bedtime.isActive) }
    @objc private func snooze60() { bedtime.snooze(minutes: 60); updateBedtime(active: bedtime.isActive) }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Stretch"
        alert.informativeText = "A tiny break reminder.\nShort breaks to rest your eyes, longer breaks to move.\nOptional bedtime paper mode for a quieter evening screen.\n\nCreated by Ziang and Claude Code.\nStay healthy. 🧘"
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Formatting / color

    /// Paint symbol (+ optional clock) into one non-template image when tinted.
    /// Menu-bar `attributedTitle` / `contentTintColor` are unreliable on recent macOS
    /// (custom colors often collapse to black); a baked image is stable.
    private func applyStatus(symbol: String, clock: String?, tint: NSColor?, on button: NSStatusBarButton) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")

        if let tint {
            button.image = Self.renderedStatusImage(symbol: symbol, clock: clock, tint: tint)
            button.imagePosition = clock == nil ? .imageOnly : .imageLeft
            return
        }

        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Stretch") {
            base.isTemplate = true
            button.image = base
        }
        button.imagePosition = .imageLeading
        if let clock {
            button.title = " " + clock
        }
    }

    private static func renderedStatusImage(symbol: String, clock: String?, tint: NSColor) -> NSImage {
        let pointSize: CGFloat = 14
        let font = NSFont.menuBarFont(ofSize: 0)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(.init(paletteColors: [tint]))
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        symbolImage?.isTemplate = false

        let text = clock.map { " " + $0 } ?? ""
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let symbolSize = symbolImage?.size ?? NSSize(width: pointSize, height: pointSize)
        let gap: CGFloat = 2
        let width = symbolSize.width + (text.isEmpty ? 0 : gap + textSize.width)
        let height = max(symbolSize.height, textSize.height, 18)
        let size = NSSize(width: ceil(width), height: ceil(height))

        let image = NSImage(size: size, flipped: false) { _ in
            if let symbolImage {
                let y = (height - symbolSize.height) / 2
                symbolImage.draw(
                    in: NSRect(x: 0, y: y, width: symbolSize.width, height: symbolSize.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
            }
            if !text.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: tint,
                ]
                let y = (height - textSize.height) / 2
                (text as NSString).draw(
                    at: NSPoint(x: symbolSize.width + gap, y: y),
                    withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Strain color ladder (nil = system default). Opaque sRGB for menu-bar reliability.
    static func strainColor(_ seconds: TimeInterval) -> NSColor? {
        guard seconds > 0 else { return nil }
        let minutes = seconds / 60
        if minutes < 5 {
            return NSColor(srgbRed: 0.92, green: 0.80, blue: 0.20, alpha: 1) // light yellow
        } else if minutes < 15 {
            return NSColor(srgbRed: 1.00, green: 0.72, blue: 0.00, alpha: 1) // yellow
        } else if minutes < 30 {
            return NSColor(srgbRed: 1.00, green: 0.48, blue: 0.00, alpha: 1) // orange
        } else {
            return NSColor(srgbRed: 0.95, green: 0.22, blue: 0.18, alpha: 1) // red
        }
    }

    /// Formats seconds as `MM:SS`, or `-MM:SS` when negative (overdue).
    static func clock(_ seconds: TimeInterval) -> String {
        let negative = seconds < 0
        let s = abs(Int(seconds.rounded()))
        let body = String(format: "%02d:%02d", s / 60, s % 60)
        return negative ? "-" + body : body
    }

    static func timeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
