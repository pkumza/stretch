import AppKit
import ServiceManagement

/// A small settings window: intervals, durations, and launch-at-login.
final class PreferencesController: NSObject {
    private var window: NSWindow?
    private let scheduler: BreakScheduler
    private let settings = Settings.shared

    private var shortIntervalStepper: NSStepper!
    private var shortDurationStepper: NSStepper!
    private var longIntervalStepper: NSStepper!
    private var longDurationStepper: NSStepper!
    private var idlePauseStepper: NSStepper!

    private var shortIntervalValue: NSTextField!
    private var shortDurationValue: NSTextField!
    private var longIntervalValue: NSTextField!
    private var longDurationValue: NSTextField!
    private var idlePauseValue: NSTextField!

    private var doseLeadStepper: NSStepper!
    private var doseCutoffStepper: NSStepper!
    private var doseLeadValue: NSTextField!
    private var doseCutoffValue: NSTextField!

    private var breakfastPicker: NSDatePicker!
    private var lunchPicker: NSDatePicker!
    private var dinnerPicker: NSDatePicker!
    private var wakeStartPicker: NSDatePicker!
    private var wakeEndPicker: NSDatePicker!

    private var loginCheckbox: NSButton!
    private var suppressCheckbox: NSButton!

    /// Opens the medication editor (wired by AppDelegate).
    var onEditMedications: (() -> Void)?

    init(scheduler: BreakScheduler) {
        self.scheduler = scheduler
        super.init()
    }

    func show() {
        if window == nil { window = buildWindow() }
        syncLoginCheckbox()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build

    private func buildWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "Stretch Preferences"
        win.isReleasedWhenClosed = false

        let (shortIntervalRow, sIStep, sIVal) =
            makeRow("Short break every", value: settings.shortIntervalMinutes, min: 1, max: 120, unit: "min")
        let (shortDurationRow, sDStep, sDVal) =
            makeRow("Short break lasts", value: settings.shortDurationSecondsValue, min: 5, max: 600, unit: "sec")
        let (longIntervalRow, lIStep, lIVal) =
            makeRow("Long break every", value: settings.longIntervalMinutes, min: 5, max: 240, unit: "min")
        let (longDurationRow, lDStep, lDVal) =
            makeRow("Long break lasts", value: settings.longDurationMinutes, min: 1, max: 60, unit: "min")
        let (idlePauseRow, idStep, idVal) =
            makeRow("Pause when idle for", value: settings.idlePauseMinutes, min: 1, max: 60, unit: "min")

        shortIntervalStepper = sIStep; shortIntervalValue = sIVal
        shortDurationStepper = sDStep; shortDurationValue = sDVal
        longIntervalStepper  = lIStep; longIntervalValue  = lIVal
        longDurationStepper  = lDStep; longDurationValue  = lDVal
        idlePauseStepper     = idStep; idlePauseValue     = idVal

        let (leadRow, leadStep, leadVal) =
            makeRow("Remind dose up to", value: settings.doseLeadMinutes, min: 0, max: 120, unit: "min")
        let (expiryRow, expStep, expVal) =
            makeRow("Skip dose if untaken after", value: settings.doseCutoffMinutes, min: 5, max: 720, unit: "min")
        doseLeadStepper = leadStep; doseLeadValue = leadVal
        doseCutoffStepper = expStep; doseCutoffValue = expVal

        let mt = settings.mealTimes
        let ww = settings.wakingWindow
        let (breakfastRow, bP) = makeTimeRow("Breakfast", minutes: mt.breakfastMin)
        let (lunchRow, lP)     = makeTimeRow("Lunch", minutes: mt.lunchMin)
        let (dinnerRow, dP)    = makeTimeRow("Dinner", minutes: mt.dinnerMin)
        let (wakeStartRow, wsP) = makeTimeRow("Awake from", minutes: ww.startMin)
        let (wakeEndRow, weP)   = makeTimeRow("Awake until", minutes: ww.endMin)
        breakfastPicker = bP; lunchPicker = lP; dinnerPicker = dP
        wakeStartPicker = wsP; wakeEndPicker = weP

        let medsHeader = sectionLabel("Medications")
        let editMedsButton = NSButton(title: "Edit medications…", target: self,
                                      action: #selector(editMedsTapped))
        editMedsButton.bezelStyle = .rounded

        loginCheckbox = NSButton(checkboxWithTitle: "Launch Stretch at login",
                                 target: self, action: #selector(toggleLogin(_:)))

        suppressCheckbox = NSButton(checkboxWithTitle: "Don't interrupt when the microphone is in use",
                                    target: self, action: #selector(toggleSuppress(_:)))
        suppressCheckbox.state = settings.suppressDuringPresentation ? .on : .off

        let stack = NSStackView(views: [
            shortIntervalRow, shortDurationRow, longIntervalRow, longDurationRow,
            idlePauseRow,
            NSBox.horizontalDivider(), suppressCheckbox, loginCheckbox,
            NSBox.horizontalDivider(), medsHeader,
            breakfastRow, lunchRow, dinnerRow, wakeStartRow, wakeEndRow,
            leadRow, expiryRow, editMedsButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])
        win.contentView = content
        return win
    }

    private func makeRow(_ title: String, value: Int, min: Int, max: Int, unit: String)
        -> (NSView, NSStepper, NSTextField) {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let stepper = NSStepper()
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.increment = unit == "sec" ? 5 : 1
        stepper.integerValue = value
        stepper.target = self
        stepper.action = #selector(changed)

        let valueField = NSTextField(labelWithString: "\(value) \(unit)")
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let row = NSStackView(views: [label, stepper, valueField])
        row.orientation = .horizontal
        row.spacing = 10
        return (row, stepper, valueField)
    }

    private func makeTimeRow(_ title: String, minutes: Int) -> (NSView, NSDatePicker) {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Self.date(fromMinutes: minutes)
        picker.target = self
        picker.action = #selector(mealTimesChanged)

        let row = NSStackView(views: [label, picker])
        row.orientation = .horizontal
        row.spacing = 10
        return (row, picker)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: - Actions

    @objc private func changed() {
        settings.shortIntervalMinutes     = shortIntervalStepper.integerValue
        settings.shortDurationSecondsValue = shortDurationStepper.integerValue
        settings.longIntervalMinutes      = longIntervalStepper.integerValue
        settings.longDurationMinutes      = longDurationStepper.integerValue
        settings.idlePauseMinutes         = idlePauseStepper.integerValue

        settings.doseLeadMinutes          = doseLeadStepper.integerValue
        settings.doseCutoffMinutes        = doseCutoffStepper.integerValue

        shortIntervalValue.stringValue = "\(settings.shortIntervalMinutes) min"
        shortDurationValue.stringValue = "\(settings.shortDurationSecondsValue) sec"
        longIntervalValue.stringValue  = "\(settings.longIntervalMinutes) min"
        longDurationValue.stringValue  = "\(settings.longDurationMinutes) min"
        idlePauseValue.stringValue     = "\(settings.idlePauseMinutes) min"
        doseLeadValue.stringValue      = "\(settings.doseLeadMinutes) min"
        doseCutoffValue.stringValue    = "\(settings.doseCutoffMinutes) min"

        scheduler.reschedule()
        MedicationManager.shared.rebuildToday(for: Date())
    }

    @objc private func mealTimesChanged() {
        settings.mealTimes = MealTimes(
            breakfastMin: Self.minutes(from: breakfastPicker.dateValue),
            lunchMin: Self.minutes(from: lunchPicker.dateValue),
            dinnerMin: Self.minutes(from: dinnerPicker.dateValue))
        settings.wakingWindow = WakingWindow(
            startMin: Self.minutes(from: wakeStartPicker.dateValue),
            endMin: Self.minutes(from: wakeEndPicker.dateValue))
        MedicationManager.shared.rebuildToday(for: Date())
    }

    @objc private func editMedsTapped() { onEditMedications?() }

    @objc private func toggleSuppress(_ sender: NSButton) {
        settings.suppressDuringPresentation = sender.state == .on
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        guard #available(macOS 13, *) else { return }
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Unsigned/dev builds may not support this; revert the checkbox.
            sender.state = sender.state == .on ? .off : .on
            NSSound.beep()
        }
    }

    private func syncLoginCheckbox() {
        guard #available(macOS 13, *) else { loginCheckbox.isEnabled = false; return }
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

private extension NSBox {
    static func horizontalDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return box
    }
}
