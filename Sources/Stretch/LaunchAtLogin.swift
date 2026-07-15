import Foundation
import ServiceManagement
import os

/// Keeps macOS Login Items in sync with `Settings.launchAtLogin` (default: on).
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.ziang.stretch", category: "LaunchAtLogin")

    /// Apply the user's preference. Call once at launch so Stretch opens after reboot by default.
    static func applyPreference() {
        guard #available(macOS 13, *) else { return }
        let want = Settings.shared.launchAtLogin
        let status = SMAppService.mainApp.status
        do {
            if want {
                if status != .enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Registered as login item")
                }
            } else if status == .enabled {
                try SMAppService.mainApp.unregister()
                logger.info("Unregistered login item")
            }
        } catch {
            // Ad-hoc / non-/Applications builds often cannot register; Preferences checkbox handles UX.
            logger.debug("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        Settings.shared.launchAtLogin = enabled
        guard #available(macOS 13, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            logger.debug("Login item setEnabled(\(enabled)) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
