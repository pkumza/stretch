import Foundation

/// Watches macOS screen lock/unlock. If the screen stays locked longer than
/// `threshold`, the user was effectively away — `onLongAway` fires on unlock.
/// `onUnlock` fires on every unlock so bedtime paper / gamma can be re-applied.
final class LockMonitor: NSObject {
    var onLongAway: (() -> Void)?
    var onUnlock: (() -> Void)?

    private var lockedAt: Date?
    private let threshold: TimeInterval = 30

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
        if Date().timeIntervalSince(lockedAt) > threshold {
            onLongAway?()
        }
    }
}
