import Foundation

/// Persists the user's list of medications (config, not log) as JSON in
/// Application Support, mirroring HistoryStore's storage approach.
final class MedicationConfigStore {
    static let shared = MedicationConfigStore()

    private(set) var medications: [Medication] = []
    private let fileURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stretch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("medications-config.json")
        load()
    }

    func add(_ m: Medication) {
        medications.append(m)
        save()
    }

    func update(_ m: Medication) {
        if let i = medications.firstIndex(where: { $0.id == m.id }) {
            medications[i] = m
            save()
        }
    }

    func remove(id: UUID) {
        medications.removeAll { $0.id == id }
        save()
    }

    var hasActive: Bool { medications.contains { $0.isActive } }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        medications = (try? decoder.decode([Medication].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(medications) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
