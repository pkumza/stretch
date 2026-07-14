import Foundation
import CoreGraphics

/// User-tunable settings, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard

    private enum Keys {
        static let shortInterval = "shortIntervalMinutes"
        static let shortDuration = "shortDurationSeconds"
        static let longInterval  = "longIntervalMinutes"
        static let longDuration  = "longDurationMinutes"
        static let suppressDuringPresentation = "suppressDuringPresentation"
        static let idlePause = "idlePauseMinutes"
        // Medication reminders — meal clock times + waking window (minutes since
        // midnight) and the dose lead/expiry windows.
        static let breakfastMin = "breakfastMin"
        static let lunchMin     = "lunchMin"
        static let dinnerMin    = "dinnerMin"
        static let wakeStartMin = "wakeStartMin"
        static let wakeEndMin   = "wakeEndMin"
        static let doseLead     = "doseLeadMinutes"
        static let doseCutoff   = "doseCutoffMinutes"
        // Bedtime paper mode — scheduled soft visual cue.
        static let bedtimeEnabled  = "bedtimeEnabled"
        static let bedtimeStartMin = "bedtimeStartMin"
        static let bedtimeEndMin   = "bedtimeEndMin"
        static let paperIntensity  = "paperIntensity"
        static let bedtimeUseGamma = "bedtimeUseGamma"
        static let bedtimeSnoozeUntil    = "bedtimeSnoozeUntil"
        static let bedtimeDismissedUntil = "bedtimeDismissedUntil"
        static let bedtimeForceUntil     = "bedtimeForceUntil"
    }

    /// Strength of the bedtime paper wash (and optional gamma).
    enum PaperIntensity: Int, CaseIterable {
        case light = 0, medium = 1, strong = 2

        var title: String {
            switch self {
            case .light:  return "Light"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }

        /// Near-zero luminance: Space swipes briefly drop the panel, so any real
        /// dimming here shows up as a bright→dark step. Warmth/dim live in gamma.
        var washAlpha: CGFloat {
            switch self {
            case .light:  return 0.025
            case .medium: return 0.04
            case .strong: return 0.055
            }
        }
        var dimAlpha: CGFloat { 0 }
        var grainAlpha: CGFloat {
            switch self {
            case .light:  return 0.02
            case .medium: return 0.035
            case .strong: return 0.05
            }
        }
        var gammaWarmth: CGFloat {
            switch self {
            case .light:  return 0.50
            case .medium: return 0.78
            case .strong: return 1.0
            }
        }
        /// Sole brightness control — must match the look with or without the panel.
        var gammaDim: CGFloat {
            switch self {
            case .light:  return 0.66
            case .medium: return 0.50
            case .strong: return 0.36
            }
        }
    }

    private init() {
        d.register(defaults: [
            Keys.shortInterval: 20,   // a short break every 20 minutes
            Keys.shortDuration: 20,   // lasting 20 seconds
            Keys.longInterval:  60,   // a long break every 60 minutes
            Keys.longDuration:   5,   // lasting 5 minutes
            Keys.suppressDuringPresentation: true,  // defer breaks only when the microphone is active
            Keys.idlePause: 5,        // treat as "away" after 5 idle minutes
            Keys.breakfastMin: 8 * 60,        // 08:00
            Keys.lunchMin:     12 * 60 + 30,  // 12:30
            Keys.dinnerMin:    19 * 60,       // 19:00
            Keys.wakeStartMin: 8 * 60,        // 08:00
            Keys.wakeEndMin:   22 * 60,       // 22:00
            Keys.doseLead:   30,      // an N×/day dose may surface 30 min early
            Keys.doseCutoff: 180,     // auto-resolve a dangling dose after 3h
            Keys.bedtimeEnabled: false,
            Keys.bedtimeStartMin: 21 * 60 + 40, // 21:40
            Keys.bedtimeEndMin:   7 * 60,       // 07:00
            Keys.paperIntensity: PaperIntensity.medium.rawValue,
            Keys.bedtimeUseGamma: true,
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
    var suppressDuringPresentation: Bool {
        get { d.bool(forKey: Keys.suppressDuringPresentation) }
        set { d.set(newValue, forKey: Keys.suppressDuringPresentation) }
    }
    var idlePauseMinutes: Int {
        get { d.integer(forKey: Keys.idlePause) }
        set { d.set(max(1, newValue), forKey: Keys.idlePause) }
    }

    // MARK: - Medication scheduling

    var mealTimes: MealTimes {
        get { MealTimes(breakfastMin: d.integer(forKey: Keys.breakfastMin),
                        lunchMin:     d.integer(forKey: Keys.lunchMin),
                        dinnerMin:    d.integer(forKey: Keys.dinnerMin)) }
        set {
            d.set(clampMinute(newValue.breakfastMin), forKey: Keys.breakfastMin)
            d.set(clampMinute(newValue.lunchMin),     forKey: Keys.lunchMin)
            d.set(clampMinute(newValue.dinnerMin),    forKey: Keys.dinnerMin)
        }
    }
    var wakingWindow: WakingWindow {
        get { WakingWindow(startMin: d.integer(forKey: Keys.wakeStartMin),
                           endMin:   d.integer(forKey: Keys.wakeEndMin)) }
        set {
            d.set(clampMinute(newValue.startMin), forKey: Keys.wakeStartMin)
            d.set(clampMinute(newValue.endMin),   forKey: Keys.wakeEndMin)
        }
    }
    var doseLeadMinutes: Int {
        get { d.integer(forKey: Keys.doseLead) }
        set { d.set(max(0, newValue), forKey: Keys.doseLead) }
    }
    var doseCutoffMinutes: Int {
        get { d.integer(forKey: Keys.doseCutoff) }
        set { d.set(max(1, newValue), forKey: Keys.doseCutoff) }
    }

    // MARK: - Bedtime paper mode

    var bedtimeEnabled: Bool {
        get { d.bool(forKey: Keys.bedtimeEnabled) }
        set { d.set(newValue, forKey: Keys.bedtimeEnabled) }
    }
    var bedtimeStartMin: Int {
        get { d.integer(forKey: Keys.bedtimeStartMin) }
        set { d.set(clampMinute(newValue), forKey: Keys.bedtimeStartMin) }
    }
    var bedtimeEndMin: Int {
        get { d.integer(forKey: Keys.bedtimeEndMin) }
        set { d.set(clampMinute(newValue), forKey: Keys.bedtimeEndMin) }
    }
    var paperIntensity: PaperIntensity {
        get { PaperIntensity(rawValue: d.integer(forKey: Keys.paperIntensity)) ?? .medium }
        set { d.set(newValue.rawValue, forKey: Keys.paperIntensity) }
    }
    var bedtimeUseGamma: Bool {
        get { d.bool(forKey: Keys.bedtimeUseGamma) }
        set { d.set(newValue, forKey: Keys.bedtimeUseGamma) }
    }
    var bedtimeSnoozeUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: Keys.bedtimeSnoozeUntil)) }
        set { d.set(newValue.timeIntervalSince1970, forKey: Keys.bedtimeSnoozeUntil) }
    }
    var bedtimeDismissedUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: Keys.bedtimeDismissedUntil)) }
        set { d.set(newValue.timeIntervalSince1970, forKey: Keys.bedtimeDismissedUntil) }
    }
    var bedtimeForceUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: Keys.bedtimeForceUntil)) }
        set { d.set(newValue.timeIntervalSince1970, forKey: Keys.bedtimeForceUntil) }
    }

    private func clampMinute(_ m: Int) -> Int { min(24 * 60 - 1, max(0, m)) }

    // Derived values used by the scheduler (in seconds).
    var shortIntervalSeconds: TimeInterval { TimeInterval(shortIntervalMinutes * 60) }
    var shortDurationSeconds: TimeInterval { TimeInterval(shortDurationSecondsValue) }
    var longIntervalSeconds:  TimeInterval { TimeInterval(longIntervalMinutes * 60) }
    var longDurationSeconds:  TimeInterval { TimeInterval(longDurationMinutes * 60) }
    var idlePauseSeconds:     TimeInterval { TimeInterval(idlePauseMinutes * 60) }

    /// How many breaks occur per cycle; the last one of each cycle is a long break.
    /// e.g. long=60, short=20  ->  3 breaks per cycle (short, short, long).
    var breaksPerLong: Int {
        max(1, Int((longIntervalSeconds / shortIntervalSeconds).rounded()))
    }

    /// When the user snoozes a break ("remind me later"), how long until it returns.
    var snoozeSeconds: TimeInterval { 2 * 60 }
}
