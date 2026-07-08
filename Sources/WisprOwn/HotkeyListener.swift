import Cocoa

/// Spec 01 — detects "Left Option held alone" via a listen-only CGEventTap.
///
/// State machine:
///   idle --option down--> arming --300ms elapsed--> recording --option up--> onStop
///   arming --option up before 300ms--> idle (nothing happens)
///   arming --any other key--> idle (accent typing like ñ/ü passes through untouched)
///   recording --any other key--> idle + onCancel
final class HotkeyListener {
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}

    /// Settable at runtime from the Settings window.
    var option: HotkeyOption = .current
    let armDelay: TimeInterval = 0.3

    private enum State { case idle, arming, recording }
    private var state: State = .idle
    private var armTimer: DispatchWorkItem?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Returns false when the event tap could not be created (missing
    /// Accessibility permission). Safe to call again after the grant.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon!).takeUnretainedValue()
                listener.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        dlog("hotkey: listening (\(option.rawValue), keyCode \(option.keyCode))")
        return true
    }

    func stop() {
        armTimer?.cancel()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        state = .idle
    }

    // Runs on the main run loop (the tap's source is scheduled there).
    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables taps that stall; re-enable and carry on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged && eventKeyCode == option.keyCode {
            let keyDown = event.flags.contains(option.flag)
            keyDown ? hotkeyDown() : hotkeyUp()
            return
        }

        // Any other keyboard activity while the hotkey is held is a combo
        // (e.g. Option+N for ñ) — never a dictation.
        if state != .idle {
            comboDetected()
        }
    }

    private func hotkeyDown() {
        guard state == .idle else { return }
        state = .arming
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .arming else { return }
            self.state = .recording
            dlog("hotkey: START")
            self.onStart()
        }
        armTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + armDelay, execute: work)
    }

    private func hotkeyUp() {
        armTimer?.cancel()
        switch state {
        case .arming:
            dlog("hotkey: tap ignored (<300ms)")
            state = .idle
        case .recording:
            state = .idle
            dlog("hotkey: STOP")
            onStop()
        case .idle:
            break
        }
    }

    private func comboDetected() {
        armTimer?.cancel()
        let wasRecording = state == .recording
        state = .idle
        if wasRecording {
            dlog("hotkey: CANCEL (combo key while recording)")
            onCancel()
        } else {
            dlog("hotkey: arm aborted (combo key)")
        }
    }
}
