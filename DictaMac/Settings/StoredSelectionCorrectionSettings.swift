import Foundation

struct StoredSelectionCorrectionSettings: SelectionCorrectionSettings, SelectionCorrectionSettingsWriting {
    static let defaultEnabled = false
    static let defaultClipboardFallbackEnabled = false
    static let defaultAllowsCloud = false
    static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.apple.keychainaccess",
        "com.apple.Passwords"
    ]

    private let store: any SettingsStoring

    init(store: any SettingsStoring = UserDefaultsSettingsStore()) {
        self.store = store
    }

    var isEnabled: Bool {
        store.bool(for: .selectionCorrectionEnabled) ?? Self.defaultEnabled
    }

    var isClipboardFallbackEnabled: Bool {
        store.bool(for: .selectionCorrectionClipboardFallback) ?? Self.defaultClipboardFallbackEnabled
    }

    var allowsCloud: Bool {
        store.bool(for: .selectionCorrectionAllowsCloud) ?? Self.defaultAllowsCloud
    }

    var excludedBundleIDs: Set<String> {
        guard let storedBundleIDs = store.stringArray(for: .selectionCorrectionExcludedApps) else {
            return Self.defaultExcludedBundleIDs
        }
        return Set(storedBundleIDs)
    }

    func setAllowsCloud(_ allowed: Bool) {
        store.set(.bool(allowed), for: .selectionCorrectionAllowsCloud)
    }
}
