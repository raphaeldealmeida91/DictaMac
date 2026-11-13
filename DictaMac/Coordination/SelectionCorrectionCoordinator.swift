import Foundation
import OSLog

@MainActor
final class SelectionCorrectionCoordinator {
    enum State: Equatable {
        case idle
        case processing
        case suggestion
        case engineUnavailable
    }

    static let presentationDelay = Duration.milliseconds(400)

    private(set) var state: State = .idle
    private let watcher: SelectionWatcher
    private let service: any SelectionCorrectionService
    private let presenter: any SelectionCorrectionPresenting
    private let dictionary: any PersonalDictionary
    private let presentationDelay: Duration
    private let activateCloud: @MainActor () -> Void
    private let loadLocalModel: @MainActor () -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "selection"
    )
    private var eventTask: Task<Void, Never>?
    private var correctionTask: Task<Void, Never>?
    private var generation = 0
    private var didPresentEngineUnavailable = false

    init(
        watcher: SelectionWatcher,
        service: any SelectionCorrectionService,
        presenter: any SelectionCorrectionPresenting,
        dictionary: any PersonalDictionary,
        activateCloud: @escaping @MainActor () -> Void = {},
        loadLocalModel: @escaping @MainActor () -> Void = {},
        presentationDelay: Duration = SelectionCorrectionCoordinator.presentationDelay
    ) {
        self.watcher = watcher
        self.service = service
        self.presenter = presenter
        self.dictionary = dictionary
        self.activateCloud = activateCloud
        self.loadLocalModel = loadLocalModel
        self.presentationDelay = presentationDelay
    }

    func start() {
        guard eventTask == nil else { return }
        didPresentEngineUnavailable = false
        logger.info("feature activated")
        Task { [service] in await service.prepare() }
        let events = watcher.events()
        watcher.start()
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        watcher.stop()
        clearActiveSuggestion()
    }

    private func handle(_ event: SelectionEvent) {
        switch event {
        case .selected(let snapshot):
            logger.info("selection event received length=\(snapshot.text.count)")
            correct(snapshot)
        case .cleared: clearActiveSuggestion()
        }
    }

    private func correct(_ snapshot: SelectionSnapshot) {
        correctionTask?.cancel()
        presenter.dismiss()
        generation += 1
        let currentGeneration = generation
        let terms = dictionary.entries().map(\.canonical)
        state = .processing
        correctionTask = Task { [weak self, service, presentationDelay] in
            do {
                let engine = await service.engineStatus()
                async let correction = service.correct(snapshot.text, dictionary: terms)
                async let unavailableMessage = service.engineUnavailableMessage()
                try await Task.sleep(for: presentationDelay)
                let result = try await correction
                let message = await unavailableMessage
                guard !Task.isCancelled else { return }
                self?.receive(
                    result,
                    snapshot: snapshot,
                    engine: engine,
                    unavailableMessage: message,
                    generation: currentGeneration
                )
            } catch is CancellationError {
                return
            } catch SelectionCorrectionError.timeout {
                self?.logger.info("result=timeout length=\(snapshot.text.count)")
                self?.finishWithoutSuggestion(generation: currentGeneration)
            } catch {
                self?.finishWithoutSuggestion(generation: currentGeneration)
            }
        }
    }

    private func receive(
        _ correction: SelectionCorrection,
        snapshot: SelectionSnapshot,
        engine: SelectionCorrectionEngine,
        unavailableMessage: String?,
        generation currentGeneration: Int
    ) {
        guard generation == currentGeneration else { return }
        correctionTask = nil
        guard correction.corrected != correction.original, !correction.changes.isEmpty else {
            if engine == .rulesOnly, !didPresentEngineUnavailable {
                presentEngineUnavailable(
                    for: snapshot,
                    message: unavailableMessage,
                    generation: currentGeneration
                )
                return
            }
            state = .idle
            return
        }
        state = .suggestion
        presenter.present(correction, for: snapshot) { [weak self] in
            self?.suggestionDidDismiss(generation: currentGeneration)
        }
    }

    private func presentEngineUnavailable(
        for snapshot: SelectionSnapshot,
        message: String?,
        generation: Int
    ) {
        didPresentEngineUnavailable = true
        state = .engineUnavailable
        presenter.presentEngineUnavailable(
            for: snapshot,
            message: message,
            onActivateCloud: activateCloud,
            onLoadLocal: loadLocalModel
        ) { [weak self] in
            self?.suggestionDidDismiss(generation: generation)
        }
    }

    private func finishWithoutSuggestion(generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        correctionTask = nil
        state = .idle
    }

    private func suggestionDidDismiss(generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        state = .idle
    }

    private func clearActiveSuggestion() {
        generation += 1
        correctionTask?.cancel()
        correctionTask = nil
        presenter.dismiss()
        state = .idle
    }
}
