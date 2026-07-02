import AppKit
import CoreAudio
import CoreGraphics
import os

/// Best-effort, permission-free detection of "don't interrupt me right now"
/// situations, so the scheduler can defer a break overlay instead of covering
/// a meeting, a screen share, or a presentation.
///
/// Two independent signals defer a break, and they differ in scope:
///   1. The microphone is live  -> you're in a call/meeting (Feishu, Zoom, …),
///      even if muted, and regardless of which app owns it. This also catches
///      screen sharing. Meetings defer *every* break — short and long.
///   2. A *media/meeting* app fills the screen -> a fullscreen/maximized video
///      (YouTube etc.), Keynote, or a conferencing app, gated on an allowlist so
///      a fullscreen editor/terminal still earns its breaks. This only defers
///      the short eye-breaks: you should still get up for the long break, even
///      mid-video.
///
/// Neither requires Screen Recording or Microphone permission: we only read
/// device *state* and window *geometry*, never audio samples or titles.
enum PresentationGuard {
    private static let logger = Logger(subsystem: "com.ziang.stretch", category: "PresentationGuard")

    enum HoldReason {
        case microphone
        case fullscreenMedia(bundleID: String, name: String)

        var menuDescription: String {
            switch self {
            case .microphone:
                return "Temporarily held: microphone in use"
            case .fullscreenMedia(_, let name):
                return "Temporarily held: \(name) is fullscreen"
            }
        }
    }

    static func shouldSuppress(for type: BreakType) -> Bool {
        guard let reason = holdReason(for: type) else { return false }
        switch reason {
        case .microphone:
            logger.info("Suppressing \(type.logName, privacy: .public) break: microphone input device is running")
        case .fullscreenMedia(let bundleID, let name):
            logger.info("Suppressing short break: frontmost media app is fullscreen or maximized bundleID=\(bundleID, privacy: .public) app=\(name, privacy: .public)")
        }
        return true
    }

    static func holdReason(for type: BreakType) -> HoldReason? {
        if isMicrophoneInUse() { return .microphone }
        if type == .short, let front = mediaAppFullscreen() {
            return .fullscreenMedia(bundleID: front.bundleID, name: front.name)
        }
        return nil
    }

    // MARK: - 1. Microphone in use (covers any meeting/call, incl. Feishu)

    private static func isMicrophoneInUse() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return (status == noErr && device != 0) ? device : nil
    }

    // MARK: - 2. A media/meeting app fills the screen

    /// Apps whose full-screen/maximized window we treat as "don't interrupt":
    /// browsers (web video, Google Meet), video players, presentation tools, and
    /// conferencing apps. A fullscreen editor/terminal is deliberately absent —
    /// you still want eye breaks while coding.
    private static let mediaBundleIDs: Set<String> = [
        // Browsers — fullscreen video, web-based meetings
        "com.google.Chrome", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.microsoft.edgemac", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        // Video players
        "com.apple.QuickTimePlayerX", "com.colliderli.iina",
        "org.videolan.vlc", "com.apple.TV",
        // Presentations
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint",
        // Conferencing (mostly redundant with the mic check, but cheap insurance)
        "com.electron.lark", "com.bytedance.lark", "com.larksuite.larkApp",
        "us.zoom.xos", "com.tencent.meeting", "com.tencent.xinWeChat",
        "com.microsoft.teams", "com.microsoft.teams2",
        "com.cisco.webexmeetings", "com.webex.meetingmanager",
    ]

    /// True when an allowlisted media/meeting app is frontmost and filling the
    /// screen (fullscreen *or* maximized).
    private static func mediaAppFullscreen() -> (bundleID: String, name: String)? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy == .regular,
              let bundleID = front.bundleIdentifier,
              mediaBundleIDs.contains(bundleID),
              fillsScreen(front) else { return nil }
        return (bundleID, front.localizedName ?? "unknown")
    }

    /// Whether `app` is filling a screen. macOS exposes this two ways:
    ///   (a) a normal-level window covers a screen — true fullscreen, *or* a
    ///       maximized window (which stops below the menu bar and above the
    ///       Dock; many people watch video this way, so we count it); or
    ///   (b) native fullscreen, which lives on its own Space that a background
    ///       agent can't see — so the app contributes *no* window to our Space.
    ///       (Verified empirically: fullscreen Chrome shows up as exactly this.)
    private static func fillsScreen(_ app: NSRunningApplication) -> Bool {
        let pid = Int(app.processIdentifier)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let screenSizes = NSScreen.screens.map { $0.frame.size }

        var hasWindowHere = false
        for win in list where (win[kCGWindowOwnerPID as String] as? Int) == pid {
            guard (win[kCGWindowLayer as String] as? Int) == 0 else { continue }
            hasWindowHere = true
            guard let boundsDict = win[kCGWindowBounds as String] else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as! CFDictionary, &rect)
            else { continue }
            // Full width, and tall enough to be fullscreen or maximized. The
            // ~120pt of vertical slack absorbs the menu bar and Dock; a normal
            // (smaller) window stays well under it, so only media apps the user
            // has blown up to fill the screen count.
            if screenSizes.contains(where: {
                rect.width >= $0.width - 2 && rect.height >= $0.height - 120
            }) { return true }
        }
        return !hasWindowHere
    }
}
