import AppKit

/// Registers a global hotkey (Control + Command + V) via CGEventTap.
/// Requires Accessibility permission.
class HotKeyManager {

    // Use a static slot so the C callback can reach the instance without Unmanaged retain/release.
    private static var shared: HotKeyManager?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        HotKeyManager.shared = self
    }

    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passRetained(event) }

                let flags   = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

                // ⌃⌘V  (Control + Command + V, keyCode 9)
                let isCtrl = flags.contains(.maskControl)
                let isCmd  = flags.contains(.maskCommand)
                let isV    = keyCode == 9

                if isCtrl && isCmd && isV {
                    DispatchQueue.main.async {
                        HotKeyManager.shared?.action()
                    }
                    return nil   // consume the event
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )

        guard let tap = eventTap else {
            print("[HotKeyManager] Failed to create event tap — Accessibility permission likely missing.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }

    deinit { stop() }
}
