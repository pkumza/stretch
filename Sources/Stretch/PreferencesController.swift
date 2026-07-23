import AppKit

/// Settings window with toolbar tabs: Breaks, Bedtime, and Medications.
final class PreferencesController: NSObject, NSToolbarDelegate {
    private enum Tab: Int {
        case breaks = 0
        case bedtime = 1
        case medications = 2
    }

    private static let toolbarBreaks = NSToolbarItem.Identifier("Breaks")
    private static let toolbarBedtime = NSToolbarItem.Identifier("Bedtime")
    private static let toolbarMedications = NSToolbarItem.Identifier("Medications")
    private static let titleColumnWidth: CGFloat = 96

    private var window: NSWindow?
    private var tabView: NSTabView!
    private var toolbar: NSToolbar!

    private let scheduler: BreakScheduler
    private let bedtime: BedtimeScheduler
    private let settings = Settings.shared

    private var shortIntervalStepper: NSStepper!
    private var shortDurationStepper: NSStepper!
    private var longIntervalStepper: NSStepper!
    private var longDurationStepper: NSStepper!

    private var shortIntervalValue: NSTextField!
    private var shortDurationValue: NSTextField!
    private var longIntervalValue: NSTextField!
    private var longDurationValue: NSTextField!

    private var doseLeadStepper: NSStepper!
    private var doseCutoffStepper: NSStepper!
    private var doseLeadValue: NSTextField!
    private var doseCutoffValue: NSTextField!

    private var breakfastPicker: NSDatePicker!
    private var lunchPicker: NSDatePicker!
    private var dinnerPicker: NSDatePicker!
    private var wakeStartPicker: NSDatePicker!
    private var wakeEndPicker: NSDatePicker!

    private var bedtimeEnabledCheckbox: NSButton!
    private var bedtimeStartPicker: NSDatePicker!
    private var bedtimeEndPicker: NSDatePicker!
    private var intensityControl: NSSegmentedControl!
    private var bedtimeGammaCheckbox: NSButton!
    private var bedtimeGrayscaleCheckbox: NSButton!
    private var bedtimeDependentViews: [NSView] = []

    private var loginCheckbox: NSButton!
    private var suppressCheckbox: NSButton!

    private var helpPopover: NSPopover?

    /// Opens the medication editor (wired by AppDelegate).
    var onEditMedications: (() -> Void)?
    /// Fired when bedtime prefs change so paper mode can refresh.
    var onBedtimeSettingsChanged: (() -> Void)?

    init(scheduler: BreakScheduler, bedtime: BedtimeScheduler) {
        self.scheduler = scheduler
        self.bedtime = bedtime
        super.init()
    }

    func show() {
        if window == nil { window = buildWindow() }
        syncLoginCheckbox()
        syncBedtimeControls()
        selectTab(.breaks)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build

    private func buildWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "Stretch Preferences"
        win.isReleasedWhenClosed = false

        tabView = NSTabView()
        tabView.tabViewType = .noTabsNoBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let breaksTab = NSTabViewItem()
        breaksTab.view = buildBreaksPane()
        tabView.addTabViewItem(breaksTab)

        let bedtimeTab = NSTabViewItem()
        bedtimeTab.view = buildBedtimePane()
        tabView.addTabViewItem(bedtimeTab)

        let medsTab = NSTabViewItem()
        medsTab.view = buildMedicationsPane()
        tabView.addTabViewItem(medsTab)

        let content = NSView()
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: content.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        win.contentView = content

        toolbar = NSToolbar(identifier: "StretchPreferencesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        if #available(macOS 11.0, *) {
            win.toolbarStyle = .preference
        }
        win.toolbar = toolbar

        return win
    }

    private func buildBreaksPane() -> NSView {
        let (shortBar, sIStep, sDStep, sIVal, sDVal) = makeBreakBar(
            title: "Short",
            everyValue: settings.shortIntervalMinutes, everyMin: 1, everyMax: 120, everyUnit: "min",
            lastsValue: settings.shortDurationSecondsValue, lastsMin: 5, lastsMax: 600, lastsUnit: "sec")
        let (longBar, lIStep, lDStep, lIVal, lDVal) = makeBreakBar(
            title: "Long",
            everyValue: settings.longIntervalMinutes, everyMin: 5, everyMax: 240, everyUnit: "min",
            lastsValue: settings.longDurationMinutes, lastsMin: 1, lastsMax: 60, lastsUnit: "min")
        shortIntervalStepper = sIStep; shortDurationStepper = sDStep
        shortIntervalValue = sIVal; shortDurationValue = sDVal
        longIntervalStepper = lIStep; longDurationStepper = lDStep
        longIntervalValue = lIVal; longDurationValue = lDVal

        suppressCheckbox = NSButton(
            checkboxWithTitle: "Don't interrupt when the microphone is in use",
            target: self, action: #selector(toggleSuppress(_:)))
        suppressCheckbox.state = settings.suppressDuringPresentation ? .on : .off

        loginCheckbox = NSButton(
            checkboxWithTitle: "Launch Stretch at login",
            target: self, action: #selector(toggleLogin(_:)))

        let optionsBar = makeOptionsBar(views: [suppressCheckbox, loginCheckbox])

        return paneStack(views: [shortBar, longBar, optionsBar])
    }

    private func buildBedtimePane() -> NSView {
        bedtimeEnabledCheckbox = NSButton(
            checkboxWithTitle: "Dim the screen to a paper look at bedtime",
            target: self, action: #selector(bedtimeChanged))
        let enableBar = makeOptionsBar(views: [bedtimeEnabledCheckbox])

        let startPicker = makeTimePicker(minutes: settings.bedtimeStartMin, action: #selector(bedtimeChanged))
        let endPicker = makeTimePicker(minutes: settings.bedtimeEndMin, action: #selector(bedtimeChanged))
        bedtimeStartPicker = startPicker
        bedtimeEndPicker = endPicker
        let scheduleBar = makeSettingBar(
            title: "Schedule",
            controls: [
                makeLabeledControl(caption: "Starts", control: startPicker),
                makeVerticalDivider(),
                makeLabeledControl(caption: "Ends", control: endPicker),
            ])

        intensityControl = NSSegmentedControl(
            labels: Settings.PaperIntensity.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(bedtimeChanged))
        intensityControl.selectedSegment = settings.paperIntensity.rawValue
        intensityControl.controlSize = .regular
        let intensityBar = makeSettingBar(title: "Intensity", controls: [intensityControl])

        bedtimeGammaCheckbox = NSButton(
            checkboxWithTitle: "Warm & dim via display gamma (recommended)",
            target: self, action: #selector(bedtimeChanged))
        bedtimeGrayscaleCheckbox = NSButton(
            checkboxWithTitle: "Also enable system grayscale (Color Filters)",
            target: self, action: #selector(bedtimeChanged))
        let optionsBar = makeOptionsBar(views: [bedtimeGammaCheckbox, bedtimeGrayscaleCheckbox])

        let shortcutsLabel = NSTextField(labelWithString: "⌘⇧B toggle · ⌘⇧S snooze 15 min")
        shortcutsLabel.font = .systemFont(ofSize: 11)
        shortcutsLabel.textColor = .secondaryLabelColor

        let helpButton = NSButton(title: "?", target: self, action: #selector(showBedtimeHelp(_:)))
        helpButton.bezelStyle = .helpButton
        helpButton.title = ""
        helpButton.controlSize = .small

        let footer = NSStackView(views: [shortcutsLabel, helpButton])
        footer.orientation = .horizontal
        footer.spacing = 6
        footer.alignment = .centerY

        bedtimeDependentViews = [scheduleBar, intensityBar, optionsBar]
        return paneStack(views: [enableBar, scheduleBar, intensityBar, optionsBar, footer])
    }

    private func buildMedicationsPane() -> NSView {
        let mt = settings.mealTimes
        let ww = settings.wakingWindow

        let breakfast = makeTimePicker(minutes: mt.breakfastMin, action: #selector(mealTimesChanged))
        let lunch = makeTimePicker(minutes: mt.lunchMin, action: #selector(mealTimesChanged))
        let dinner = makeTimePicker(minutes: mt.dinnerMin, action: #selector(mealTimesChanged))
        breakfastPicker = breakfast; lunchPicker = lunch; dinnerPicker = dinner
        let mealsBar = makeMultiRowBar(title: "Meals", rows: [
            ("Breakfast", breakfast),
            ("Lunch", lunch),
            ("Dinner", dinner),
        ])

        let wakeStart = makeTimePicker(minutes: ww.startMin, action: #selector(mealTimesChanged))
        let wakeEnd = makeTimePicker(minutes: ww.endMin, action: #selector(mealTimesChanged))
        wakeStartPicker = wakeStart
        wakeEndPicker = wakeEnd
        let awakeBar = makeSettingBar(
            title: "Awake",
            controls: [
                makeLabeledControl(caption: "from", control: wakeStart),
                makeVerticalDivider(),
                makeLabeledControl(caption: "until", control: wakeEnd),
            ])

        let (remindBar, leadStep, leadVal) = makeStepperBar(
            title: "Remind",
            prefix: "up to",
            value: settings.doseLeadMinutes, min: 0, max: 120, unit: "min")
        let (skipBar, skipStep, skipVal) = makeStepperBar(
            title: "Skip after",
            prefix: "",
            value: settings.doseCutoffMinutes, min: 5, max: 720, unit: "min")
        doseLeadStepper = leadStep; doseLeadValue = leadVal
        doseCutoffStepper = skipStep; doseCutoffValue = skipVal

        let editMedsButton = NSButton(title: "Edit medications…", target: self,
                                      action: #selector(editMedsTapped))
        editMedsButton.bezelStyle = .rounded

        return paneStack(views: [mealsBar, awakeBar, remindBar, skipBar, editMedsButton])
    }

    private func paneStack(views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
        ])
        return container
    }

    // MARK: - Bar helpers

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeVerticalDivider() -> NSView {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return divider
    }

    private func makeLabeledControl(caption: String, control: NSView) -> NSView {
        let group = NSStackView(views: [secondaryLabel(caption), control])
        group.orientation = .horizontal
        group.spacing = 6
        group.alignment = .centerY
        return group
    }

    private func makeSettingBar(title: String, controls: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: Self.titleColumnWidth).isActive = true
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controlsStack = NSStackView(views: controls)
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 10
        controlsStack.alignment = .centerY

        let row = NSStackView(views: [titleLabel, spacer, controlsStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        return wrapInBar(row)
    }

    private func makeOptionsBar(views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return wrapInBar(stack, horizontalPadding: 14, verticalPadding: 10)
    }

    private func wrapInBar(_ content: NSView,
                           horizontalPadding: CGFloat = 14,
                           verticalPadding: CGFloat = 10) -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 8
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        bar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        bar.layer?.borderWidth = 1
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: horizontalPadding),
            content.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -horizontalPadding),
            content.topAnchor.constraint(equalTo: bar.topAnchor, constant: verticalPadding),
            content.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -verticalPadding),
        ])
        return bar
    }

    private func makeCompactStepper(
        prefix: String, value: Int, min: Int, max: Int, unit: String
    ) -> (NSView, NSStepper, NSTextField) {
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.increment = unit == "sec" ? 5 : 1
        stepper.integerValue = value
        stepper.target = self
        stepper.action = #selector(changed)

        let valueField = NSTextField(labelWithString: "\(value)")
        valueField.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueField.alignment = .center
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.widthAnchor.constraint(equalToConstant: 32).isActive = true

        var parts: [NSView] = []
        if !prefix.isEmpty { parts.append(secondaryLabel(prefix)) }
        parts.append(contentsOf: [valueField, stepper, secondaryLabel(unit)])

        let group = NSStackView(views: parts)
        group.orientation = .horizontal
        group.spacing = 4
        group.alignment = .centerY
        return (group, stepper, valueField)
    }

    private func makeBreakBar(
        title: String,
        everyValue: Int, everyMin: Int, everyMax: Int, everyUnit: String,
        lastsValue: Int, lastsMin: Int, lastsMax: Int, lastsUnit: String
    ) -> (NSView, NSStepper, NSStepper, NSTextField, NSTextField) {
        let (everyGroup, everyStep, everyVal) =
            makeCompactStepper(prefix: "every", value: everyValue, min: everyMin, max: everyMax, unit: everyUnit)
        let (lastsGroup, lastsStep, lastsVal) =
            makeCompactStepper(prefix: "lasts", value: lastsValue, min: lastsMin, max: lastsMax, unit: lastsUnit)
        let bar = makeSettingBar(title: title, controls: [everyGroup, makeVerticalDivider(), lastsGroup])
        return (bar, everyStep, lastsStep, everyVal, lastsVal)
    }

    private func makeStepperBar(
        title: String, prefix: String, value: Int, min: Int, max: Int, unit: String
    ) -> (NSView, NSStepper, NSTextField) {
        let (group, stepper, valueField) =
            makeCompactStepper(prefix: prefix, value: value, min: min, max: max, unit: unit)
        let bar = makeSettingBar(title: title, controls: [group])
        return (bar, stepper, valueField)
    }

    private func makeMultiRowBar(title: String, rows: [(String, NSView)]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: Self.titleColumnWidth).isActive = true
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let rowViews: [NSView] = rows.map { caption, control in
            let captionLabel = secondaryLabel(caption)
            captionLabel.translatesAutoresizingMaskIntoConstraints = false
            captionLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true
            let row = NSStackView(views: [captionLabel, control])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            return row
        }
        let rowsStack = NSStackView(views: rowViews)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let content = NSStackView(views: [titleLabel, spacer, rowsStack])
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 8
        return wrapInBar(content)
    }

    private func makeTimePicker(minutes: Int, action: Selector) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Self.date(fromMinutes: minutes)
        picker.target = self
        picker.action = action
        picker.controlSize = .small
        return picker
    }

    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func syncBedtimeControls() {
        bedtimeEnabledCheckbox.state = settings.bedtimeEnabled ? .on : .off
        bedtimeStartPicker.dateValue = Self.date(fromMinutes: settings.bedtimeStartMin)
        bedtimeEndPicker.dateValue = Self.date(fromMinutes: settings.bedtimeEndMin)
        intensityControl.selectedSegment = settings.paperIntensity.rawValue
        bedtimeGammaCheckbox.state = settings.bedtimeUseGamma ? .on : .off
        bedtimeGrayscaleCheckbox.state = settings.bedtimeUseGrayscale ? .on : .off
        updateBedtimeEnabledState()
    }

    private func updateBedtimeEnabledState() {
        let on = bedtimeEnabledCheckbox.state == .on
        bedtimeStartPicker.isEnabled = on
        bedtimeEndPicker.isEnabled = on
        intensityControl.isEnabled = on
        bedtimeGammaCheckbox.isEnabled = on
        bedtimeGrayscaleCheckbox.isEnabled = on
        for view in bedtimeDependentViews {
            view.alphaValue = on ? 1.0 : 0.45
        }
    }

    private func selectTab(_ tab: Tab) {
        tabView.selectTabViewItem(at: tab.rawValue)
        toolbar.selectedItemIdentifier = Self.toolbarIdentifier(for: tab)
    }

    private static func toolbarIdentifier(for tab: Tab) -> NSToolbarItem.Identifier {
        switch tab {
        case .breaks: return toolbarBreaks
        case .bedtime: return toolbarBedtime
        case .medications: return toolbarMedications
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toolbarBreaks, Self.toolbarBedtime, Self.toolbarMedications]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toolbarBreaks, Self.toolbarBedtime, Self.toolbarMedications]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toolbarBreaks, Self.toolbarBedtime, Self.toolbarMedications]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case Self.toolbarBreaks:
            item.label = "Breaks"
            item.paletteLabel = "Breaks"
            item.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Breaks")
            item.target = self
            item.action = #selector(toolbarBreaksTapped)
        case Self.toolbarBedtime:
            item.label = "Bedtime"
            item.paletteLabel = "Bedtime"
            item.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Bedtime")
            item.target = self
            item.action = #selector(toolbarBedtimeTapped)
        case Self.toolbarMedications:
            item.label = "Medications"
            item.paletteLabel = "Medications"
            item.image = NSImage(systemSymbolName: "pills", accessibilityDescription: "Medications")
            item.target = self
            item.action = #selector(toolbarMedicationsTapped)
        default:
            return nil
        }
        return item
    }

    // MARK: - Actions

    @objc private func toolbarBreaksTapped() { selectTab(.breaks) }
    @objc private func toolbarBedtimeTapped() { selectTab(.bedtime) }
    @objc private func toolbarMedicationsTapped() { selectTab(.medications) }

    @objc private func changed() {
        settings.shortIntervalMinutes = shortIntervalStepper.integerValue
        settings.shortDurationSecondsValue = shortDurationStepper.integerValue
        settings.longIntervalMinutes = longIntervalStepper.integerValue
        settings.longDurationMinutes = longDurationStepper.integerValue

        settings.doseLeadMinutes = doseLeadStepper.integerValue
        settings.doseCutoffMinutes = doseCutoffStepper.integerValue

        shortIntervalValue.stringValue = "\(settings.shortIntervalMinutes)"
        shortDurationValue.stringValue = "\(settings.shortDurationSecondsValue)"
        longIntervalValue.stringValue = "\(settings.longIntervalMinutes)"
        longDurationValue.stringValue = "\(settings.longDurationMinutes)"
        doseLeadValue.stringValue = "\(settings.doseLeadMinutes)"
        doseCutoffValue.stringValue = "\(settings.doseCutoffMinutes)"

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

    @objc private func bedtimeChanged() {
        settings.bedtimeEnabled = bedtimeEnabledCheckbox.state == .on
        settings.bedtimeStartMin = Self.minutes(from: bedtimeStartPicker.dateValue)
        settings.bedtimeEndMin = Self.minutes(from: bedtimeEndPicker.dateValue)
        let seg = intensityControl.selectedSegment
        settings.paperIntensity = Settings.PaperIntensity(rawValue: seg) ?? .medium
        settings.bedtimeUseGamma = bedtimeGammaCheckbox.state == .on
        settings.bedtimeUseGrayscale = bedtimeGrayscaleCheckbox.state == .on
        if settings.bedtimeEnabled {
            settings.bedtimeSnoozeUntil = .distantPast
            settings.bedtimeDismissedUntil = .distantPast
        }
        updateBedtimeEnabledState()
        bedtime.refresh()
        onBedtimeSettingsChanged?()
    }

    @objc private func showBedtimeHelp(_ sender: NSButton) {
        if helpPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            let text = NSTextField(wrappingLabelWithString:
                "Brightness comes from display gamma (stable across desktop swipes). The paper layer is a faint warm tint. Optional grayscale uses Accessibility Color Filters — no Screen Recording.")
            text.font = .systemFont(ofSize: 11)
            text.preferredMaxLayoutWidth = 280
            let vc = NSViewController()
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            text.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(text)
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
                text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
                text.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
                text.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            ])
            vc.view = view
            popover.contentViewController = vc
            helpPopover = popover
        }
        helpPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func editMedsTapped() { onEditMedications?() }

    @objc private func toggleSuppress(_ sender: NSButton) {
        settings.suppressDuringPresentation = sender.state == .on
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        guard #available(macOS 13, *) else { return }
        let wantOn = sender.state == .on
        if !LaunchAtLogin.setEnabled(wantOn) {
            sender.state = wantOn ? .off : .on
            NSSound.beep()
        }
    }

    private func syncLoginCheckbox() {
        guard #available(macOS 13, *) else { loginCheckbox.isEnabled = false; return }
        loginCheckbox.state = settings.launchAtLogin ? .on : .off
    }
}
