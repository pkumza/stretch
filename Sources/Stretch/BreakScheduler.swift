import Foundation
import os

enum BreakType: Equatable {
    case short, long

    var isLong: Bool { self == .long }
    var logName: String { isLong ? "long" : "short" }

    var title: String {
        isLong ? "Time for a long break" : "Time for a short break"
    }
}

enum SchedulerState {
    case working(nextBreak: Date, nextType: BreakType)
    case breaking(type: BreakType, ends: Date)
    case paused(until: Date?)
}

/// The engine. A single 1-second timer drives the whole state machine and
/// reports changes through the closures below.
final class BreakScheduler {
    private static let logger = Logger(subsystem: "com.ziang.stretch", category: "BreakScheduler")

    private(set) var state: SchedulerState = .paused(until: nil)

    /// Accumulated "eye debt" in seconds. Drives menu-bar color. Never decays
    /// with wall time alone — only real rest / away settlement reduces it.
    private(set) var eyeStrainSeconds: TimeInterval = 0

    /// Highest strain reached since the last clear (for history).
    private var strainPeakSeconds: TimeInterval = 0

    /// Seconds banked toward the next long break (capped at one long duration).
    private(set) var longBreakCredit: TimeInterval = 0

    /// Only log a debt-cleared history row when the peak was at least this long.
    private let minDebtRecordSeconds: TimeInterval = 60

    private var timer: Timer?
    private var breaksDoneInCycle = 0
    private var currentBreakDuration: TimeInterval = 0
    private var settings: Settings { .shared }

    /// After the mic releases on an overdue break, wait this long before showing
    /// the overlay (lets you hang up cleanly).
    private let postCallDelay: TimeInterval = 30
    /// Skip strain boost (seconds of debt).
    private let skipStrainBoost: TimeInterval = 15 * 60
    /// Strain rate while a snooze countdown is running.
    private let snoozeStrainRate: TimeInterval = 0.35
    /// Ignore sub-second jitter when detecting end of an away episode.
    private let awayNoiseFloor: TimeInterval = 3

    /// Set when an overdue break was held for the mic and the mic has since
    /// cleared; break fires at this time unless the mic returns.
    private var postCallAt: Date?

    /// Idle-away episode tracking (lock away is settled via `settleAwayEpisode`).
    private var idleAwayActive = false
    private var peakIdleAway: TimeInterval = 0
    private var lastAwaySettleAt: Date?
    /// True after snooze until the break fires or the schedule is reset.
    private var snoozeActive = false

    /// Fired every second with the current state (drive the menu-bar label).
    var onTick: ((SchedulerState) -> Void)?
    /// Fired when a break begins (show the overlay).
    var onBreakStart: ((BreakType, TimeInterval) -> Void)?
    /// Fired when a break ends or is dismissed (hide the overlay).
    var onBreakEnd: (() -> Void)?
    /// Asked just before an *automatic* break fires, with the break's type.
    /// Returning true defers the break (microphone in use) without losing its
    /// place in the cycle. Manual "take break now" ignores this.
    var shouldSuppressBreak: ((BreakType) -> Bool)?
    /// Seconds since last user input (0 when actively using the Mac).
    var secondsIdle: (() -> TimeInterval)?

    func start() {
        scheduleNextWork()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // MARK: - Core loop

    private func tick() {
        let now = Date()
        let idle = secondsIdle?() ?? 0
        let isAway = idle >= awayNoiseFloor

        if isAway {
            idleAwayActive = true
            peakIdleAway = max(peakIdleAway, idle)
        } else if idleAwayActive {
            let duration = peakIdleAway
            idleAwayActive = false
            peakIdleAway = 0
            settleAwayEpisode(duration: duration)
        }

        switch state {
        case .working(let nextBreak, let type):
            if isAway {
                // Don't fire breaks while away; settlement runs on return.
                break
            }
            if now >= nextBreak {
                accumulateStrain(1)
                if shouldSuppressBreak?(type) == true {
                    postCallAt = nil
                    Self.logger.info("Holding \(type.logName, privacy: .public) break — microphone in use")
                } else {
                    if postCallAt == nil {
                        postCallAt = now.addingTimeInterval(postCallDelay)
                        Self.logger.info("Mic clear; starting \(self.postCallDelay, privacy: .public)s post-call wait before \(type.logName, privacy: .public) break")
                    }
                    if let deadline = postCallAt, now >= deadline {
                        self.postCallAt = nil
                        beginBreak(type)
                    }
                }
            } else {
                postCallAt = nil
                if snoozeActive {
                    accumulateStrain(snoozeStrainRate)
                }
            }

        case .breaking(_, let ends):
            if now >= ends { finishBreak() }

        case .paused(let until):
            if !isAway {
                accumulateStrain(1)
            }
            if let until, now >= until { scheduleNextWork() }
        }

        onTick?(state)
    }

    private func nextType() -> BreakType {
        breaksDoneInCycle >= settings.breaksPerLong - 1 ? .long : .short
    }

    private func scheduleNextWork() {
        postCallAt = nil
        snoozeActive = false
        let type = nextType()
        state = .working(nextBreak: Date().addingTimeInterval(settings.shortIntervalSeconds),
                         nextType: type)
    }

    private func nominalDuration(for type: BreakType) -> TimeInterval {
        type.isLong ? settings.longDurationSeconds : settings.shortDurationSeconds
    }

    /// Long breaks are shortened by banked credit, with a small floor so a long
    /// never disappears entirely after partial credit.
    private func plannedDuration(for type: BreakType) -> TimeInterval {
        let nominal = nominalDuration(for: type)
        guard type.isLong else { return nominal }
        let floor = max(30, nominal * 0.2)
        return max(floor, nominal - longBreakCredit)
    }

    private func consumeLongCredit(planned _: TimeInterval) {
        // Credit is fully applied into this long (via plannedDuration); clear it.
        longBreakCredit = 0
    }

    /// - Parameter duration: nil uses the planned duration (long credit applied).
    ///   A non-nil value is a top-up / custom length; caller must already have
    ///   consumed long credit when appropriate.
    private func beginBreak(_ type: BreakType, duration: TimeInterval? = nil, creditConsumed: Bool = false) {
        postCallAt = nil
        snoozeActive = false
        let finalDuration: TimeInterval
        if let duration {
            finalDuration = max(1, duration)
            if type.isLong, !creditConsumed {
                consumeLongCredit(planned: plannedDuration(for: type))
            }
        } else {
            let planned = plannedDuration(for: type)
            if type.isLong { consumeLongCredit(planned: planned) }
            finalDuration = max(1, planned)
        }
        currentBreakDuration = finalDuration
        state = .breaking(type: type, ends: Date().addingTimeInterval(finalDuration))
        onBreakStart?(type, finalDuration)
    }

    private func finishBreak() {
        if case .breaking(let type, _) = state {
            HistoryStore.shared.record(isLong: type.isLong, action: .completed,
                                       durationSec: Int(currentBreakDuration.rounded()))
            advanceCycle(after: type)
            clearStrain()
        }
        onBreakEnd?()
        scheduleNextWork()
    }

    private func advanceCycle(after type: BreakType) {
        if type.isLong { breaksDoneInCycle = 0 }
        else { breaksDoneInCycle += 1 }
    }

    private func accumulateStrain(_ delta: TimeInterval) {
        eyeStrainSeconds = max(0, eyeStrainSeconds + delta)
        strainPeakSeconds = max(strainPeakSeconds, eyeStrainSeconds)
    }

    private func reduceStrain(_ delta: TimeInterval) {
        eyeStrainSeconds = max(0, eyeStrainSeconds - delta)
    }

    /// Zero eye debt. When `record` and the episode peaked high enough, append a
    /// small history note with that peak.
    private func clearStrain(record: Bool = true) {
        let peak = strainPeakSeconds
        eyeStrainSeconds = 0
        strainPeakSeconds = 0
        guard record, peak >= minDebtRecordSeconds else { return }
        HistoryStore.shared.record(isLong: false, action: .debtCleared,
                                   durationSec: Int(peak.rounded()))
    }

    // MARK: - Away settlement

    /// Call when a continuous away episode ends (idle returned, or screen unlocked).
    func settleAwayEpisode(duration: TimeInterval) {
        guard duration >= awayNoiseFloor else { return }
        // Debounce lock+idle double settlement.
        if let last = lastAwaySettleAt, Date().timeIntervalSince(last) < 1.5 {
            return
        }
        lastAwaySettleAt = Date()

        if case .paused = state {
            // Pause is respected for scheduling, but away still rests the eyes.
            reduceStrain(duration)
            if duration >= settings.longDurationSeconds {
                longBreakCredit = 0
                clearStrain()
            } else if duration >= settings.shortDurationSeconds {
                bankLongCredit(duration)
            }
            onTick?(state)
            return
        }

        if case .breaking = state {
            // Already resting on-screen; away doesn't change the overlay.
            reduceStrain(duration)
            onTick?(state)
            return
        }

        guard case .working(let nextBreak, let type) = state else {
            reduceStrain(duration)
            onTick?(state)
            return
        }

        let now = Date()
        let imminent = now >= nextBreak || postCallAt != nil

        if imminent {
            settleImminentAway(duration: duration, type: type)
        } else {
            settleFarAway(duration: duration)
        }
        onTick?(state)
    }

    private func settleImminentAway(duration: TimeInterval, type: BreakType) {
        let planned = plannedDuration(for: type)
        if duration >= planned {
            Self.logger.info("Away \(Int(duration))s satisfied imminent \(type.logName) break (\(Int(planned))s)")
            if type.isLong { consumeLongCredit(planned: planned) }
            silentComplete(type: type, durationSec: Int(planned.rounded()))
        } else {
            let remaining = planned - duration
            Self.logger.info("Away \(Int(duration))s; topping up \(type.logName) break with \(Int(remaining))s")
            if type.isLong { consumeLongCredit(planned: planned) }
            reduceStrain(duration)
            beginBreak(type, duration: remaining, creditConsumed: true)
        }
    }

    private func settleFarAway(duration: TimeInterval) {
        let longDur = settings.longDurationSeconds
        let shortDur = settings.shortDurationSeconds

        if duration >= longDur {
            // Plan B: a full long rest away from the desk counts as the long break.
            Self.logger.info("Far away \(Int(duration))s ≥ long duration — silent long complete")
            longBreakCredit = 0
            silentComplete(type: .long, durationSec: Int(longDur.rounded()))
            return
        }

        if duration >= shortDur {
            bankLongCredit(duration)
            reduceStrain(duration)
            Self.logger.info("Far away \(Int(duration))s — banked long credit (now \(Int(self.longBreakCredit))s)")
            return
        }

        // Noise: short glance away.
    }

    private func bankLongCredit(_ duration: TimeInterval) {
        let cap = settings.longDurationSeconds
        longBreakCredit = min(cap, longBreakCredit + duration)
    }

    private func silentComplete(type: BreakType, durationSec: Int) {
        postCallAt = nil
        HistoryStore.shared.record(isLong: type.isLong, action: .completed, durationSec: durationSec)
        advanceCycle(after: type)
        clearStrain()
        onBreakEnd?()
        scheduleNextWork()
    }

    // MARK: - User actions

    func takeBreakNow(_ type: BreakType) {
        beginBreak(type)
        onTick?(state)
    }

    /// Restart the next-break countdown only (Preferences). Does not clear eye debt.
    func reschedule() {
        scheduleNextWork()
        onTick?(state)
    }

    /// Menu "Reset timer": new countdown, clear eye-debt color and long credit.
    func resetTimer() {
        longBreakCredit = 0
        clearStrain()
        scheduleNextWork()
        onTick?(state)
    }

    /// Permanent skip: drop this break entirely (counts toward the cycle).
    func skipBreak() {
        if case .breaking(let type, _) = state {
            HistoryStore.shared.record(isLong: type.isLong, action: .skipped)
            advanceCycle(after: type)
        }
        accumulateStrain(skipStrainBoost)
        onBreakEnd?()
        scheduleNextWork()
        onTick?(state)
    }

    /// Snooze: dismiss the break and bring it back shortly, same type.
    func snoozeBreak() {
        let type: BreakType
        if case .breaking(let t, _) = state {
            type = t
            HistoryStore.shared.record(isLong: t.isLong, action: .snoozed)
        } else {
            type = nextType()
        }
        onBreakEnd?()
        // Mild bump up front; tick continues at snoozeStrainRate while waiting.
        accumulateStrain(30)
        snoozeActive = true
        postCallAt = nil
        state = .working(nextBreak: Date().addingTimeInterval(settings.snoozeSeconds),
                         nextType: type)
        onTick?(state)
    }

    func pause(for interval: TimeInterval?) {
        onBreakEnd?()
        postCallAt = nil
        snoozeActive = false
        state = .paused(until: interval.map { Date().addingTimeInterval($0) })
        onTick?(state)
    }

    func resume() {
        scheduleNextWork()
        onTick?(state)
    }
}
