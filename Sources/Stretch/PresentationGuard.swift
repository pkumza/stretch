import CoreAudio
import os

/// Best-effort, permission-free detection of "don't interrupt me right now"
/// situations, so the scheduler can defer a break overlay instead of covering
/// a meeting or call.
///
/// The only automatic hold signal is microphone activity. A fullscreen or
/// maximized app never suppresses a break; if Feishu or Chrome is fullscreen
/// but the mic is not live, Stretch should still remind you to rest.
///
/// Neither requires Screen Recording or Microphone permission: we only read
/// device *state*, never audio samples.
enum PresentationGuard {
    private static let logger = Logger(subsystem: "com.ziang.stretch", category: "PresentationGuard")

    enum HoldReason {
        case microphone

        var menuDescription: String {
            switch self {
            case .microphone:
                return "Temporarily held: microphone in use"
            }
        }
    }

    static func shouldSuppress(for type: BreakType) -> Bool {
        guard let reason = holdReason(for: type) else { return false }
        switch reason {
        case .microphone:
            logger.info("Suppressing \(type.logName, privacy: .public) break: microphone input device is running")
        }
        return true
    }

    static func holdReason(for _: BreakType) -> HoldReason? {
        if isMicrophoneInUse() { return .microphone }
        return nil
    }

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
}
