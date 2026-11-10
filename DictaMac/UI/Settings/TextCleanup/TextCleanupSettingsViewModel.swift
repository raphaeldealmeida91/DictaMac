import Combine
import Foundation

@MainActor
final class TextCleanupSettingsViewModel: ObservableObject {
    @Published var engine: TextCleanupEngine {
        didSet {
            store.set(.string(engine.rawValue), for: .textCleanupEngine)
            updateLocalModelActivation(from: oldValue, to: engine)
        }
    }
    @Published var cloudModel: String { didSet { store.set(.string(cloudModel), for: .textCleanupModel) } }
    @Published var localModel: String { didSet { store.set(.string(localModel), for: .textCleanupLocalModel) } }
    @Published var removeIsolatedGenre: Bool {
        didSet { store.set(.bool(removeIsolatedGenre), for: .textCleanupRemoveIsolatedGenre) }
    }
    @Published var localTimeout: Double { didSet { store.set(.double(localTimeout), for: .textCleanupLocalTimeout) } }
    @Published var apiKey = ""
    @Published private(set) var apiKeyStatus = ""
    @Published private(set) var modelStatus = ""
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var modelIsBusy = false
    @Published private(set) var modelBadge: StatusBadge.Status = .loading

    let isLowMemoryMac: Bool
    let localModelChoices = [StoredTextCleanupSettings.defaultLocalModel, StoredTextCleanupSettings.lightLocalModel]
    private let store: any SettingsStoring
    private let manager: any LocalCleanupModelManaging
    private let keyStore: any APIKeyStoring
    private let readModelState: () -> (String, Double?, Bool, Bool, Bool)
    private var cancellables = Set<AnyCancellable>()

    init<State: LocalCleanupModelStateProviding>(
        store: any SettingsStoring,
        state: State,
        manager: any LocalCleanupModelManaging,
        keyStore: any APIKeyStoring,
        recommendedLocalModel: String,
        isLowMemoryMac: Bool
    ) {
        self.store = store
        self.manager = manager
        self.keyStore = keyStore
        self.isLowMemoryMac = isLowMemoryMac
        engine = store.string(for: .textCleanupEngine).flatMap(TextCleanupEngine.init(rawValue:)) ?? .fast
        cloudModel = store.string(for: .textCleanupModel) ?? StoredTextCleanupSettings.defaultModel
        localModel = store.string(for: .textCleanupLocalModel) ?? recommendedLocalModel
        removeIsolatedGenre = store.bool(for: .textCleanupRemoveIsolatedGenre) ?? true
        let storedTimeout = store.double(for: .textCleanupLocalTimeout) ?? StoredTextCleanupSettings.defaultLocalTimeout
        localTimeout = storedTimeout
        readModelState = { (state.status, state.downloadProgress, state.isBusy, state.isReady, state.hasError) }
        state.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.synchronizeModelState()
            }
        }
        .store(in: &cancellables)
        synchronizeModelState()
        loadAPIKey()
    }

    func loadLocalModel() {
        Task { await manager.approveDownloadAndActivate() }
    }

    func cancelLocalModelDownload() {
        Task { await manager.cancelDownload() }
    }

    func saveAPIKey() {
        do {
            try keyStore.save(apiKey)
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            apiKeyStatus = apiKey.isEmpty ? "Clé supprimée" : "Clé enregistrée"
        } catch {
            apiKeyStatus = error.localizedDescription
        }
    }

    private func loadAPIKey() {
        do {
            apiKey = try keyStore.load() ?? ""
            apiKeyStatus = apiKey.isEmpty ? "Clé non configurée" : "Clé chargée depuis le Keychain"
        } catch {
            apiKeyStatus = error.localizedDescription
        }
    }

    private func updateLocalModelActivation(from oldEngine: TextCleanupEngine, to newEngine: TextCleanupEngine) {
        guard oldEngine != newEngine else { return }
        Task {
            if newEngine == .local {
                await manager.approveDownloadAndActivate()
            } else {
                await manager.unload(reason: "Moteur local désactivé")
            }
        }
    }

    private func synchronizeModelState() {
        let state = readModelState()
        modelStatus = state.0
        downloadProgress = state.1
        modelIsBusy = state.2
        modelBadge = state.4 ? .error : (state.3 ? .ready : .loading)
    }
}
