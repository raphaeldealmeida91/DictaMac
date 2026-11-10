import Combine
import Foundation

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    @Published var feedbackSoundsEnabled: Bool { didSet { persist(.bool(feedbackSoundsEnabled), .feedbackSoundsEnabled) } }
    @Published var historyEnabled: Bool { didSet { persist(.bool(historyEnabled), .historyEnabled) } }
    @Published var maximumRecordingDuration: Double {
        didSet { persist(.double(maximumRecordingDuration), .recordingMaximumDuration) }
    }
    @Published var emergencyUsesControl: Bool { didSet { persist(.bool(emergencyUsesControl), .emergencyHotkeyControl) } }
    @Published var emergencyUsesOption: Bool { didSet { persist(.bool(emergencyUsesOption), .emergencyHotkeyOption) } }
    @Published var emergencyUsesCommand: Bool { didSet { persist(.bool(emergencyUsesCommand), .emergencyHotkeyCommand) } }
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatus: String?
    @Published private(set) var historyIsEmpty = true
    @Published private(set) var historyError: String?

    let recordingDurationRange = StoredRecordingSettings.allowedRange
    let versionDescription: String
    private let store: any SettingsStoring
    private let setLaunchAtLogin: (Bool) -> Void
    private let refreshLaunchAtLogin: () -> Void
    private let clearStoredHistory: () throws -> Void
    private let readServiceState: () -> (Bool, String?, Bool)
    private var cancellables = Set<AnyCancellable>()

    init<Launch: LaunchAtLoginManaging, History: HistoryManaging>(
        store: any SettingsStoring,
        launchAtLogin: Launch,
        history: History,
        versionInfo: AppVersionInfo = .current
    ) {
        self.store = store
        feedbackSoundsEnabled = store.bool(for: .feedbackSoundsEnabled) ?? true
        historyEnabled = store.bool(for: .historyEnabled) ?? StoredHistorySettings.defaultEnabled
        maximumRecordingDuration = StoredRecordingSettings.clamped(
            store.double(for: .recordingMaximumDuration) ?? StoredRecordingSettings.defaultMaximumDuration
        )
        emergencyUsesControl = store.bool(for: .emergencyHotkeyControl) ?? true
        emergencyUsesOption = store.bool(for: .emergencyHotkeyOption) ?? true
        emergencyUsesCommand = store.bool(for: .emergencyHotkeyCommand) ?? true
        versionDescription = versionInfo.description
        setLaunchAtLogin = launchAtLogin.setEnabled
        refreshLaunchAtLogin = launchAtLogin.refresh
        clearStoredHistory = history.clear
        readServiceState = { (launchAtLogin.isEnabled, launchAtLogin.statusMessage, history.entries.isEmpty) }
        observe(launchAtLogin.objectWillChange)
        observe(history.objectWillChange)
        synchronizeServiceState()
    }

    func appear() {
        refreshLaunchAtLogin()
        synchronizeServiceState()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        setLaunchAtLogin(enabled)
        synchronizeServiceState()
    }

    func clearHistory() {
        do {
            try clearStoredHistory()
            historyError = nil
        } catch {
            historyError = error.localizedDescription
        }
        synchronizeServiceState()
    }

    private func persist(_ value: SettingsValue, _ key: SettingsKey) {
        store.set(value, for: key)
    }

    private func observe<PublisherType: Publisher>(_ publisher: PublisherType)
    where PublisherType.Output == Void, PublisherType.Failure == Never {
        publisher.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.synchronizeServiceState()
            }
        }
        .store(in: &cancellables)
    }

    private func synchronizeServiceState() {
        let state = readServiceState()
        launchAtLoginEnabled = state.0
        launchAtLoginStatus = state.1
        historyIsEmpty = state.2
    }
}
