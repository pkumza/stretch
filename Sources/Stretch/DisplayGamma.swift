import CoreGraphics
import Foundation
import os

/// Display transfer-table dimming for bedtime. This is the brightness source that
/// stays on during Space swipes; the paper NSPanel is only a warm tint / grain.
enum DisplayGamma {
    private static let logger = Logger(subsystem: "com.ziang.stretch", category: "DisplayGamma")

    private struct Backup {
        let displayID: CGDirectDisplayID
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }

    private static var backups: [Backup] = []
    private static var applied = false
    private static var lastIntensity: Settings.PaperIntensity?

    static func applyBedtime(intensity: Settings.PaperIntensity) {
        // Avoid restore→reapply flicker when called again with the same intensity
        // (e.g. every Space swipe). Still rewrite the table so a reset is corrected.
        if !applied {
            captureBackups()
        }
        lastIntensity = intensity
        writeTable(intensity: intensity)
        applied = true
    }

    static func restore() {
        guard applied || !backups.isEmpty else {
            CGDisplayRestoreColorSyncSettings()
            lastIntensity = nil
            return
        }
        for b in backups {
            var r = b.red, g = b.green, bl = b.blue
            _ = CGSetDisplayTransferByTable(b.displayID, UInt32(r.count), &r, &g, &bl)
        }
        backups.removeAll()
        applied = false
        lastIntensity = nil
        CGDisplayRestoreColorSyncSettings()
    }

    private static func captureBackups() {
        backups.removeAll()
        let capacity: UInt32 = 256
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success else { return }
        for i in 0..<Int(displayCount) {
            let id = displays[i]
            var sampleCount: UInt32 = 0
            var br = [CGGammaValue](repeating: 0, count: Int(capacity))
            var bg = [CGGammaValue](repeating: 0, count: Int(capacity))
            var bb = [CGGammaValue](repeating: 0, count: Int(capacity))
            let getErr = CGGetDisplayTransferByTable(id, capacity, &br, &bg, &bb, &sampleCount)
            if getErr == .success, sampleCount > 0 {
                backups.append(Backup(
                    displayID: id,
                    red: Array(br.prefix(Int(sampleCount))),
                    green: Array(bg.prefix(Int(sampleCount))),
                    blue: Array(bb.prefix(Int(sampleCount)))
                ))
            }
        }
    }

    private static func writeTable(intensity: Settings.PaperIntensity) {
        let capacity: UInt32 = 256
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))

        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success else { return }

        let warm = Float(intensity.gammaWarmth)
        let dim = Float(intensity.gammaDim)

        for j in 0..<Int(capacity) {
            let t = CGGammaValue(j) / CGGammaValue(capacity - 1)
            // Gentle toe + hard ceiling = clearly dimmer without crushing blacks oddly.
            let v = powf(t, 1.12) * dim
            red[j] = min(1, v * (1 + warm * 0.10))
            green[j] = min(1, v * (1 + warm * 0.02))
            blue[j] = min(1, v * (1 - warm * 0.40))
        }

        for i in 0..<Int(displayCount) {
            let id = displays[i]
            let err = CGSetDisplayTransferByTable(id, capacity, red, green, blue)
            if err != .success {
                logger.debug("CGSetDisplayTransferByTable failed for display \(id): \(err.rawValue)")
            }
        }
    }
}
