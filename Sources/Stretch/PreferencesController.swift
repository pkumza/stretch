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

    private var bedtimeEnabledCheckbox: NSButton!
    private var bedtimeStartPicker: NSDatePicker!
    private var bedtimeEndPicker: NSDatePicker!
    private var intensityControl: NSSegmentedControl!
    private var bedtimeGammaCheckbox: NSButton!
    private var bedtimeGrayscaleCheckbox: NSButton!

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
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
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
        let (shortRow, sIStep, sDStep, sIVal, sDVal) = makeDualFieldRow(
            label: "Short break",
            leftTitle: "every", leftValue: settings.shortIntervalMinutes, leftMin: 1, leftMax: 120, leftUnit: "min",
            rightTitle: "lasts", rightValue: settings.shortDurationSecondsValue, rightMin: 5, rightMax: 600, rightUnit: "sec")
        let (longRow, lIStep, lDStep, lIVal, lDVal) = makeDualFieldRow(
            label: "Long break",
            leftTitle: "every", leftValue: settings.longIntervalMinutes, leftMin: 5, leftMax: 240, leftUnit: "min",
            rightTitle: "lasts", rightValue: settings.longDurationMinutes, rightMin: 1, rightMax: 60, rightUnit: "min")
        let (idleRow, idStep, idVal) =
            makeRow("Idle", value: settings.idlePauseMinutes, min: 1, max: 60, unit: "min", prefix: "pause after")

        shortIntervalStepper = sIStep; shortDurationStepper = sDStep
        shortIntervalValue = sIVal; shortDurationValue = sDVal
        longIntervalStepper = lIStep; longDurationStepper = lDStep
        longIntervalValue = lIVal; longDurationValue = lDVal
        idlePauseStepper = idStep; idlePauseValue = idVal

        suppressCheckbox = NSButton(
            checkboxWithTitle: "Don't interrupt when the microphone is in use",
            target: self, action: #selector(toggleSuppress(_:)))
        suppressCheckbox.state = settings.suppressDuringPresentation ? .on : .off

        loginCheckbox = NSButton(
            checkboxWithTitle: "Launch Stretch at login",
            target: self, action: #selector(toggleLogin(_:)))

        return paneStack(views: [shortRow, longRow, idleRow, suppressCheckbox, loginCheckbox])
    }

    private func buildBedtimePane() -> NSView {
        bedtimeEnabledCheckbox = NSButton(
            checkboxWithTitle: "Dim the screen to a paper look at bedtime",
            target: self, action: #selector(bedtimeChanged))

        let (scheduleRow, bsP, beP) = makeTimePairRow(
            label: "Schedule",
            leftTitle: "Starts", leftMinutes: settings.bedtimeStartMin,
            rightTitle: "Ends", rightMinutes: settings.bedtimeEndMin,
            action: #selector(bedtimeChanged))
        bedtimeStartPicker = bsP
        bedtimeEndPicker = beP

        let intensityLabel = rowLabel("Intensity", width: 100)
        intensityControl = NSSegmentedControl(
            labels: Settings.PaperIntensity.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(bedtimeChanged))
        intensityControl.selectedSegment = settings.paperIntensity.rawValue
        let intensityRow = NSStackView(views: [intensityLabel, intensityControl])
        intensityRow.orientation = .horizontal
        intensityRow.spacing = 10

        bedtimeGammaCheckbox = NSButton(
            checkboxWithTitle: "Warm & dim via display gamma (recommended)",
            target: self, action: #selector(bedtimeChanged))
        bedtimeGrayscaleCheckbox = NSButton(
            checkboxWithTitle: "Also enable system grayscale (Color Filters)",
            target: self, action: #selector(bedtimeChanged))

        let shortcutsLabel = NSTextField(labelWithString: "Shortcuts: ⌘⇧B toggle · ⌘⇧S snooze 15 min")
        shortcutsLabel.font = .systemFont(ofSize: 11)
        shortcutsLabel.textColor = .secondaryLabelColor

        let helpButton = NSButton(title: "?", target: self, action: #selector(showBedtimeHelp(_:)))
        helpButton.bezelStyle = .roundRect
        helpButton.font = .systemFont(ofSize: 11, weight: .semibold)
        helpButton.controlSize = .small

        let shortcutsRow = NSStackView(views: [shortcutsLabel, helpButton])
        shortcutsRow.orientation = .horizontal
        shortcutsRow.spacing = 6

        return paneStack(views: [
            bedtimeEnabledCheckbox, scheduleRow, intensityRow,
            bedtimeGammaCheckbox, bedtimeGrayscaleCheckbox, shortcutsRow,
        ])
    }

    private func buildMedicationsPane() -> NSView {
        let mt = settings.mealTimes
        let ww = settings.wakingWindow

        let (mealsRow, bP, lP, dP) = makeMealTimesRow(
            breakfast: mt.breakfastMin, lunch: mt.lunchMin, dinner: mt.dinnerMin)
        breakfastPicker = bP; lunchPicker = lP; dinnerPicker = dP

        let (awakeRow, wsP, weP) = makeTimePairRow(
            label: "Awake",
            leftTitle: "from", leftMinutes: ww.startMin,
            rightTitle: "until", rightMinutes: ww.endMin,
            action: #selector(mealTimesChanged))
        wakeStartPicker = wsP
        wakeEndPicker = weP

        let (leadRow, leadStep, leadVal) =
            makeRow("Remind dose up to", value: settings.doseLeadMinutes, min: 0, max: 120, unit: "min")
        let (expiryRow, expStep, expVal) =
            makeRow("Skip if untaken after", value: settings.doseCutoffMinutes, min: 5, max: 720, unit: "min")
        doseLeadStepper = leadStep; doseLeadValue = leadVal
        doseCutoffStepper = expStep; doseCutoffValue = expVal

        let editMedsButton = NSButton(title: "Edit medications…", target: self,
                                      action: #selector(editMedsTapped))
        editMedsButton.bezelStyle = .rounded

        return paneStack(views: [mealsRow, awakeRow, leadRow, expiryRow, editMedsButton])
    }

    private func paneStack(views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    // MARK: - Row helpers

    private func rowLabel(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func makeDualFieldRow(
        label: String,
        leftTitle: String, leftValue: Int, leftMin: Int, leftMax: Int, leftUnit: String,
        rightTitle: String, rightValue: Int, rightMin: Int, rightMax: Int, rightUnit: String
    ) -> (NSView, NSStepper, NSStepper, NSTextField, NSTextField) {
        let rowLabel = rowLabel(label, width: 100)

        let leftTitleField = NSTextField(labelWithString: leftTitle)
        let leftStepper = NSStepper()
        leftStepper.minValue = Double(leftMin)
        leftStepper.maxValue = Double(leftMax)
        leftStepper.increment = leftUnit == "sec" ? 5 : 1
        leftStepper.integerValue = leftValue
        leftStepper.target = self
        leftStepper.action = #selector(changed)
        let leftValueField = NSTextField(labelWithString: "\(leftValue) \(leftUnit)")
        leftValueField.translatesAutoresizingMaskIntoConstraints = false
        leftValueField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let rightTitleField = NSTextField(labelWithString: rightTitle)
        let rightStepper = NSStepper()
        rightStepper.minValue = Double(rightMin)
        rightStepper.maxValue = Double(rightMax)
        rightStepper.increment = rightUnit == "sec" ? 5 : 1
        rightStepper.integerValue = rightValue
        rightStepper.target = self
        rightStepper.action = #selector(changed)
        let rightValueField = NSTextField(labelWithString: "\(rightValue) \(rightUnit)")
        rightValueField.translatesAutoresizingMaskIntoConstraints = false
        rightValueField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let row = NSStackView(views: [
            rowLabel, leftTitleField, leftStepper, leftValueField,
            rightTitleField, rightStepper, rightValueField,
        ])
        row.orientation = .horizontal
        row.spacing = 8
        return (row, leftStepper, rightStepper, leftValueField, rightValueField)
    }

    private func makeRow(_ title: String, value: Int, min: Int, max: Int, unit: String,
                         prefix: String? = nil)
        -> (NSView, NSStepper, NSTextField) {
        let label = rowLabel(title, width: 100)

        var views: [NSView] = [label]
        if let prefix {
            views.append(NSTextField(labelWithString: prefix))
        }

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

        views.append(contentsOf: [stepper, valueField])
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        return (row, stepper, valueField)
    }

    private func makeTimePairRow(
        label: String,
        leftTitle: String, leftMinutes: Int,
        rightTitle: String, rightMinutes: Int,
        action: Selector
    ) -> (NSView, NSDatePicker, NSDatePicker) {
        let rowLabel = rowLabel(label, width: 100)

        let leftTitleField = NSTextField(labelWithString: leftTitle)
        let leftPicker = makeTimePicker(minutes: leftMinutes, action: action)

        let rightTitleField = NSTextField(labelWithString: rightTitle)
        let rightPicker = makeTimePicker(minutes: rightMinutes, action: action)

        let row = NSStackView(views: [rowLabel, leftTitleField, leftPicker, rightTitleField, rightPicker])
        row.orientation = .horizontal
        row.spacing = 8
        return (row, leftPicker, rightPicker)
    }

    private func makeMealTimesRow(
        breakfast: Int, lunch: Int, dinner: Int
    ) -> (NSView, NSDatePicker, NSDatePicker, NSDatePicker) {
        let rowLabel = rowLabel("Meals", width: 100)

        let breakfastLabel = NSTextField(labelWithString: "Breakfast")
        let breakfastPicker = makeTimePicker(minutes: breakfast, action: #selector(mealTimesChanged))

        let lunchLabel = NSTextField(labelWithString: "Lunch")
        let lunchPicker = makeTimePicker(minutes: lunch, action: #selector(mealTimesChanged))

        let dinnerLabel = NSTextField(labelWithString: "Dinner")
        let dinnerPicker = makeTimePicker(minutes: dinner, action: #selector(mealTimesChanged))

        let row = NSStackView(views: [
            rowLabel, breakfastLabel, breakfastPicker,
            lunchLabel, lunchPicker, dinnerLabel, dinnerPicker,
        ])
        row.orientation = .horizontal
        row.spacing = 8
        return (row, breakfastPicker, lunchPicker, dinnerPicker)
    }

    private func makeTimePicker(minutes: Int, action: Selector) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Self.date(fromMinutes: minutes)
        picker.target = self
        picker.action = action
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
        settings.idlePauseMinutes = idlePauseStepper.integerValue

        settings.doseLeadMinutes = doseLeadStepper.integerValue
        settings.doseCutoffMinutes = doseCutoffStepper.integerValue

        shortIntervalValue.stringValue = "\(settings.shortIntervalMinutes) min"
        shortDurationValue.stringValue = "\(settings.shortDurationSecondsValue) sec"
        longIntervalValue.stringValue = "\(settings.longIntervalMinutes) min"
        longDurationValue.stringValue = "\(settings.longDurationMinutes) min"
        idlePauseValue.stringValue = "\(settings.idlePauseMinutes) min"
        doseLeadValue.stringValue = "\(settings.doseLeadMinutes) min"
        doseCutoffValue.stringValue = "\(settings.doseCutoffMinutes) min"

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
