import Foundation

/// A clock-anchored schedule — the one genuinely new concept in an otherwise
/// interval-based app. Resolved to concrete target `Date`s per calendar day at
/// runtime. All math here is pure (inject `Calendar`/`day`) so it's easy to test.
enum MedicationSchedule: Codable, Equatable {
    /// "30 min before lunch", "with breakfast", "2h after dinner".
    case mealRelative(meal: Meal, relation: Relation, offsetMinutes: Int)
    /// "4 times a day" — spread evenly across the waking window.
    case timesPerDay(count: Int)

    enum Meal: String, Codable, CaseIterable {
        case breakfast, lunch, dinner
        var label: String { rawValue.capitalized }
    }
    enum Relation: String, Codable, CaseIterable {
        case before, after, with
        var label: String { rawValue }
    }

    /// Concrete target times for `day` (a start-of-day anchor).
    func targetTimes(on day: Date,
                     mealTimes: MealTimes,
                     wakingWindow: WakingWindow,
                     calendar: Calendar = .current) -> [Date] {
        switch self {
        case let .mealRelative(meal, relation, offset):
            let base = mealTimes.date(for: meal, on: day, calendar: calendar)
            let delta = relation == .before ? -offset : (relation == .after ? offset : 0)
            return [base.addingTimeInterval(TimeInterval(delta * 60))]
        case let .timesPerDay(count):
            return wakingWindow.spread(count: count, on: day, calendar: calendar)
        }
    }

    /// Whether a dose should surface a bit *before* its target (only for the
    /// N×/day kind; meal-relative targets are already the intended moment).
    var usesLead: Bool {
        if case .timesPerDay = self { return true }
        return false
    }

    /// Human-readable summary for the editor table and the overlay subtitle.
    var description: String {
        switch self {
        case let .mealRelative(meal, relation, offset):
            switch relation {
            case .with:   return "with \(meal.rawValue)"
            case .before: return "\(offset) min before \(meal.rawValue)"
            case .after:  return "\(offset) min after \(meal.rawValue)"
            }
        case let .timesPerDay(count):
            return "\(count)× per day"
        }
    }
}

/// User-configurable meal clock times, stored as minutes-since-midnight so they
/// are time-zone agnostic and trivially Codable.
struct MealTimes: Codable, Equatable {
    var breakfastMin: Int
    var lunchMin: Int
    var dinnerMin: Int

    func date(for meal: MedicationSchedule.Meal, on day: Date, calendar: Calendar) -> Date {
        let m: Int
        switch meal {
        case .breakfast: m = breakfastMin
        case .lunch:     m = lunchMin
        case .dinner:    m = dinnerMin
        }
        return calendar.date(byAdding: .minute, value: m, to: day) ?? day
    }

    static let `default` = MealTimes(breakfastMin: 8 * 60, lunchMin: 12 * 60 + 30, dinnerMin: 19 * 60)
}

/// The waking window used to spread N×/day doses (default 08:00–22:00).
struct WakingWindow: Codable, Equatable {
    var startMin: Int
    var endMin: Int

    /// Evenly spread `count` doses across [start, end]. count==1 → midpoint;
    /// count≥2 → inclusive of both endpoints.
    func spread(count: Int, on day: Date, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        func at(_ minutes: Int) -> Date {
            calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
        }
        if count == 1 { return [at((startMin + endMin) / 2)] }
        let step = Double(endMin - startMin) / Double(count - 1)
        return (0..<count).map { at(startMin + Int((Double($0) * step).rounded())) }
    }

    static let `default` = WakingWindow(startMin: 8 * 60, endMin: 22 * 60)
}
