import AppKit

/// A window showing break stats over several time windows.
final class HistoryController: NSObject {
    private var window: NSWindow?
    private var grid: NSGridView?
    private var medGrid: NSGridView?
    private var medTitle: NSTextField?

    func show() {
        if window == nil { window = buildWindow() }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build

    private func buildWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "Break History"
        win.isReleasedWhenClosed = false

        let grid = Self.makeGrid(["Period", "Rested", "Rest time", "Skipped", "Snoozed", "Debts", "Peak debt"])
        self.grid = grid
        let title = Self.sectionTitle("Your breaks")

        let medGrid = Self.makeGrid(["Period", "Taken", "Skipped", "Missed", "Adherence"])
        self.medGrid = medGrid
        let medTitle = Self.sectionTitle("Your medications")
        self.medTitle = medTitle

        let stack = NSStackView(views: [title, grid, medTitle, medGrid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(28, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        win.contentView = content
        return win
    }

    private static func makeGrid(_ header: [String]) -> NSGridView {
        let grid = NSGridView(views: [header.map { Self.head($0) }])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 24
        grid.column(at: 0).xPlacement = .leading
        for c in 1..<header.count { grid.column(at: c).xPlacement = .trailing }
        return grid
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let title = NSTextField(labelWithString: text)
        title.font = .systemFont(ofSize: 18, weight: .bold)
        return title
    }

    // MARK: - Data

    /// (Today / 7d / 30d / All time) start dates.
    private static func periods() -> [(String, Date)] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        return [
            ("Today",        startOfToday),
            ("Last 7 days",  cal.date(byAdding: .day, value: -7, to: startOfToday)!),
            ("Last 30 days", cal.date(byAdding: .day, value: -30, to: startOfToday)!),
            ("All time",     Date(timeIntervalSince1970: 0)),
        ]
    }

    /// NSGridView.removeRow(at:) detaches a row but leaves its cell views in the
    /// hierarchy, so remove them by hand — otherwise stale numbers pile up.
    private static func clearRows(_ grid: NSGridView) {
        while grid.numberOfRows > 1 {
            let row = grid.row(at: grid.numberOfRows - 1)
            for i in 0..<row.numberOfCells { row.cell(at: i).contentView?.removeFromSuperview() }
            grid.removeRow(at: grid.numberOfRows - 1)
        }
    }

    private func refresh() {
        if let grid {
            Self.clearRows(grid)
            for (name, since) in Self.periods() {
                let s = HistoryStore.shared.summary(since: since)
                grid.addRow(with: [
                    Self.cell(name, bold: true),
                    Self.cell("\(s.restCount)"),
                    Self.cell(Self.duration(s.restSeconds)),
                    Self.cell("\(s.skipCount)"),
                    Self.cell("\(s.snoozeCount)"),
                    Self.cell("\(s.debtClearCount)"),
                    Self.cell(s.peakDebtSeconds > 0 ? Self.duration(s.peakDebtSeconds) : "—"),
                ])
            }
        }

        // Medication section — hidden entirely when the feature is dormant.
        let dormant = MedicationConfigStore.shared.medications.isEmpty
            && MedicationLogStore.shared.events.isEmpty
        medTitle?.isHidden = dormant
        medGrid?.isHidden = dormant
        if let medGrid, !dormant {
            Self.clearRows(medGrid)
            for (name, since) in Self.periods() {
                let s = MedicationLogStore.shared.summary(since: since)
                medGrid.addRow(with: [
                    Self.cell(name, bold: true),
                    Self.cell("\(s.taken)"),
                    Self.cell("\(s.skipped)"),
                    Self.cell("\(s.missed)"),
                    Self.cell("\(s.adherencePct)%"),
                ])
            }
        }
    }

    // MARK: - Cell helpers

    private static func head(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private static func cell(_ text: String, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
        return l
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}
