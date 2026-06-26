import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scheduler = BreakScheduler()
    private let overlay = OverlayController()
    private var menu: MenuBarController!
    private var prefs: PreferencesController?
    private let history = HistoryController()
    private let medsEditor = MedicationEditorController()
    private let lockMonitor = LockMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "Stretch", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        menu = MenuBarController(scheduler: scheduler)
        menu.onPreferences = { [weak self] in self?.showPreferences() }
        menu.onHistory = { [weak self] in self?.history.show() }
        menu.onMedications = { [weak self] in self?.medsEditor.show() }

        MedicationManager.shared.start()

        scheduler.onTick = { [weak self] state in
            guard let self else { return }
            self.menu.update(state: state)
            MedicationManager.shared.tick()
            if case .breaking(_, let ends) = state {
                self.overlay.update(remaining: ends.timeIntervalSinceNow)
            }
        }
        scheduler.onBreakStart = { [weak self] type, duration in
            guard let self else { return }
            self.overlay.show(
                type: type,
                duration: duration,
                reminders: MedicationManager.shared.dueDoses(),
                onSkip: { [weak self] in self?.scheduler.skipBreak() },
                onSnooze: { [weak self] in self?.scheduler.snoozeBreak() },
                onDoseAction: { dose, action in
                    MedicationManager.shared.resolve(dose, action)
                }
            )
        }
        scheduler.onBreakEnd = { [weak self] in
            self?.overlay.hide()
        }
        scheduler.shouldSuppressBreak = { type in
            Settings.shared.suppressDuringPresentation && PresentationGuard.shouldSuppress(for: type)
        }
        scheduler.isUserAway = {
            IdleMonitor.secondsSinceInput() >= Settings.shared.idlePauseSeconds
        }

        lockMonitor.onLongAway = { [weak self] in
            self?.scheduler.resetAfterAwayBreak()
        }

        scheduler.start()
    }

    private func showPreferences() {
        if prefs == nil {
            prefs = PreferencesController(scheduler: scheduler)
            prefs?.onEditMedications = { [weak self] in self?.medsEditor.show() }
        }
        prefs?.show()
    }
}
