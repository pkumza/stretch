import Foundation

/// One recorded transition for a scheduled dose. Append-only; the latest event
/// per `doseKey` (by `resolvedAt`) is authoritative.
struct MedicationEvent: Codable {
    enum Action: String, Codable {
        case taken
        case notYet = "not_yet"   // non-terminal — a later event supersedes it
        case skipped
        case missed
    }
    var doseKey: String           // "<medID>|<yyyy-MM-dd local>|<targetEpoch>"
    var medID: UUID
    var medName: String
    var kind: String              // "oral" | "topical"
    var scheduledFor: Date        // the dose's target clock time
    var day: String               // "yyyy-MM-dd" (user-local)
    var action: Action
    var resolvedAt: Date
}

/// Aggregated medication adherence over a window.
struct MedicationSummary {
    var taken = 0
    var skipped = 0
    var missed = 0
    var openNotYet = 0   // doses whose latest state is still "not yet"
    /// Distinct doses that reached a terminal state (taken+skipped+missed).
    var resolved: Int { taken + skipped + missed }
    var adherencePct: Int {
        let denom = resolved
        return denom == 0 ? 0 : Int((Double(taken) / Double(denom) * 100).rounded())
    }
}

/// Append-only medication log persisted as JSON in Application Support. This
/// file (`medication.json`) is the documented one-way export the external
/// "health" project reads. Stretch only ever writes it.
final class MedicationLogStore {
    static let shared = MedicationLogStore()

    static let schemaVersion = 1

    private(set) var events: [MedicationEvent] = []
    private let fileURL: URL

    /// On-disk envelope: { schemaVersion, generatedBy, events: [...] }.
    private struct Envelope: Codable {
        var schemaVersion: Int
        var generatedBy: String
        var events: [MedicationEvent]
    }

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stretch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("medication.json")
        load()
    }

    func record(_ e: MedicationEvent) {
        events.append(e)
        save()
    }

    /// Latest-event-per-dose within [since, ∞), then tally by terminal state.
    func summary(since: Date) -> MedicationSummary {
        var latest: [String: MedicationEvent] = [:]
        for e in events where e.scheduledFor >= since {
            if let cur = latest[e.doseKey], cur.resolvedAt >= e.resolvedAt { continue }
            latest[e.doseKey] = e
        }
        var s = MedicationSummary()
        for e in latest.values {
            switch e.action {
            case .taken:   s.taken += 1
            case .skipped: s.skipped += 1
            case .missed:  s.missed += 1
            case .notYet:  s.openNotYet += 1
            }
        }
        return s
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        events = (try? decoder.decode(Envelope.self, from: data))?.events ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelope = Envelope(schemaVersion: Self.schemaVersion,
                                generatedBy: "Stretch", events: events)
        if let data = try? encoder.encode(envelope) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
