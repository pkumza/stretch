import Foundation

/// Decides whether bedtime paper mode should be on, independently of breaks.
final class BedtimeScheduler {
    private(set) var isActive = false
    var onChange: ((Bool) -> Void)?

    private var settings: Settings { .shared }

    func start() {
        refresh()
    }

    /// Call about once a second (wired from AppDelegate's break tick).
    func tick() {
        refresh()
    }

    func refresh() {
        let desired = shouldBeActive(at: Date())
        guard desired != isActive else { return }
        isActive = desired
        onChange?(desired)
    }

    // MARK: - User actions

    /// Force paper mode on until the end of the current bedtime window
    /// (or for one hour if outside the scheduled window).
    func activateNow() {
        let now = Date()
        settings.bedtimeForceUntil = endOfCurrentOrNextWindow(from: now)
        settings.bedtimeSnoozeUntil = .distantPast
        settings.bedtimeDismissedUntil = .distantPast
        refresh()
    }

    /// Turn off until the scheduled window ends (tonight / this morning).
    func dismissUntilMorning() {
        let now = Date()
        settings.bedtimeForceUntil = .distantPast
        settings.bedtimeDismissedUntil = endOfCurrentWindow(from: now) ?? now.addingTimeInterval(8 * 3600)
        refresh()
    }

    func snooze(minutes: Int) {
        settings.bedtimeForceUntil = .distantPast
        settings.bedtimeSnoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        refresh()
    }

    // MARK: - Logic

    private func shouldBeActive(at now: Date) -> Bool {
        if settings.bedtimeForceUntil > now { return true }
        guard settings.bedtimeEnabled else { return false }
        if settings.bedtimeSnoozeUntil > now { return false }
        if settings.bedtimeDismissedUntil > now { return false }
        return isInBedtimeWindow(at: now)
    }

    func isInBedtimeWindow(at now: Date) -> Bool {
        let m = Self.minutesSinceMidnight(now)
        let start = settings.bedtimeStartMin
        let end = settings.bedtimeEndMin
        if start == end { return settings.bedtimeEnabled }
        if start < end {
            return m >= start && m < end
        }
        // Crosses midnight, e.g. 21:40 → 07:00
        return m >= start || m < end
    }

    /// End of the window that contains `now`, or nil if outside.
    private func endOfCurrentWindow(from now: Date) -> Date? {
        guard isInBedtimeWindow(at: now) else { return nil }
        return Self.dateOfNextOccurrence(ofMinute: settings.bedtimeEndMin, after: now)
    }

    private func endOfCurrentOrNextWindow(from now: Date) -> Date {
        if let end = endOfCurrentWindow(from: now) { return end }
        let oneHour = now.addingTimeInterval(3600)
        let nextEnd = Self.dateOfNextOccurrence(ofMinute: settings.bedtimeEndMin, after: now)
        return min(oneHour, nextEnd)
    }

    static func minutesSinceMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Next clock time matching `minuteOfDay` strictly after `after`.
    static func dateOfNextOccurrence(ofMinute minuteOfDay: Int, after: Date) -> Date {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: after)
        let candidate = cal.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? after
        if candidate > after { return candidate }
        return cal.date(byAdding: .day, value: 1, to: candidate) ?? after.addingTimeInterval(86400)
    }

    static func formatMinutes(_ m: Int) -> String {
        String(format: "%d:%02d", m / 60, m % 60)
    }
}
