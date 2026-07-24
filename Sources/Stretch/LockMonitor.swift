import Foundation

/// Watches macOS screen lock/unlock. Reports how long the screen stayed locked
/// when it unlocks, so the scheduler can treat a long lock as rest (and avoid
/// firing another long break immediately). `onUnlock` fires on every unlock so
/// bedtime paper / gamma can be re-applied.
final class LockMonitor: NSObject {
    /// Fired on unlock with the seconds the screen was locked (may be tiny).
    var onAwayEnded: ((TimeInterval) -> Void)?
    var onUnlock: (() -> Void)?

    private var lockedAt: Date?

    override init() {
        super.init()
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked),
                        name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked),
                        name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func screenLocked() {
        lockedAt = Date()
    }

    @objc private func screenUnlocked() {
        defer { lockedAt = nil }
        onUnlock?()
        guard let lockedAt else { return }
        let duration = Date().timeIntervalSince(lockedAt)
        if duration > 0 {
            onAwayEnded?(duration)
        }
    }
}
