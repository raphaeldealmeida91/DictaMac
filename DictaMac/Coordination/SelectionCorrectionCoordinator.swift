import Foundation
import OSLog

@MainActor
final class SelectionCorrectionCoordinator {
    enum State: Equatable {
        case idle
        case processing
        case preparing
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
    private let diagnosticLog: (any DiagnosticLogging)?
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
        diagnosticLog: (any DiagnosticLogging)? = nil,
        presentationDelay: Duration = SelectionCorrectionCoordinator.presentationDelay
    ) {
        self.watcher = watcher
        self.service = service
        self.presenter = presenter
        self.dictionary = dictionary
        self.activateCloud = activateCloud
        self.loadLocalModel = loadLocalModel
        self.diagnosticLog = diagnosticLog
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
        let detectedAt = watcher.latestDetectionInstant ?? .now
        state = .processing
        correctionTask = Task { [weak self] in
            await self?.runCorrection(
                snapshot,
                terms: terms,
                detectedAt: detectedAt,
                generation: currentGeneration
            )
        }
    }

    private func runCorrection(
        _ snapshot: SelectionSnapshot,
        terms: [String],
        detectedAt: ContinuousClock.Instant,
        generation: Int
    ) async {
        do {
            if await service.requiresPreparation() {
                presentPreparing(for: snapshot, generation: generation)
            }
            async let execution = service.correctWithMetrics(snapshot.text, dictionary: terms)
            async let unavailableMessage = service.engineUnavailableMessage()
            try await Task.sleep(for: presentationDelay)
            let result = try await execution
            guard !Task.isCancelled else { return }
            receive(
                result,
                snapshot: snapshot,
                unavailableMessage: await unavailableMessage,
                detectedAt: detectedAt,
                generation: generation
            )
        } catch {
            handleCorrectionFailure(error, snapshot: snapshot, generation: generation)
        }
    }

    private func handleCorrectionFailure(
        _ error: Error,
        snapshot: SelectionSnapshot,
        generation: Int
    ) {
        guard !(error is CancellationError) else { return }
        if error as? SelectionCorrectionError == .timeout {
            logger.info("result=timeout length=\(snapshot.text.count)")
        }
        finishWithoutSuggestion(generation: generation)
    }

    private func receive(
        _ execution: SelectionCorrectionExecution,
        snapshot: SelectionSnapshot,
        unavailableMessage: String?,
        detectedAt: ContinuousClock.Instant,
        generation currentGeneration: Int
    ) {
        guard generation == currentGeneration else { return }
        correctionTask = nil
        let correction = execution.correction
        guard correction.corrected != correction.original, !correction.changes.isEmpty else {
            if execution.engine == .rulesOnly, !didPresentEngineUnavailable {
                presentEngineUnavailable(
                    for: snapshot,
                    message: unavailableMessage,
                    generation: currentGeneration
                )
                return
            }
            presenter.dismiss()
            state = .idle
            return
        }
        state = .suggestion
        presenter.present(correction, for: snapshot) { [weak self] in
            self?.suggestionDidDismiss(generation: currentGeneration)
        }
        recordLatency(execution, detectedAt: detectedAt)
    }

    private func presentPreparing(for snapshot: SelectionSnapshot, generation: Int) {
        guard self.generation == generation else { return }
        state = .preparing
        presenter.presentPreparing(for: snapshot) { [weak self] in
            self?.preparationDidDismiss(generation: generation)
        }
    }

    private func preparationDidDismiss(generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        correctionTask?.cancel()
        correctionTask = nil
        state = .idle
    }

    private func recordLatency(
        _ execution: SelectionCorrectionExecution,
        detectedAt: ContinuousClock.Instant
    ) {
        diagnosticLog?.selectionCorrectionLatency(
            detectionToInference: Self.seconds(detectedAt.duration(to: execution.inferenceStartedAt)),
            inference: Self.seconds(execution.inferenceStartedAt.duration(to: execution.inferenceFinishedAt)),
            inferenceToPresentation: Self.seconds(execution.inferenceFinishedAt.duration(to: .now)),
            modelAlreadyLoaded: execution.modelAlreadyLoaded
        )
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
        presenter.dismiss()
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

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
