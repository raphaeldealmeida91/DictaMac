import Combine
import Foundation

@MainActor
final class SelectionCorrectionSettingsViewModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published var allowsCloud: Bool {
        didSet { store.set(.bool(allowsCloud), for: .selectionCorrectionAllowsCloud) }
    }
    @Published var usesClipboardFallback: Bool {
        didSet { store.set(.bool(usesClipboardFallback), for: .selectionCorrectionClipboardFallback) }
    }
    @Published private(set) var excludedApps: [RunningApplicationInfo]

    private let store: any SettingsStoring
    private let permissions: any PermissionManaging
    private let applications: any RunningApplicationProviding
    private let ownBundleID: String?
    private let setFeatureEnabled: @MainActor (Bool) -> Void

    init(
        store: any SettingsStoring,
        permissions: any PermissionManaging,
        applications: any RunningApplicationProviding,
        ownBundleID: String?,
        setFeatureEnabled: @escaping @MainActor (Bool) -> Void
    ) {
        self.store = store
        self.permissions = permissions
        self.applications = applications
        self.ownBundleID = ownBundleID
        self.setFeatureEnabled = setFeatureEnabled
        isEnabled = store.bool(for: .selectionCorrectionEnabled)
            ?? StoredSelectionCorrectionSettings.defaultEnabled
        allowsCloud = store.bool(for: .selectionCorrectionAllowsCloud)
            ?? StoredSelectionCorrectionSettings.defaultAllowsCloud
        usesClipboardFallback = store.bool(for: .selectionCorrectionClipboardFallback)
            ?? StoredSelectionCorrectionSettings.defaultClipboardFallbackEnabled
        let excluded = store.stringArray(for: .selectionCorrectionExcludedApps)
            ?? Array(StoredSelectionCorrectionSettings.defaultExcludedBundleIDs)
        excludedApps = Self.applicationInfos(for: excluded)
    }

    var availableApplications: [RunningApplicationInfo] {
        let excluded = Set(excludedApps.map(\.bundleID))
        return applications.applications()
            .filter { $0.bundleID != ownBundleID && !excluded.contains($0.bundleID) }
            .uniqued(by: \.bundleID)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        store.set(.bool(enabled), for: .selectionCorrectionEnabled)
        setFeatureEnabled(enabled)
        guard enabled, permissions.status(for: .accessibility) != .authorized else { return }
        Task { _ = await permissions.request(.accessibility) }
    }

    func addExcludedApplication(_ application: RunningApplicationInfo) {
        guard !excludedApps.contains(where: { $0.bundleID == application.bundleID }) else { return }
        excludedApps.append(application)
        excludedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistExcludedApps()
    }

    func removeExcludedApplication(bundleID: String) {
        excludedApps.removeAll { $0.bundleID == bundleID }
        persistExcludedApps()
    }

    private func persistExcludedApps() {
        store.set(.stringArray(excludedApps.map(\.bundleID)), for: .selectionCorrectionExcludedApps)
    }

    private static func applicationInfos(for bundleIDs: [String]) -> [RunningApplicationInfo] {
        bundleIDs.map { bundleID in
            RunningApplicationInfo(name: displayName(for: bundleID), bundleID: bundleID)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func displayName(for bundleID: String) -> String {
        let names = [
            "com.apple.Terminal": "Terminal",
            "com.googlecode.iterm2": "iTerm2",
            "com.1password.1password": "1Password",
            "com.agilebits.onepassword7": "1Password 7",
            "com.bitwarden.desktop": "Bitwarden",
            "com.dashlane.Dashlane": "Dashlane",
            "com.apple.keychainaccess": "Trousseaux d’accès",
            "com.apple.Passwords": "Mots de passe"
        ]
        return names[bundleID] ?? bundleID
    }
}

private extension Sequence {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
