import AppKit

/// Owns the status-bar item and its menu, and keeps the countdown label fresh.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let scheduler: BreakScheduler
    private var statusLine: NSMenuItem!

    var onPreferences: (() -> Void)?
    var onHistory: (() -> Void)?
    var onMedications: (() -> Void)?

    init(scheduler: BreakScheduler) {
        self.scheduler = scheduler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        setImage("figure.mind.and.body")
        statusItem.button?.imagePosition = .imageLeading
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

    private func setImage(_ symbol: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Stretch")
    }

    // MARK: - Live updates

    func update(state: SchedulerState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .working(let nextBreak, let type):
            let r = max(0, nextBreak.timeIntervalSinceNow)
            button.title = " " + Self.clock(r)
            setImage("figure.mind.and.body")
            statusLine.title = type.isLong
                ? "Next: long break in \(Self.clock(r))"
                : "Next: break in \(Self.clock(r))"

        case .breaking(let type, let ends):
            let r = max(0, ends.timeIntervalSinceNow)
            button.title = " " + Self.clock(r)
            setImage("cup.and.saucer.fill")
            statusLine.title = (type.isLong ? "Long break — " : "Short break — ")
                + Self.clock(r) + " left"

        case .paused(let until):
            button.title = ""
            setImage("pause.circle")
            if let until = until {
                statusLine.title = "Paused until " + Self.timeOfDay(until)
            } else {
                statusLine.title = "Paused"
            }
        }
    }

    // MARK: - Actions

    @objc private func shortNow()   { scheduler.takeBreakNow(.short) }
    @objc private func longNow()    { scheduler.takeBreakNow(.long) }
    @objc private func resetTimer() { scheduler.reschedule() }
    @objc private func pause30()    { scheduler.pause(for: 30 * 60) }
    @objc private func pause60()    { scheduler.pause(for: 60 * 60) }
    @objc private func pauseInf()   { scheduler.pause(for: nil) }
    @objc private func resumeNow()  { scheduler.resume() }
    @objc private func openPrefs()  { onPreferences?() }
    @objc private func openHistory() { onHistory?() }
    @objc private func openMeds()   { onMedications?() }
    @objc private func quit()       { NSApp.terminate(nil) }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Stretch"
        alert.informativeText = "A tiny break reminder.\nShort breaks to rest your eyes, longer breaks to move.\n\nCreated by Ziang and Claude Code.\nStay healthy. 🧘"
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Formatting

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func timeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
