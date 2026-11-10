@preconcurrency import ApplicationServices

final class EmergencyHotkeyDetector: @unchecked Sendable {
    private let settings: any EmergencyHotkeySettings
    private let runtime: EmergencyRuntime
    private let recovery: any EmergencyRecovering
    private var chordIsDown = false

    init(
        settings: any EmergencyHotkeySettings,
        runtime: EmergencyRuntime,
        recovery: any EmergencyRecovering
    ) {
        self.settings = settings
        self.runtime = runtime
        self.recovery = recovery
    }

    func process(_ snapshot: HotkeyEventSnapshot) {
        guard snapshot.kind == .flagsChanged || snapshot.kind == .keyDown else { return }
        let required = settings.configuredModifiers.rawValue
        let isDown = required != 0 && snapshot.flags & required == required
        if isDown, !chordIsDown {
            chordIsDown = true
            runtime.setIdle(false)
            recovery.begin(reason: "global_hotkey", hotkey: true)
        } else if !isDown {
            chordIsDown = false
        }
    }

    func reset() {
        chordIsDown = false
    }
}
