import Foundation

/// One expected dose on a given day. Identity is `doseKey`, stable across breaks
/// and config reloads, unique per (medication, day, target slot).
struct DoseInstance: Equatable {
    enum State: String { case pending, due, taken, skipped, missed }

    let medID: UUID
    let medName: String
    let kind: Medication.Kind
    let notes: String
    let target: Date
    let leadMinutes: Int        // how early it may surface (0 for meal-relative)
    let cutoffMinutes: Int      // how long unresolved before it auto-resolves
    var state: State
    var seenDue = false         // did the app ever surface it (vs. app was off)?

    var dayKey: String { DoseInstance.dayFormatter.string(from: target) }
    var doseKey: String { "\(medID.uuidString)|\(dayKey)|\(Int(target.timeIntervalSince1970))" }

    var dueStart: Date { target.addingTimeInterval(TimeInterval(-leadMinutes * 60)) }
    var cutoff: Date { target.addingTimeInterval(TimeInterval(cutoffMinutes * 60)) }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Computes which medication doses are "due" right now and applies the user's
/// taps. Passive: it owns no timer — `tick()` is driven from the break
/// scheduler, and `dueDoses()` is pulled at break start. Logs to
/// MedicationLogStore (the `medication.json` export). Zero overhead when no
/// medications are configured.
final class MedicationManager {
    static let shared = MedicationManager()

    enum Action { case took, notYet, skip }

    private(set) var config: [Medication] = []
    private var today: [DoseInstance] = []
    private var dayAnchor = Calendar.current.startOfDay(for: Date())

    private var settings: Settings { .shared }
    private var log: MedicationLogStore { .shared }

    func start() {
        reloadConfig()
        rebuildToday(for: Date())
    }

    /// Reload the medication list after the editor changes it.
    func reloadConfig() {
        config = MedicationConfigStore.shared.medications
    }

    var hasActiveMedications: Bool { config.contains { $0.isActive } }

    // MARK: - Building today's doses

    /// (Re)derive today's doses. Preserves resolved states by `doseKey` so a
    /// mid-day config/meal-time edit doesn't resurrect handled doses; on a day
    /// change, flushes any still-unresolved doses to "missed" first.
    func rebuildToday(for now: Date) {
        let cal = Calendar.current
        let newAnchor = cal.startOfDay(for: now)
        let dayChanged = newAnchor != dayAnchor

        var resolved: [String: DoseInstance.State] = [:]
        var seen: Set<String> = []
        for d in today {
            if d.state == .taken || d.state == .skipped || d.state == .missed {
                resolved[d.doseKey] = d.state
            }
            if d.seenDue { seen.insert(d.doseKey) }
        }

        if dayChanged {
            for i in today.indices where today[i].state == .pending || today[i].state == .due {
                autoResolve(&today[i], at: now)
            }
            resolved.removeAll(); seen.removeAll()   // new day — no carryover
        }

        dayAnchor = newAnchor
        today = buildInstances(for: newAnchor)
        for i in today.indices {
            if let s = resolved[today[i].doseKey] { today[i].state = s }
            if seen.contains(today[i].doseKey) { today[i].seenDue = true }
        }
    }

    private func buildInstances(for anchor: Date) -> [DoseInstance] {
        let cal = Calendar.current
        let meals = settings.mealTimes
        let wake = settings.wakingWindow
        let globalCutoff = settings.doseCutoffMinutes
        let lead = settings.doseLeadMinutes

        var out: [DoseInstance] = []
        for med in config where med.isActive {
            let targets = med.schedule.targetTimes(on: anchor, mealTimes: meals,
                                                   wakingWindow: wake, calendar: cal)
            for target in targets {
                out.append(DoseInstance(
                    medID: med.id, medName: med.name, kind: med.kind, notes: med.notes,
                    target: target,
                    leadMinutes: med.schedule.usesLead ? lead : 0,
                    cutoffMinutes: med.expiryMinutes ?? globalCutoff,
                    state: .pending))
            }
        }
        return out
    }

    // MARK: - Tick (drive state by the clock)

    /// Promote pending→due, and auto-resolve doses left dangling past their
    /// cutoff. Cheap no-op when no medications are configured.
    func tick(now: Date = Date()) {
        if Calendar.current.startOfDay(for: now) != dayAnchor { rebuildToday(for: now); return }
        guard !config.isEmpty else { return }

        for i in today.indices {
            guard today[i].state == .pending || today[i].state == .due else { continue }
            if now > today[i].cutoff {
                autoResolve(&today[i], at: now)
            } else if now >= today[i].dueStart {
                today[i].state = .due
                today[i].seenDue = true
            }
        }
    }

    /// A dose left unresolved past its cutoff: skipped if the app actually
    /// surfaced it (you were around and kept deferring), missed if it never
    /// became due while running (the app was off through its whole window).
    private func autoResolve(_ dose: inout DoseInstance, at now: Date) {
        let action: MedicationEvent.Action = dose.seenDue ? .skipped : .missed
        dose.state = dose.seenDue ? .skipped : .missed
        record(dose, action, at: now)
    }

    // MARK: - Querying & resolving

    /// Doses to surface on the break overlay right now. Promotes first so the
    /// result is current regardless of tick ordering.
    func dueDoses(at now: Date = Date()) -> [DoseInstance] {
        tick(now: now)
        return today.filter { $0.state == .due }
    }

    /// Apply the break overlay's outcome and log terminal states.
    func resolve(_ dose: DoseInstance, _ action: Action, at now: Date = Date()) {
        guard let i = today.firstIndex(where: { $0.doseKey == dose.doseKey }) else { return }
        switch action {
        case .took:
            today[i].state = .taken
            record(today[i], .taken, at: now)
        case .skip:
            today[i].state = .skipped
            record(today[i], .skipped, at: now)
        case .notYet:
            // Leave it due so it re-surfaces next break; not a terminal outcome,
            // so nothing is logged (avoids a breadcrumb on every break).
            today[i].state = .due
        }
    }

    // MARK: - Logging

    private func record(_ dose: DoseInstance, _ action: MedicationEvent.Action, at now: Date) {
        log.record(MedicationEvent(
            doseKey: dose.doseKey, medID: dose.medID, medName: dose.medName,
            kind: dose.kind.rawValue, scheduledFor: dose.target, day: dose.dayKey,
            action: action, resolvedAt: now))
    }
}
