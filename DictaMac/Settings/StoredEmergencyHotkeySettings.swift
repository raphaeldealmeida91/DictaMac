@preconcurrency import ApplicationServices

struct StoredEmergencyHotkeySettings: EmergencyHotkeySettings {
    static let defaultModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    private let store: any SettingsStoring

    init(store: any SettingsStoring = UserDefaultsSettingsStore()) {
        self.store = store
    }

    var configuredModifiers: CGEventFlags {
        var flags: CGEventFlags = []
        if value(for: .emergencyHotkeyControl) { flags.insert(.maskControl) }
        if value(for: .emergencyHotkeyOption) { flags.insert(.maskAlternate) }
        if value(for: .emergencyHotkeyCommand) { flags.insert(.maskCommand) }
        return flags.isEmpty ? Self.defaultModifiers : flags
    }

    private func value(for key: SettingsKey) -> Bool {
        store.bool(for: key) ?? true
    }
}
