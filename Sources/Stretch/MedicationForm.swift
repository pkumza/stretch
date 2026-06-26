import AppKit

/// The add/edit medication form, shown as a sheet by MedicationEditorController.
/// Calls `completion(nil)` on cancel, `completion(medication)` on save.
final class MedicationForm: NSObject {
    let panel: NSWindow
    private let completion: (Medication?) -> Void
    private let existing: Medication?

    private let nameField = NSTextField()
    private let kindPopup = NSPopUpButton()
    private let typePopup = NSPopUpButton()        // Meal-relative / N× per day
    private let mealPopup = NSPopUpButton()
    private let relationPopup = NSPopUpButton()
    private let offsetStepper = NSStepper()
    private let offsetValue = NSTextField(labelWithString: "30 min")
    private let countStepper = NSStepper()
    private let countValue = NSTextField(labelWithString: "2×")
    private let notesField = NSTextField()
    private let activeCheckbox = NSButton(checkboxWithTitle: "Active", target: nil, action: nil)

    private var mealRow: NSView!
    private var countRow: NSView!

    init(existing: Medication?, completion: @escaping (Medication?) -> Void) {
        self.existing = existing
        self.completion = completion
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                         styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = existing == nil ? "Add Medication" : "Edit Medication"
        buildForm()
        populate()
        syncScheduleRows()
    }

    // MARK: - Build

    private func buildForm() {
        kindPopup.addItems(withTitles: Medication.Kind.allCases.map { $0.label })
        typePopup.addItems(withTitles: ["Meal-relative", "N times per day"])
        typePopup.target = self; typePopup.action = #selector(typeChanged)
        mealPopup.addItems(withTitles: MedicationSchedule.Meal.allCases.map { $0.label })
        relationPopup.addItems(withTitles: MedicationSchedule.Relation.allCases.map { $0.label })

        offsetStepper.minValue = 0; offsetStepper.maxValue = 240; offsetStepper.increment = 5
        offsetStepper.integerValue = 30
        offsetStepper.target = self; offsetStepper.action = #selector(offsetChanged)
        offsetValue.widthAnchor.constraint(equalToConstant: 64).isActive = true

        countStepper.minValue = 1; countStepper.maxValue = 12; countStepper.increment = 1
        countStepper.integerValue = 2
        countStepper.target = self; countStepper.action = #selector(countChanged)
        countValue.widthAnchor.constraint(equalToConstant: 40).isActive = true

        nameField.placeholderString = "e.g. CoQ10"
        notesField.placeholderString = "e.g. with food (optional)"

        mealRow = row("When", [mealPopup, relationPopup, offsetStepper, offsetValue])
        countRow = row("Times per day", [countStepper, countValue])

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"   // Esc
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"           // Return
        let actions = NSStackView(views: [cancel, save])
        actions.orientation = .horizontal; actions.spacing = 10

        let stack = NSStackView(views: [
            row("Name", [nameField]),
            row("Kind", [kindPopup]),
            row("Schedule", [typePopup]),
            mealRow,
            countRow,
            row("Notes", [notesField]),
            row("", [activeCheckbox]),
            actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            actions.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        panel.contentView = content
    }

    private func row(_ title: String, _ controls: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        if title == "Name" || title == "Notes" {
            (controls.first as? NSTextField)?.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        let r = NSStackView(views: [label] + controls)
        r.orientation = .horizontal
        r.spacing = 8
        return r
    }

    // MARK: - Populate from existing

    private func populate() {
        guard let m = existing else {
            activeCheckbox.state = .on
            return
        }
        nameField.stringValue = m.name
        notesField.stringValue = m.notes
        kindPopup.selectItem(at: Medication.Kind.allCases.firstIndex(of: m.kind) ?? 0)
        activeCheckbox.state = m.isActive ? .on : .off
        switch m.schedule {
        case let .mealRelative(meal, relation, offset):
            typePopup.selectItem(at: 0)
            mealPopup.selectItem(at: MedicationSchedule.Meal.allCases.firstIndex(of: meal) ?? 0)
            relationPopup.selectItem(at: MedicationSchedule.Relation.allCases.firstIndex(of: relation) ?? 0)
            offsetStepper.integerValue = offset
        case let .timesPerDay(count):
            typePopup.selectItem(at: 1)
            countStepper.integerValue = count
        }
        offsetChanged(); countChanged()
    }

    // MARK: - Actions

    @objc private func typeChanged() { syncScheduleRows() }
    @objc private func offsetChanged() { offsetValue.stringValue = "\(offsetStepper.integerValue) min" }
    @objc private func countChanged() { countValue.stringValue = "\(countStepper.integerValue)×" }

    private func syncScheduleRows() {
        let mealRelative = typePopup.indexOfSelectedItem == 0
        mealRow.isHidden = !mealRelative
        countRow.isHidden = mealRelative
    }

    @objc private func cancelTapped() { completion(nil) }

    @objc private func saveTapped() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { NSSound.beep(); return }

        let schedule: MedicationSchedule
        if typePopup.indexOfSelectedItem == 0 {
            let meal = MedicationSchedule.Meal.allCases[mealPopup.indexOfSelectedItem]
            let relation = MedicationSchedule.Relation.allCases[relationPopup.indexOfSelectedItem]
            schedule = .mealRelative(meal: meal, relation: relation,
                                     offsetMinutes: offsetStepper.integerValue)
        } else {
            schedule = .timesPerDay(count: countStepper.integerValue)
        }

        let med = Medication(
            id: existing?.id ?? UUID(),
            name: name,
            kind: Medication.Kind.allCases[kindPopup.indexOfSelectedItem],
            schedule: schedule,
            isActive: activeCheckbox.state == .on,
            notes: notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            expiryMinutes: existing?.expiryMinutes)
        completion(med)
    }
}
