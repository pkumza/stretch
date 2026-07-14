import Foundation

/// Optional system grayscale via Universal Access Color Filters.
/// Uses the `com.apple.universalaccess` preference domain (no Screen Recording).
/// On some macOS versions the change applies immediately; if not, the user can
/// toggle Color Filters once in System Settings → Accessibility → Display.
enum AccessibilityColorFilter {
    private static let domain = "com.apple.universalaccess" as CFString
    private static let enabledKey = "ColorFilterEnabled" as CFString
    private static let typeKey = "ColorFilterType" as CFString
    private static let legacyGrayscaleKey = "grayscale" as CFString
    /// 0 = Grayscale in Accessibility Color Filters.
    private static let grayscaleType = 0

    private struct PriorState {
        let filterEnabled: Bool
        let filterType: Int
        let legacyGrayscale: Bool
    }

    private static var prior: PriorState?

    /// Turn grayscale on, remembering the previous filter so we can restore later.
    static func enableGrayscale() {
        if prior == nil {
            prior = PriorState(
                filterEnabled: boolValue(enabledKey),
                filterType: intValue(typeKey),
                legacyGrayscale: boolValue(legacyGrayscaleKey)
            )
        }
        setBool(enabledKey, true)
        setInt(typeKey, grayscaleType)
        setBool(legacyGrayscaleKey, true)
        synchronizeAndNotify()
    }

    /// Restore whatever Color Filters looked like before we touched them.
    static func restore() {
        guard let prior else {
            setBool(enabledKey, false)
            setBool(legacyGrayscaleKey, false)
            synchronizeAndNotify()
            return
        }
        setBool(enabledKey, prior.filterEnabled)
        setInt(typeKey, prior.filterType)
        setBool(legacyGrayscaleKey, prior.legacyGrayscale)
        self.prior = nil
        synchronizeAndNotify()
    }

    // MARK: - Preferences I/O

    private static func boolValue(_ key: CFString) -> Bool {
        if let v = CFPreferencesCopyAppValue(key, domain) as? Bool { return v }
        return false
    }

    private static func intValue(_ key: CFString) -> Int {
        if let n = CFPreferencesCopyAppValue(key, domain) as? NSNumber {
            return n.intValue
        }
        return 0
    }

    private static func setBool(_ key: CFString, _ value: Bool) {
        CFPreferencesSetAppValue(key, value as CFBoolean, domain)
    }

    private static func setInt(_ key: CFString, _ value: Int) {
        CFPreferencesSetAppValue(key, value as CFNumber, domain)
    }

    private static func synchronizeAndNotify() {
        CFPreferencesAppSynchronize(domain)
        // Nudge Universal Access / display pipeline to re-read prefs.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let names = [
            "com.apple.UniversalAccess.PreferenceChanged",
            "com.apple.accessibility.cache.colorfilter",
            "com.apple.accessibility.settingschanged",
        ]
        for name in names {
            CFNotificationCenterPostNotification(
                center,
                CFNotificationName(name as CFString),
                nil,
                nil,
                true
            )
        }
    }
}
