import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scheduler = BreakScheduler()
    private let overlay = OverlayController()
    private let paper = PaperModeController()
    private let bedtime = BedtimeScheduler()
    private let hotKeys = HotKeyController()
    private var menu: MenuBarController!
    private var prefs: PreferencesController?
    private let history = HistoryController()
    private let medsEditor = MedicationEditorController()
    private let lockMonitor = LockMonitor()

    /// 0…1 bedtime visual strength (paper + gamma).
    private var bedtimeProgress: Double = 0
    private var bedtimeTransition: Timer?
    private let bedtimeFadeDuration: TimeInterval = 3.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "Stretch", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        // Default: open at login. User can turn off in Preferences.
        LaunchAtLogin.applyPreference()

        menu = MenuBarController(scheduler: scheduler, bedtime: bedtime)
        menu.onPreferences = { [weak self] in self?.showPreferences() }
        menu.onHistory = { [weak self] in self?.history.show() }
        menu.onMedications = { [weak self] in self?.medsEditor.show() }
        menu.onBedtimeSettingsChanged = { [weak self] in
            self?.handleBedtimeSettingsChanged()
        }

        MedicationManager.shared.start()

        bedtime.onChange = { [weak self] active in
            guard let self else { return }
            self.menu.updateBedtime(active: active)
            self.transitionBedtime(to: active, showToast: active)
        }

        hotKeys.onToggleBedtime = { [weak self] in
            guard let self else { return }
            if self.bedtime.isActive {
                self.bedtime.dismissUntilMorning()
            } else {
                self.bedtime.activateNow()
            }
            self.menu.updateBedtime(active: self.bedtime.isActive)
        }
        hotKeys.onSnoozeBedtime = { [weak self] in
            guard let self, self.bedtime.isActive else { return }
            self.bedtime.snooze(minutes: 15)
            self.menu.updateBedtime(active: self.bedtime.isActive)
        }
        hotKeys.start()

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
        lockMonitor.onUnlock = { [weak self] in
            guard let self, self.bedtime.isActive else { return }
            // Stay at full strength — don't replay the fade/toast after unlock.
            self.bedtimeProgress = 1
            self.paper.prepare(initialOpacity: 1)
            self.paper.setOpacity(1)
            self.applyDisplayEffects(progress: 1)
        }

        bedtime.start()
        scheduler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        bedtimeTransition?.invalidate()
        hotKeys.stop()
        paper.setActive(false)
        applyDisplayEffects(progress: 0)
    }

    // MARK: - Bedtime fade (3s)

    private func transitionBedtime(to active: Bool, showToast: Bool) {
        bedtimeTransition?.invalidate()
        bedtimeTransition = nil

        if active {
            paper.prepare(initialOpacity: bedtimeProgress)
            if showToast {
                paper.showActivationToast(duration: bedtimeFadeDuration)
            }
        } else {
            // Drop accessibility filter immediately on the way out.
            AccessibilityColorFilter.restore()
        }

        let start = bedtimeProgress
        let end: Double = active ? 1 : 0
        if abs(start - end) < 0.001 {
            applyDisplayEffects(progress: end)
            paper.setOpacity(CGFloat(end))
            if !active { paper.setActive(false) }
            if active, Settings.shared.bedtimeUseGrayscale {
                AccessibilityColorFilter.enableGrayscale()
            }
            return
        }

        let t0 = Date()
        let duration = bedtimeFadeDuration
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let u = min(1, Date().timeIntervalSince(t0) / duration)
            // Smoothstep ease-in-out.
            let eased = u * u * (3 - 2 * u)
            let p = start + (end - start) * eased
            self.bedtimeProgress = p
            self.paper.setOpacity(CGFloat(p))
            self.applyDisplayEffects(progress: p)

            if u >= 1 {
                timer.invalidate()
                self.bedtimeTransition = nil
                self.bedtimeProgress = end
                if active {
                    if Settings.shared.bedtimeUseGrayscale {
                        AccessibilityColorFilter.enableGrayscale()
                    }
                } else {
                    self.paper.setActive(false)
                    self.applyDisplayEffects(progress: 0)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        bedtimeTransition = timer
        timer.fire()
    }

    /// Gamma (+ grayscale only when fully on — handled by caller).
    private func applyDisplayEffects(progress: Double) {
        let settings = Settings.shared
        if progress <= 0.001 {
            DisplayGamma.restore()
            return
        }
        if settings.bedtimeUseGamma {
            DisplayGamma.apply(progress: Float(progress), intensity: settings.paperIntensity)
        } else if progress >= 0.999 {
            DisplayGamma.restore()
        }
    }

    private func handleBedtimeSettingsChanged() {
        bedtime.refresh()
        menu.updateBedtime(active: bedtime.isActive)
        if bedtime.isActive {
            // Preference tweaks while already on: refresh look at current strength.
            if bedtimeProgress < 0.01 {
                transitionBedtime(to: true, showToast: true)
            } else {
                paper.refreshAppearance()
                bedtimeProgress = 1
                paper.setOpacity(1)
                applyDisplayEffects(progress: 1)
                if Settings.shared.bedtimeUseGrayscale {
                    AccessibilityColorFilter.enableGrayscale()
                } else {
                    AccessibilityColorFilter.restore()
                }
            }
        } else {
            transitionBedtime(to: false, showToast: false)
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
                self?.handleBedtimeSettingsChanged()
            }
        }
        prefs?.show()
    }
}
