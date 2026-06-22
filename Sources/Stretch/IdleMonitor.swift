import CoreGraphics
import Foundation

/// Reads how long the user has been idle — no keyboard, mouse, or scroll input.
/// Uses the HID event source, which needs no permissions.
///
/// Used so a break doesn't pop up (and get counted as "rested") while you're
/// away from the keyboard but the screen isn't locked — e.g. the Mac left on
/// over lunch or overnight.
enum IdleMonitor {
    /// Seconds since the most recent user input of any kind.
    static func secondsSinceInput() -> TimeInterval {
        // No single "any input" constant is safely bridged to Swift, so take the
        // most recent across the input event types — the smallest value wins.
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .keyDown, .flagsChanged, .scrollWheel,
        ]
        let state = CGEventSourceStateID.combinedSessionState
        return types
            .map { CGEventSource.secondsSinceLastEventType(state, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
    }
}
