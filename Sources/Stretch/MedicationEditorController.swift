import AppKit

/// A window to add/edit/remove medications. Mirrors how HistoryController builds
/// and shows its window. Edits go through MedicationConfigStore and notify
/// MedicationManager so today's doses rebuild immediately.
final class MedicationEditorController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow?
    private var table: NSTableView!
    private var meds: [Medication] = []

    func show() {
        if window == nil { window = buildWindow() }
        reload()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reload() {
        meds = MedicationConfigStore.shared.medications
        table?.reloadData()
    }

    private func commit() {
        MedicationManager.shared.reloadConfig()
        MedicationManager.shared.rebuildToday(for: Date())
        reload()
    }

    // MARK: - Build

    private func buildWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Medications"
        win.isReleasedWhenClosed = false

        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .default
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(editTapped)
        for (id, title, width) in [("name", "Name", 150.0), ("kind", "Kind", 70.0),
                                   ("schedule", "Schedule", 200.0), ("active", "Active", 60.0)] {
            let col = NSTableColumn(identifier: .init(id))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }
        self.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let add = button("Add", #selector(addTapped))
        let edit = button("Edit", #selector(editTapped))
        let remove = button("Remove", #selector(removeTapped))
        let buttons = NSStackView(views: [add, edit, remove])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        win.contentView = content
        return win
    }

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        return b
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { meds.count }

    func tableView(_ tableView: NSTableView,
                   objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let m = meds[row]
        switch column?.identifier.rawValue {
        case "name":     return m.name
        case "kind":     return m.kind.label
        case "schedule": return m.schedule.description
        case "active":   return m.isActive ? "✓" : "—"
        default:         return nil
        }
    }

    // MARK: - Actions

    @objc private func addTapped() { presentForm(editing: nil) }

    @objc private func editTapped() {
        let row = table.selectedRow
        guard row >= 0, row < meds.count else { return }
        presentForm(editing: meds[row])
    }

    @objc private func removeTapped() {
        let row = table.selectedRow
        guard row >= 0, row < meds.count else { return }
        MedicationConfigStore.shared.remove(id: meds[row].id)
        commit()
    }

    // MARK: - Add/Edit form (sheet)

    private var form: MedicationForm?

    private func presentForm(editing existing: Medication?) {
        guard let window else { return }
        let form = MedicationForm(existing: existing) { [weak self] result in
            guard let self, let panel = self.form?.panel else { return }
            window.endSheet(panel)
            self.form = nil
            if let med = result {
                if existing == nil { MedicationConfigStore.shared.add(med) }
                else { MedicationConfigStore.shared.update(med) }
                self.commit()
            }
        }
        self.form = form
        window.beginSheet(form.panel, completionHandler: nil)
    }
}
