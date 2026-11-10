import Combine
import Foundation

@MainActor
final class FirstLaunchAssistantViewModel: ObservableObject {
    @Published private(set) var step: FirstLaunchStep = .microphone
    @Published private(set) var statuses: [AppPermission: PermissionStatus] = [:]
    @Published private(set) var modelStatus: String
    @Published private(set) var modelProgress: Double?
    @Published private(set) var modelIsReady: Bool
    @Published private(set) var dictationState: DictationState
    @Published var fnConfigurationConfirmed = false
    @Published var modelSkipped = false
    @Published var dictationTrialSkipped = false

    private let store: any SettingsStoring
    private let permissionManager: any PermissionManaging
    private let loadModel: () async throws -> Void
    private let readModelState: () -> (String, Double?, Bool, Bool)
    private let readActivityState: () -> DictationState
    private let openKeyboardSettingsAction: () -> Void
    private var skippedPermissions = Set<AppPermission>()
    private var observedDictation = false
    private var cancellables = Set<AnyCancellable>()

    init<Permissions: PermissionManaging, Model: TranscriptionModelStateProviding,
         Loader: TranscriptionModelReloading, Activity: DictationActivityProviding>(
        store: any SettingsStoring,
        permissions: Permissions,
        modelState: Model,
        modelLoader: Loader,
        activity: Activity,
        openKeyboardSettings: @escaping () -> Void
    ) {
        self.store = store
        permissionManager = permissions
        modelStatus = modelState.status
        modelProgress = modelState.downloadProgress
        modelIsReady = modelState.isReady
        dictationState = activity.state
        loadModel = { try await modelLoader.reloadConfiguredModel() }
        readModelState = {
            (modelState.status, modelState.downloadProgress, modelState.isReady, modelState.isBusy)
        }
        readActivityState = { activity.state }
        openKeyboardSettingsAction = openKeyboardSettings
        observe(permissions.objectWillChange) { [weak self] in self?.refreshPermissions() }
        observe(modelState.objectWillChange) { [weak self] in self?.refreshModelState() }
        observe(activity.objectWillChange) { [weak self] in self?.refreshActivityState() }
        refreshPermissions()
    }

    var isFirstLaunchCompleted: Bool {
        store.bool(for: .firstLaunchAssistantCompleted) ?? false
    }

    var canContinue: Bool {
        guard let permission = step.permission else { return canFinish }
        return status(for: permission).isAuthorized || skippedPermissions.contains(permission)
    }

    var canFinish: Bool {
        fnConfigurationConfirmed
            && (modelIsReady || modelSkipped)
            && (observedDictation || dictationTrialSkipped)
    }

    var didObserveDictation: Bool { observedDictation }

    func appear() {
        permissionManager.startPeriodicRefresh()
        refreshPermissions()
    }

    func disappear() {
        permissionManager.stopPeriodicRefresh()
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func requestCurrentPermission() {
        guard let permission = step.permission else { return }
        Task {
            statuses[permission] = await permissionManager.request(permission)
            objectWillChange.send()
        }
    }

    func openCurrentPermissionSettings() {
        guard let permission = step.permission else { return }
        permissionManager.openSystemSettings(for: permission)
    }

    func skipCurrentPermission() {
        guard let permission = step.permission else { return }
        skippedPermissions.insert(permission)
        objectWillChange.send()
    }

    func continueForward() {
        guard canContinue, let next = FirstLaunchStep(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .readyToDictate {
            prepareModelIfNeeded()
        }
    }

    func goBack() {
        guard let previous = FirstLaunchStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func openKeyboardSettings() {
        openKeyboardSettingsAction()
    }

    func finish() -> Bool {
        guard canFinish else { return false }
        store.set(.bool(true), for: .firstLaunchAssistantCompleted)
        return true
    }

    private func prepareModelIfNeeded() {
        let state = readModelState()
        guard !state.2, !state.3 else { return }
        Task { try? await loadModel() }
    }

    private func refreshPermissions() {
        statuses = Dictionary(
            uniqueKeysWithValues: AppPermission.allCases.map { ($0, permissionManager.status(for: $0)) }
        )
    }

    private func refreshModelState() {
        let state = readModelState()
        modelStatus = state.0
        modelProgress = state.1
        modelIsReady = state.2
    }

    private func refreshActivityState() {
        dictationState = readActivityState()
        if dictationState != .idle {
            observedDictation = true
        }
    }

    private func observe<PublisherType: Publisher>(
        _ publisher: PublisherType,
        action: @escaping @MainActor () -> Void
    ) where PublisherType.Output == Void, PublisherType.Failure == Never {
        publisher.sink {
            Task { @MainActor in
                await Task.yield()
                action()
            }
        }
        .store(in: &cancellables)
    }
}
