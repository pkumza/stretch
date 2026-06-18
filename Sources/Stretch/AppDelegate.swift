import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scheduler = BreakScheduler()
    private let overlay = OverlayController()
    private var menu: MenuBarController!
    private var prefs: PreferencesController?
    private let history = HistoryController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuBarController(scheduler: scheduler)
        menu.onPreferences = { [weak self] in self?.showPreferences() }
        menu.onHistory = { [weak self] in self?.history.show() }

        scheduler.onTick = { [weak self] state in
            guard let self else { return }
            self.menu.update(state: state)
            if case .breaking(_, let ends) = state {
                self.overlay.update(remaining: ends.timeIntervalSinceNow)
            }
        }
        scheduler.onBreakStart = { [weak self] type, duration in
            guard let self else { return }
            self.overlay.show(
                type: type,
                duration: duration,
                onSkip: { [weak self] in self?.scheduler.skipBreak() },
                onSnooze: { [weak self] in self?.scheduler.snoozeBreak() }
            )
        }
        scheduler.onBreakEnd = { [weak self] in
            self?.overlay.hide()
        }

        scheduler.start()
    }

    private func showPreferences() {
        if prefs == nil { prefs = PreferencesController(scheduler: scheduler) }
        prefs?.show()
    }
}
