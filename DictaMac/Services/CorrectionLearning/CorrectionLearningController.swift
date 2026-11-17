import Combine
import Foundation

@MainActor
final class CorrectionLearningController: ObservableObject {
    @Published private(set) var pendingProposal: LearnedCorrectionEntry?
    @Published private(set) var isEmpty: Bool
    @Published private(set) var errorMessage: String?

    private let settings: any CorrectionLearningSettings
    private let repository: LearnedCorrectionRepository
    private let dictionary: any PersonalDictionary
    private let watcher: SelectionWatcher
    private let tracker: RecentDictationTracker
    private let detector: CorrectionReplacementDetector
    private let dateProvider: @Sendable () -> Date
    private var eventTask: Task<Void, Never>?

    init(
        settings: any CorrectionLearningSettings,
        repository: LearnedCorrectionRepository,
        dictionary: any PersonalDictionary,
        watcher: SelectionWatcher,
        tracker: RecentDictationTracker,
        detector: CorrectionReplacementDetector = CorrectionReplacementDetector(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.repository = repository
        self.dictionary = dictionary
        self.watcher = watcher
        self.tracker = tracker
        self.detector = detector
        self.dateProvider = dateProvider
        pendingProposal = settings.isEnabled ? repository.nextProposal() : nil
        isEmpty = repository.entries().isEmpty
    }

    var isEnabled: Bool { settings.isEnabled }

    func start() {
        guard settings.isEnabled, eventTask == nil else { return }
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
        tracker.clear()
    }

    func setEnabled(_ enabled: Bool) {
        settings.setEnabled(enabled)
        if enabled {
            refreshState()
            start()
        } else {
            stop()
            pendingProposal = nil
        }
    }

    func acceptPendingProposal() {
        guard let proposal = pendingProposal else { return }
        do {
            try addToDictionary(proposal)
            try repository.setStatus(.accepted, for: proposal.id)
            refreshState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refusePendingProposal() {
        guard let proposal = pendingProposal else { return }
        do {
            try repository.setStatus(.refused, for: proposal.id)
            refreshState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        do {
            try repository.clear()
            tracker.clear()
            refreshState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ event: SelectionEvent) {
        switch event {
        case .selected(let snapshot):
            observe(candidate: snapshot.text, sourceBundleID: snapshot.sourceBundleID)
        case .focusedText(let snapshot):
            observe(candidate: snapshot.text, sourceBundleID: snapshot.sourceBundleID)
        case .cleared:
            _ = tracker.current()
        }
    }

    private func observe(candidate: String, sourceBundleID: String?) {
        guard let observation = tracker.current(),
              sourceBundleID == observation.targetBundleID else { return }
        let replacements = detector.replacements(from: observation.text, in: candidate)
        let unseen = replacements.filter { !observation.observedPairs.contains($0) }
        guard !unseen.isEmpty else { return }
        do {
            for replacement in unseen {
                try repository.record(
                    dictated: replacement.dictated,
                    corrected: replacement.corrected,
                    at: dateProvider()
                )
            }
            tracker.markObserved(unseen)
            refreshState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addToDictionary(_ correction: LearnedCorrectionEntry) throws {
        var entries = dictionary.entries()
        if let index = entries.firstIndex(where: { Self.matches($0.canonical, correction.corrected) }) {
            var variants = entries[index].variants
            if !variants.contains(where: { Self.matches($0, correction.dictated) }) {
                variants.append(correction.dictated)
            }
            entries[index] = DictionaryEntry(canonical: entries[index].canonical, variants: variants)
        } else {
            entries.append(DictionaryEntry(
                canonical: correction.corrected,
                variants: [correction.dictated]
            ))
        }
        try dictionary.replaceEntries(entries)
    }

    private func refreshState() {
        pendingProposal = settings.isEnabled ? repository.nextProposal() : nil
        isEmpty = repository.entries().isEmpty
        errorMessage = nil
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
