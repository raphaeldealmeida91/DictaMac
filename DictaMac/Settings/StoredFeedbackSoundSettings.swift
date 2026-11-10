struct StoredFeedbackSoundSettings: FeedbackSoundSettings {
    private let store: any SettingsStoring

    init(store: any SettingsStoring = UserDefaultsSettingsStore()) {
        self.store = store
    }

    var isEnabled: Bool { store.bool(for: .feedbackSoundsEnabled) ?? true }
}
