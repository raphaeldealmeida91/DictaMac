import Foundation

@MainActor
final class RecentDictationTracker: DictationCorrectionTracking {
    struct Observation {
        let text: String
        let targetBundleID: String
        let date: Date
        var observedPairs: Set<CorrectionReplacement>
    }

    static let observationDuration: TimeInterval = 60

    private let settings: any CorrectionLearningSettings
    private let dateProvider: @Sendable () -> Date
    private var observation: Observation?

    init(
        settings: any CorrectionLearningSettings,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.dateProvider = dateProvider
    }

    func recordInjectedText(_ text: String, targetBundleID: String?) {
        guard settings.isEnabled,
              !text.isEmpty,
              let targetBundleID,
              !targetBundleID.isEmpty else { return }
        observation = Observation(
            text: text,
            targetBundleID: targetBundleID,
            date: dateProvider(),
            observedPairs: []
        )
    }

    func current() -> Observation? {
        expireIfNeeded()
        return observation
    }

    func markObserved(_ replacements: [CorrectionReplacement]) {
        guard var observation else { return }
        observation.observedPairs.formUnion(replacements)
        self.observation = observation
    }

    func clear() {
        observation = nil
    }

    private func expireIfNeeded() {
        guard let observation else { return }
        if dateProvider().timeIntervalSince(observation.date) > Self.observationDuration {
            self.observation = nil
        }
    }
}
