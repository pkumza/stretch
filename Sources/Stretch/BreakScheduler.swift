import Foundation

enum BreakType: Equatable {
    case short, long

    var isLong: Bool { self == .long }

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
            if now >= nextBreak { beginBreak(type) }
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
        if case .breaking(let type, _) = state { advanceCycle(after: type) }
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

    /// Skip the current break (counts toward the cycle, just like finishing it).
    func skipBreak() {
        if case .breaking(let type, _) = state { advanceCycle(after: type) }
        onBreakEnd?()
        scheduleNextWork()
        onTick?(state)
    }

    /// Postpone: dismiss the break and bring it back shortly, same type.
    func postponeBreak() {
        let type: BreakType
        if case .breaking(let t, _) = state { type = t } else { type = nextType() }
        onBreakEnd?()
        state = .working(nextBreak: Date().addingTimeInterval(settings.postponeSeconds),
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
}
