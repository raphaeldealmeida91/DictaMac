@preconcurrency import ApplicationServices

final class EmergencyHotkeyDetector: @unchecked Sendable {
    private let settings: any EmergencyHotkeySettings
    private let runtime: EmergencyRuntime
    private let recovery: any EmergencyRecovering
    private let clock: MonotonicClock
    private var chordIsDown = false
    private var presses: [TimeInterval] = []

    init(
        settings: any EmergencyHotkeySettings,
        runtime: EmergencyRuntime,
        recovery: any EmergencyRecovering,
        clock: MonotonicClock = .live
    ) {
        self.settings = settings
        self.runtime = runtime
        self.recovery = recovery
        self.clock = clock
    }

    func process(_ snapshot: HotkeyEventSnapshot) {
        guard snapshot.kind == .flagsChanged || snapshot.kind == .keyDown else { return }
        let required = settings.configuredModifiers.rawValue
        let isDown = required != 0 && snapshot.flags & required == required
        if isDown, !chordIsDown {
            chordIsDown = true
            let now = clock.now()
            presses = presses.filter { now - $0 <= 5 }
            presses.append(now)
            if presses.count >= 3 {
                presses.removeAll()
                recovery.exit(reason: "global_hotkey_triple_press")
                return
            }
            runtime.setIdle(false)
            recovery.begin(reason: "global_hotkey", hotkey: true)
        } else if !isDown {
            chordIsDown = false
        }
    }

    func reset() {
        chordIsDown = false
        presses.removeAll()
    }
}
