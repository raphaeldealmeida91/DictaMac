import Foundation

@MainActor
final class SelectionCorrectionCoordinator {
    enum State: Equatable {
        case idle
        case processing
        case suggestion
    }

    static let presentationDelay = Duration.milliseconds(400)

    private(set) var state: State = .idle
    private let watcher: SelectionWatcher
    private let service: any SelectionCorrectionService
    private let presenter: any SelectionCorrectionPresenting
    private let dictionary: any PersonalDictionary
    private let presentationDelay: Duration
    private var eventTask: Task<Void, Never>?
    private var correctionTask: Task<Void, Never>?
    private var generation = 0

    init(
        watcher: SelectionWatcher,
        service: any SelectionCorrectionService,
        presenter: any SelectionCorrectionPresenting,
        dictionary: any PersonalDictionary,
        presentationDelay: Duration = SelectionCorrectionCoordinator.presentationDelay
    ) {
        self.watcher = watcher
        self.service = service
        self.presenter = presenter
        self.dictionary = dictionary
        self.presentationDelay = presentationDelay
    }

    func start() {
        guard eventTask == nil else { return }
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
        case .selected(let snapshot): correct(snapshot)
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
                async let correction = service.correct(snapshot.text, dictionary: terms)
                try await Task.sleep(for: presentationDelay)
                let result = try await correction
                guard !Task.isCancelled else { return }
                self?.receive(result, snapshot: snapshot, generation: currentGeneration)
            } catch is CancellationError {
                return
            } catch {
                self?.finishWithoutSuggestion(generation: currentGeneration)
            }
        }
    }

    private func receive(
        _ correction: SelectionCorrection,
        snapshot: SelectionSnapshot,
        generation currentGeneration: Int
    ) {
        guard generation == currentGeneration else { return }
        correctionTask = nil
        guard correction.corrected != correction.original, !correction.changes.isEmpty else {
            state = .idle
            return
        }
        state = .suggestion
        presenter.present(correction, for: snapshot) { [weak self] in
            self?.suggestionDidDismiss(generation: currentGeneration)
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
