import AppKit
import CoreAudio
import CoreGraphics

/// Best-effort, permission-free detection of "don't interrupt me right now"
/// situations, so the scheduler can defer a break overlay instead of covering
/// a meeting, a screen share, or a presentation.
///
/// Two independent signals, either of which defers the break:
///   1. The microphone is live  -> you're in a call/meeting (Feishu, Zoom, …),
///      even if muted, and regardless of which app owns it. This also catches
///      screen sharing, which during a meeting goes hand in hand with the mic.
///   2. A *media/meeting* app is frontmost and fullscreen -> a fullscreen video
///      (YouTube etc.), Keynote presenting, or a conferencing app. We gate on
///      an allowlist so a fullscreen editor/terminal still earns its eye break.
///
/// Neither requires Screen Recording or Microphone permission: we only read
/// device *state* and window *geometry*, never audio samples or titles.
enum PresentationGuard {

    static func shouldSuppress() -> Bool {
        isMicrophoneInUse() || isMediaAppFullscreen()
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

    // MARK: - 2. A media/meeting app is frontmost and fullscreen

    /// Apps whose *fullscreen* we treat as "don't interrupt": browsers (web
    /// video, Google Meet), video players, presentation tools, and conferencing
    /// apps. A fullscreen editor/terminal is deliberately absent — you still
    /// want eye breaks while coding.
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

    /// True when an allowlisted media/meeting app is frontmost *and* fullscreen.
    private static func isMediaAppFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy == .regular,
              let bundleID = front.bundleIdentifier,
              mediaBundleIDs.contains(bundleID) else { return false }
        return isFullscreen(front)
    }

    /// Whether `app` is running fullscreen. macOS exposes this two ways:
    ///   (a) a normal-level window of the app fills an entire screen (borderless
    ///       / same-Space fullscreen, common for video players); or
    ///   (b) native fullscreen, which lives on its own Space that a background
    ///       agent can't see — so the app contributes *no* window to our Space.
    ///       (Verified empirically: fullscreen Chrome shows up as exactly this.)
    private static func isFullscreen(_ app: NSRunningApplication) -> Bool {
        let pid = Int(app.processIdentifier)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let screenSizes = NSScreen.screens.map { $0.frame.size }

        var hasWindowHere = false
        for win in list where (win[kCGWindowOwnerPID as String] as? Int) == pid {
            guard (win[kCGWindowLayer as String] as? Int) == 0 else { continue }
            hasWindowHere = true
            // A window filling an entire screen (incl. the menu-bar strip). A
            // merely maximized window is ~1 menu-bar shorter, so the `- 2` floor
            // keeps a maximized browser from counting as fullscreen.
            guard let boundsDict = win[kCGWindowBounds as String] else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as! CFDictionary, &rect)
            else { continue }
            if screenSizes.contains(where: {
                rect.width >= $0.width - 2 && rect.height >= $0.height - 2
            }) { return true }
        }
        return !hasWindowHere
    }
}
