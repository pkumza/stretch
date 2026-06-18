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

    private var shortIntervalValue: NSTextField!
    private var shortDurationValue: NSTextField!
    private var longIntervalValue: NSTextField!
    private var longDurationValue: NSTextField!

    private var loginCheckbox: NSButton!

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
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
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

        shortIntervalStepper = sIStep; shortIntervalValue = sIVal
        shortDurationStepper = sDStep; shortDurationValue = sDVal
        longIntervalStepper  = lIStep; longIntervalValue  = lIVal
        longDurationStepper  = lDStep; longDurationValue  = lDVal

        loginCheckbox = NSButton(checkboxWithTitle: "Launch Stretch at login",
                                 target: self, action: #selector(toggleLogin(_:)))

        let stack = NSStackView(views: [
            shortIntervalRow, shortDurationRow, longIntervalRow, longDurationRow,
            NSBox.horizontalDivider(), loginCheckbox,
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

    // MARK: - Actions

    @objc private func changed() {
        settings.shortIntervalMinutes     = shortIntervalStepper.integerValue
        settings.shortDurationSecondsValue = shortDurationStepper.integerValue
        settings.longIntervalMinutes      = longIntervalStepper.integerValue
        settings.longDurationMinutes      = longDurationStepper.integerValue

        shortIntervalValue.stringValue = "\(settings.shortIntervalMinutes) min"
        shortDurationValue.stringValue = "\(settings.shortDurationSecondsValue) sec"
        longIntervalValue.stringValue  = "\(settings.longIntervalMinutes) min"
        longDurationValue.stringValue  = "\(settings.longDurationMinutes) min"

        scheduler.reschedule()
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
