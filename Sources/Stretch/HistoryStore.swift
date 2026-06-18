import Foundation

/// One thing that happened to a break.
struct BreakEvent: Codable {
    enum Action: String, Codable {
        case completed   // you took the break
        case skipped     // permanent skip
        case snoozed     // temporary skip — re-alerts shortly
    }
    let date: Date
    let isLong: Bool
    let action: Action
    let durationSec: Int   // for completed breaks; 0 otherwise
}

/// Aggregated counts over some time window.
struct HistorySummary {
    var restCount = 0
    var restSeconds = 0
    var skipCount = 0
    var snoozeCount = 0
}

/// Append-only event log persisted as JSON in Application Support.
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var events: [BreakEvent] = []
    private let fileURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stretch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    func record(isLong: Bool, action: BreakEvent.Action, durationSec: Int = 0) {
        events.append(BreakEvent(date: Date(), isLong: isLong,
                                 action: action, durationSec: durationSec))
        save()
    }

    /// Summarize all events on or after `since`.
    func summary(since: Date) -> HistorySummary {
        var s = HistorySummary()
        for e in events where e.date >= since {
            switch e.action {
            case .completed:
                s.restCount += 1
                s.restSeconds += e.durationSec
            case .skipped:
                s.skipCount += 1
            case .snoozed:
                s.snoozeCount += 1
            }
        }
        return s
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        events = (try? decoder.decode([BreakEvent].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
