struct StoredHistorySettings: HistorySettings {
    static let defaultEnabled = true

    private let store: any SettingsStoring

    init(store: any SettingsStoring = UserDefaultsSettingsStore()) {
        self.store = store
    }

    var isEnabled: Bool { store.bool(for: .historyEnabled) ?? Self.defaultEnabled }
}
