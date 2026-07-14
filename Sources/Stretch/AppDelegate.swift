import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scheduler = BreakScheduler()
    private let overlay = OverlayController()
    private let paper = PaperModeController()
    private let bedtime = BedtimeScheduler()
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

        menu = MenuBarController(scheduler: scheduler, bedtime: bedtime)
        menu.onPreferences = { [weak self] in self?.showPreferences() }
        menu.onHistory = { [weak self] in self?.history.show() }
        menu.onMedications = { [weak self] in self?.medsEditor.show() }
        menu.onBedtimeSettingsChanged = { [weak self] in
            self?.bedtime.refresh()
            if self?.bedtime.isActive == true {
                self?.paper.refreshAppearance()
                self?.applyGammaIfNeeded(active: true)
            }
        }

        MedicationManager.shared.start()

        bedtime.onChange = { [weak self] active in
            guard let self else { return }
            self.paper.setActive(active)
            self.applyGammaIfNeeded(active: active)
            self.menu.updateBedtime(active: active)
        }

        scheduler.onTick = { [weak self] state in
            guard let self else { return }
            self.menu.update(state: state, holdReason: self.holdReason(for: state))
            MedicationManager.shared.tick()
            self.bedtime.tick()
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

        bedtime.start()
        scheduler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        paper.setActive(false)
        DisplayGamma.restore()
    }

    private func applyGammaIfNeeded(active: Bool) {
        // Gamma is the transition-safe dimming layer: macOS hides NSWindow overlays
        // during four-finger Space swipes, but the display transfer table stays on.
        if active {
            DisplayGamma.applyBedtime(intensity: Settings.shared.paperIntensity)
        } else {
            DisplayGamma.restore()
        }
    }

    private func holdReason(for state: SchedulerState) -> PresentationGuard.HoldReason? {
        guard Settings.shared.suppressDuringPresentation,
              case .working(_, let type) = state else { return nil }
        return PresentationGuard.holdReason(for: type)
    }

    private func showPreferences() {
        if prefs == nil {
            prefs = PreferencesController(scheduler: scheduler, bedtime: bedtime)
            prefs?.onEditMedications = { [weak self] in self?.medsEditor.show() }
            prefs?.onBedtimeSettingsChanged = { [weak self] in
                self?.bedtime.refresh()
                if self?.bedtime.isActive == true {
                    self?.paper.refreshAppearance()
                    self?.applyGammaIfNeeded(active: true)
                } else {
                    self?.paper.setActive(false)
                    self?.applyGammaIfNeeded(active: false)
                }
                self?.menu.updateBedtime(active: self?.bedtime.isActive == true)
            }
        }
        prefs?.show()
    }
}
