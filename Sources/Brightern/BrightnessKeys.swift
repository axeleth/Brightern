import AppKit
import Carbon.HIToolbox

/// The keyboard's brightness keys, for when there's no built-in screen for them to control (lid closed).
/// macOS then sends them as plain key presses (key codes 144 and 145) and ignores them. Brightern registers
/// them as global hotkeys, which needs no special permissions. A registered hotkey is no longer seen by
/// macOS, so Brightern only registers them while it's the one using them. Main thread only.
final class BrightnessKeys {
    /// Called for each step: once on a press, then repeatedly while the key is held.
    var onStep: ((_ up: Bool, _ fine: Bool) -> Void)?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { register() } else { unregister() }
        }
    }

    /// Key codes for brightness up (F2) and down (F1) on Apple keyboards.
    private static let upKeyCode: UInt32 = 144
    private static let downKeyCode: UInt32 = 145
    private static let signature: OSType = 0x4252_544E  // "BRTN"
    /// Option-Shift with a brightness key makes smaller steps, as it does for the MacBook's screen.
    private static let fineModifiers = UInt32(optionKey | shiftKey)

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var heldKey: UInt32?
    private var repeatTimer: Timer?

    /// The next level on a scale of `steps` equal steps, as the brightness keys move it.
    /// A level between steps (e.g. set by the monitor's own buttons) moves to the next step in that direction.
    static func step(from percent: Int, up: Bool, steps: Int) -> Int {
        let count = Double(steps)
        let position = Double(min(max(percent, 0), 100)) * count / 100
        let nearest = position.rounded()
        // Levels are whole percentages, so a step like 6.25% is stored as 6%: allow for that rounding.
        let onStep = abs(position - nearest) <= 0.5 * count / 100 + 1e-9
        let from = onStep ? nearest : (up ? position.rounded(.down) : position.rounded(.up))
        let next = min(max(from + (up ? 1 : -1), 0), count)
        return Int((next * 100 / count).rounded())
    }

    private func register() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            guard let event, let context,
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == BrightnessKeys.signature
            else { return OSStatus(eventNotHandledErr) }
            let keys = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
            keys.handle(id.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)

        for (keyCode, up) in [(Self.upKeyCode, true), (Self.downKeyCode, false)] {
            for fine in [false, true] {
                var hotKey: EventHotKeyRef?
                let id = EventHotKeyID(signature: Self.signature, id: Self.id(up: up, fine: fine))
                let status = RegisterEventHotKey(
                    keyCode, fine ? Self.fineModifiers : 0, id, GetApplicationEventTarget(), 0, &hotKey)
                if status == noErr, let hotKey {
                    hotKeys.append(hotKey)
                } else {
                    NSLog("Brightern: couldn't register brightness key \(keyCode) (fine: \(fine)): \(status)")
                }
            }
        }
    }

    private func unregister() {
        stopRepeating()
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private static func id(up: Bool, fine: Bool) -> UInt32 {
        (up ? 1 : 0) | (fine ? 2 : 0)
    }

    /// Hotkeys report one press and one release, with no key repeat, so holding a key is
    /// repeated here at the user's key repeat rate.
    private func handle(_ id: UInt32, pressed: Bool) {
        guard pressed else {
            stopRepeating()
            return
        }
        guard heldKey != id else { return }
        let up = id & 1 != 0, fine = id & 2 != 0
        stopRepeating()
        heldKey = id
        onStep?(up, fine)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatDelay, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatInterval, repeats: true) {
                [weak self] _ in self?.onStep?(up, fine)
            }
        }
    }

    private func stopRepeating() {
        heldKey = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
