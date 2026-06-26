import Foundation

/// One medication or supplement the user wants to be reminded about. This is
/// *configuration* (persisted by MedicationConfigStore), not a log entry.
struct Medication: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case oral, topical   // a pill to swallow vs. a cream/drops to apply

        var label: String { self == .oral ? "Oral" : "Topical" }
    }

    var id: UUID
    var name: String
    var kind: Kind
    var schedule: MedicationSchedule
    var isActive: Bool
    var notes: String          // e.g. "with food" — shown as the dose subtitle
    /// Minutes after a dose's target time before an unresolved dose is counted
    /// "missed". nil → use the global default (Settings.doseExpiryMinutes).
    var expiryMinutes: Int?

    init(id: UUID = UUID(),
         name: String,
         kind: Kind = .oral,
         schedule: MedicationSchedule,
         isActive: Bool = true,
         notes: String = "",
         expiryMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.schedule = schedule
        self.isActive = isActive
        self.notes = notes
        self.expiryMinutes = expiryMinutes
    }
}
