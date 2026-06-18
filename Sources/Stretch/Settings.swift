import Foundation

/// User-tunable settings, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard

    private enum Keys {
        static let shortInterval = "shortIntervalMinutes"
        static let shortDuration = "shortDurationSeconds"
        static let longInterval  = "longIntervalMinutes"
        static let longDuration  = "longDurationMinutes"
    }

    private init() {
        d.register(defaults: [
            Keys.shortInterval: 20,   // a short break every 20 minutes
            Keys.shortDuration: 20,   // lasting 20 seconds
            Keys.longInterval:  60,   // a long break every 60 minutes
            Keys.longDuration:   5,   // lasting 5 minutes
        ])
    }

    // Stored values (in their natural units, as shown in Preferences).
    var shortIntervalMinutes: Int {
        get { d.integer(forKey: Keys.shortInterval) }
        set { d.set(max(1, newValue), forKey: Keys.shortInterval) }
    }
    var shortDurationSecondsValue: Int {
        get { d.integer(forKey: Keys.shortDuration) }
        set { d.set(max(5, newValue), forKey: Keys.shortDuration) }
    }
    var longIntervalMinutes: Int {
        get { d.integer(forKey: Keys.longInterval) }
        set { d.set(max(1, newValue), forKey: Keys.longInterval) }
    }
    var longDurationMinutes: Int {
        get { d.integer(forKey: Keys.longDuration) }
        set { d.set(max(1, newValue), forKey: Keys.longDuration) }
    }

    // Derived values used by the scheduler (in seconds).
    var shortIntervalSeconds: TimeInterval { TimeInterval(shortIntervalMinutes * 60) }
    var shortDurationSeconds: TimeInterval { TimeInterval(shortDurationSecondsValue) }
    var longIntervalSeconds:  TimeInterval { TimeInterval(longIntervalMinutes * 60) }
    var longDurationSeconds:  TimeInterval { TimeInterval(longDurationMinutes * 60) }

    /// How many breaks occur per cycle; the last one of each cycle is a long break.
    /// e.g. long=60, short=20  ->  3 breaks per cycle (short, short, long).
    var breaksPerLong: Int {
        max(1, Int((longIntervalSeconds / shortIntervalSeconds).rounded()))
    }

    /// When the user snoozes a break ("remind me later"), how long until it returns.
    var snoozeSeconds: TimeInterval { 2 * 60 }
}
