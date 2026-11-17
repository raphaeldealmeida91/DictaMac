final class StoredCorrectionLearningSettings: CorrectionLearningSettings, @unchecked Sendable {
    private let store: any SettingsStoring

    init(store: any SettingsStoring) {
        self.store = store
    }

    var isEnabled: Bool {
        store.bool(for: .correctionLearningEnabled) ?? false
    }

    func setEnabled(_ enabled: Bool) {
        store.set(.bool(enabled), for: .correctionLearningEnabled)
    }
}
