import AppKit

/// A window showing break stats over several time windows.
final class HistoryController: NSObject {
    private var window: NSWindow?
    private var grid: NSGridView?

    func show() {
        if window == nil { window = buildWindow() }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build

    private func buildWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "Break History"
        win.isReleasedWhenClosed = false

        let header = ["Period", "Rested", "Rest time", "Skipped", "Snoozed"]
        let rows: [[NSView]] = [header.map { Self.head($0) }]
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 24
        grid.column(at: 0).xPlacement = .leading
        for c in 1..<header.count { grid.column(at: c).xPlacement = .trailing }
        self.grid = grid

        let title = NSTextField(labelWithString: "Your breaks")
        title.font = .systemFont(ofSize: 18, weight: .bold)

        let stack = NSStackView(views: [title, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
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

    // MARK: - Data

    private func refresh() {
        guard let grid else { return }
        // Drop every row except the header.
        while grid.numberOfRows > 1 { grid.removeRow(at: grid.numberOfRows - 1) }

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let periods: [(String, Date)] = [
            ("Today",        startOfToday),
            ("Last 7 days",  cal.date(byAdding: .day, value: -7, to: startOfToday)!),
            ("Last 30 days", cal.date(byAdding: .day, value: -30, to: startOfToday)!),
            ("All time",     Date(timeIntervalSince1970: 0)),
        ]

        let store = HistoryStore.shared
        for (name, since) in periods {
            let s = store.summary(since: since)
            grid.addRow(with: [
                Self.cell(name, bold: true),
                Self.cell("\(s.restCount)"),
                Self.cell(Self.duration(s.restSeconds)),
                Self.cell("\(s.skipCount)"),
                Self.cell("\(s.snoozeCount)"),
            ])
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
