import AppKit
import Carbon

/// Global hotkeys that work while other apps are focused (Carbon RegisterEventHotKey).
/// Does not require Screen Recording; Accessibility is not required for these hotkeys.
final class HotKeyController {
    var onToggleBedtime: (() -> Void)?
    var onSnoozeBedtime: (() -> Void)?

    private var toggleRef: EventHotKeyRef?
    private var snoozeRef: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private enum HotKeyID: UInt32 {
        case toggle = 1
        case snooze = 2
    }

    func start() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                switch HotKeyID(rawValue: hotKeyID.id) {
                case .toggle: controller.onToggleBedtime?()
                case .snooze: controller.onSnoozeBedtime?()
                case .none: break
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handler
        )

        // ⌘⇧B — toggle bedtime paper mode
        register(
            id: .toggle,
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(cmdKey | shiftKey),
            into: &toggleRef
        )
        // ⌘⇧S — snooze paper mode 15 minutes
        register(
            id: .snooze,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey),
            into: &snoozeRef
        )
    }

    func stop() {
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        if let snoozeRef { UnregisterEventHotKey(snoozeRef) }
        if let handler { RemoveEventHandler(handler) }
        toggleRef = nil
        snoozeRef = nil
        handler = nil
    }

    private func register(id: HotKeyID, keyCode: UInt32, modifiers: UInt32,
                          into ref: inout EventHotKeyRef?) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53545248), id: id.rawValue) // 'STRH'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
    }

    deinit { stop() }
}
