import Combine
import Foundation

@MainActor
final class TranscriptionSettingsViewModel: ObservableObject {
    @Published var model: String { didSet { store.set(.string(model), for: .transcriptionModel) } }
    @Published var automaticLanguage: Bool {
        didSet { store.set(.bool(automaticLanguage), for: .transcriptionAutomaticLanguage) }
    }
    @Published var language: String { didSet { store.set(.string(language), for: .transcriptionLanguage) } }
    @Published private(set) var modelStatus = ""
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var modelIsBusy = false
    @Published private(set) var modelIsReady = false
    @Published private(set) var loadError: String?

    let isLowMemoryMac: Bool
    let fallbackModel = StoredTranscriptionSettings.fallbackModel
    private let store: any SettingsStoring
    private let reloadModel: () async throws -> Void
    private let readModelState: () -> (String, Double?, Bool, Bool)
    private var cancellables = Set<AnyCancellable>()

    init<State: TranscriptionModelStateProviding>(
        store: any SettingsStoring,
        state: State,
        loader: any TranscriptionModelReloading,
        recommendedModel: String,
        isLowMemoryMac: Bool
    ) {
        self.store = store
        self.isLowMemoryMac = isLowMemoryMac
        model = store.string(for: .transcriptionModel) ?? recommendedModel
        automaticLanguage = store.bool(for: .transcriptionAutomaticLanguage) ?? false
        language = store.string(for: .transcriptionLanguage) ?? "fr"
        reloadModel = { try await loader.reloadConfiguredModel() }
        readModelState = { (state.status, state.downloadProgress, state.isBusy, state.isReady) }
        state.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.synchronizeModelState()
            }
        }
        .store(in: &cancellables)
        synchronizeModelState()
    }

    func applyAndLoad() {
        loadError = nil
        Task {
            do {
                try await reloadModel()
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func synchronizeModelState() {
        let state = readModelState()
        modelStatus = state.0
        downloadProgress = state.1
        modelIsBusy = state.2
        modelIsReady = state.3
    }
}
