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

    private var timer: Timer?
    private var breaksDoneInCycle = 0
    private var settings: Settings { .shared }

    /// Fired every second with the current state (drive the menu-bar label).
    var onTick: ((SchedulerState) -> Void)?
    /// Fired when a break begins (show the overlay).
    var onBreakStart: ((BreakType, TimeInterval) -> Void)?
    /// Fired when a break ends or is dismissed (hide the overlay).
    var onBreakEnd: (() -> Void)?
    /// Asked just before an *automatic* break fires, with the break's type.
    /// Returning true defers the break (currently: microphone in use)
    /// without losing its place in the cycle. Manual "take break now" ignores
    /// this.
    var shouldSuppressBreak: ((BreakType) -> Bool)?
    /// Returns true when the user is idle/away (no input for a while). Being
    /// away is itself a rest, so we neither show nor count a break.
    var isUserAway: (() -> Bool)?

    /// While a break is being deferred, how soon to re-check whether the user
    /// is free again.
    private let suppressRecheckSeconds: TimeInterval = 60

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
        switch state {
        case .working(let nextBreak, let type):
            if isUserAway?() == true {
                // Idle/away counts as rest: don't show or record a break, and
                // hold the next one a full work interval out so you don't get a
                // break the instant you sit back down.
                state = .working(nextBreak: now.addingTimeInterval(settings.shortIntervalSeconds),
                                 nextType: type)
            } else if now >= nextBreak {
                if shouldSuppressBreak?(type) == true {
                    // Busy (microphone in use): push the same break a
                    // little later and re-check, leaving the cycle untouched.
                    Self.logger.info("Deferring \(type.logName, privacy: .public) break for \(self.suppressRecheckSeconds, privacy: .public)s because PresentationGuard suppressed it")
                    state = .working(nextBreak: now.addingTimeInterval(suppressRecheckSeconds),
                                     nextType: type)
                } else {
                    beginBreak(type)
                }
            }
        case .breaking(_, let ends):
            if now >= ends { finishBreak() }
        case .paused(let until):
            if let until = until, now >= until { scheduleNextWork() }
        }
        onTick?(state)
    }

    private func nextType() -> BreakType {
        breaksDoneInCycle >= settings.breaksPerLong - 1 ? .long : .short
    }

    private func scheduleNextWork() {
        let type = nextType()
        state = .working(nextBreak: Date().addingTimeInterval(settings.shortIntervalSeconds),
                         nextType: type)
    }

    private func beginBreak(_ type: BreakType) {
        let duration = type.isLong ? settings.longDurationSeconds : settings.shortDurationSeconds
        state = .breaking(type: type, ends: Date().addingTimeInterval(duration))
        onBreakStart?(type, duration)
    }

    private func finishBreak() {
        if case .breaking(let type, _) = state {
            let duration = type.isLong ? settings.longDurationSeconds : settings.shortDurationSeconds
            HistoryStore.shared.record(isLong: type.isLong, action: .completed,
                                       durationSec: Int(duration))
            advanceCycle(after: type)
        }
        onBreakEnd?()
        scheduleNextWork()
    }

    private func advanceCycle(after type: BreakType) {
        if type.isLong { breaksDoneInCycle = 0 }
        else { breaksDoneInCycle += 1 }
    }

    // MARK: - User actions

    func takeBreakNow(_ type: BreakType) {
        beginBreak(type)
        onTick?(state)
    }

    /// "Reset timer" — restart the countdown to the next break from now.
    func reschedule() {
        scheduleNextWork()
        onTick?(state)
    }

    /// Permanent skip: drop this break entirely (counts toward the cycle).
    func skipBreak() {
        if case .breaking(let type, _) = state {
            HistoryStore.shared.record(isLong: type.isLong, action: .skipped)
            advanceCycle(after: type)
        }
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
        state = .working(nextBreak: Date().addingTimeInterval(settings.snoozeSeconds),
                         nextType: type)
        onTick?(state)
    }

    func pause(for interval: TimeInterval?) {
        onBreakEnd?()
        state = .paused(until: interval.map { Date().addingTimeInterval($0) })
        onTick?(state)
    }

    func resume() {
        scheduleNextWork()
        onTick?(state)
    }

    /// The screen was locked long enough to count as a real break: dismiss any
    /// overlay, restart the long-break cycle, and reschedule from now. A manual
    /// Pause is respected (we don't silently un-pause the user).
    func resetAfterAwayBreak() {
        if case .paused = state { return }
        breaksDoneInCycle = 0
        onBreakEnd?()
        scheduleNextWork()
        onTick?(state)
    }
}
