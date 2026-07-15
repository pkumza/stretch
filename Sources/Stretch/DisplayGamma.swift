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

    /// `progress` 0 = normal display, 1 = full bedtime curve.
    static func apply(progress: Float, intensity: Settings.PaperIntensity) {
        let p = max(0, min(1, progress))
        if p <= 0.001 {
            restore()
            return
        }
        if !applied {
            captureBackups()
        }
        let warm = Float(intensity.gammaWarmth) * p
        let dim = 1 + (Float(intensity.gammaDim) - 1) * p
        writeTable(warm: warm, dim: dim)
        applied = true
    }

    static func applyBedtime(intensity: Settings.PaperIntensity) {
        apply(progress: 1, intensity: intensity)
    }

    static func restore() {
        guard applied || !backups.isEmpty else {
            CGDisplayRestoreColorSyncSettings()
            return
        }
        for b in backups {
            var r = b.red, g = b.green, bl = b.blue
            _ = CGSetDisplayTransferByTable(b.displayID, UInt32(r.count), &r, &g, &bl)
        }
        backups.removeAll()
        applied = false
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

    private static func writeTable(warm: Float, dim: Float) {
        let capacity: UInt32 = 256
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))

        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success else { return }

        for j in 0..<Int(capacity) {
            let t = CGGammaValue(j) / CGGammaValue(capacity - 1)
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
