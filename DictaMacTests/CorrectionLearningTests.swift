import XCTest
@testable import DictaMac

final class CorrectionLearningTests: XCTestCase {
    func testLearningIsDisabledByDefault() {
        let settings = StoredCorrectionLearningSettings(store: InMemorySettingsStore())

        XCTAssertFalse(settings.isEnabled)
    }

    func testDetectsShortWordReplacement() {
        let detector = CorrectionReplacementDetector()

        let replacements = detector.replacements(
            from: "Je prépare le de vie pour le client demain matin",
            in: "Je prépare le devis pour le client demain matin"
        )

        XCTAssertEqual(replacements, [
            CorrectionReplacement(dictated: "de vie", corrected: "devis")
        ])
    }

    func testDetectsReplacementInsideLongerFocusedText() {
        let detector = CorrectionReplacementDetector()

        let replacements = detector.replacements(
            from: "Je prépare le de vie pour demain matin",
            in: "Introduction précédente Je prépare le devis pour demain matin conclusion suivante"
        )

        XCTAssertEqual(replacements, [
            CorrectionReplacement(dictated: "de vie", corrected: "devis")
        ])
    }

    func testDetectsCaseCorrectionAndRemovesSurroundingPunctuation() {
        let replacements = CorrectionReplacementDetector().replacements(
            from: "J'utilise dictamac chaque jour avec mon équipe",
            in: "J'utilise DictaMac, chaque jour avec mon équipe"
        )

        XCTAssertEqual(replacements, [
            CorrectionReplacement(dictated: "dictamac", corrected: "DictaMac")
        ])
    }

    func testRejectsPunctuationOnlyChange() {
        let replacements = CorrectionReplacementDetector().replacements(
            from: "Bonjour équipe voici le compte rendu final",
            in: "Bonjour équipe, voici le compte rendu final"
        )

        XCTAssertTrue(replacements.isEmpty)
    }

    func testRejectsAmbiguousCandidateContainingUnchangedDictation() {
        let replacements = CorrectionReplacementDetector().replacements(
            from: "Je prépare le de vie pour demain matin",
            in: "Je prépare le de vie pour demain matin puis Je prépare le devis pour demain matin"
        )

        XCTAssertTrue(replacements.isEmpty)
    }

    func testRejectsCompleteRewrite() {
        let detector = CorrectionReplacementDetector()

        let replacements = detector.replacements(
            from: "Je prépare le compte rendu complet pour notre réunion de demain",
            in: "Merci de réserver une salle calme avant le déjeuner avec Alice"
        )

        XCTAssertTrue(replacements.isEmpty)
    }

    func testRejectsCompleteRewriteOfShortText() {
        let replacements = CorrectionReplacementDetector().replacements(
            from: "réunion demain matin",
            in: "déjeuner avec Alice"
        )

        XCTAssertTrue(replacements.isEmpty)
    }

    func testAcceptsSimilarRecognitionAcrossEntireShortText() {
        let replacements = CorrectionReplacementDetector().replacements(
            from: "de vie",
            in: "devis"
        )

        XCTAssertEqual(replacements, [
            CorrectionReplacement(dictated: "de vie", corrected: "devis")
        ])
    }

    func testRepositoryKeepsAtMostTwoHundredMostRecentEntries() throws {
        let storage = MemoryLearnedCorrectionStorage()
        let repository = LearnedCorrectionRepository(storage: storage)
        let start = Date(timeIntervalSince1970: 1_000)

        for index in 0...LearnedCorrectionRepository.maximumEntryCount {
            try repository.record(
                dictated: "erreur \(index)",
                corrected: "correction \(index)",
                at: start.addingTimeInterval(TimeInterval(index))
            )
        }

        XCTAssertEqual(repository.entries().count, LearnedCorrectionRepository.maximumEntryCount)
        XCTAssertFalse(repository.entries().contains(where: { $0.dictated == "erreur 0" }))
    }

    func testProposalAppearsAtSecondOccurrence() throws {
        let repository = LearnedCorrectionRepository(storage: MemoryLearnedCorrectionStorage())

        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        XCTAssertNil(repository.nextProposal())

        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        XCTAssertEqual(repository.nextProposal()?.occurrenceCount, 2)
    }

    func testRefusedPairIsNeverProposedAgain() throws {
        let repository = LearnedCorrectionRepository(storage: MemoryLearnedCorrectionStorage())
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        let proposal = try XCTUnwrap(repository.nextProposal())

        try repository.setStatus(.refused, for: proposal.id)
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())

        XCTAssertNil(repository.nextProposal())
    }

    func testRefusedPairSurvivesRepositoryCapacityTrimming() throws {
        let repository = LearnedCorrectionRepository(storage: MemoryLearnedCorrectionStorage())
        let start = Date(timeIntervalSince1970: 1_000)
        try repository.record(dictated: "de vie", corrected: "devis", at: start)
        try repository.record(dictated: "de vie", corrected: "devis", at: start)
        let refused = try XCTUnwrap(repository.nextProposal())
        try repository.setStatus(.refused, for: refused.id)

        for index in 0..<LearnedCorrectionRepository.maximumEntryCount {
            try repository.record(
                dictated: "erreur \(index)",
                corrected: "correction \(index)",
                at: start.addingTimeInterval(TimeInterval(index + 1))
            )
        }

        XCTAssertEqual(repository.entries().count, LearnedCorrectionRepository.maximumEntryCount)
        XCTAssertTrue(repository.entries().contains(where: { $0.id == refused.id }))
    }

    func testJSONStorageUsesOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = JSONLearnedCorrectionStore(directoryProvider: { directory })

        try storage.save([sampleEntry])

        let attributes = try FileManager.default.attributesOfItem(
            atPath: storage.storageURL().path
        )
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testClearRemovesEveryStoredCorrection() throws {
        let storage = MemoryLearnedCorrectionStorage()
        let repository = LearnedCorrectionRepository(storage: storage)
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())

        try repository.clear()

        XCTAssertTrue(repository.entries().isEmpty)
        XCTAssertTrue(storage.didClear)
    }

    @MainActor
    func testRecentDictationExpiresAfterSixtySeconds() {
        let clock = TestDateBox(date: Date(timeIntervalSince1970: 1_000))
        let tracker = RecentDictationTracker(
            settings: TestCorrectionLearningSettings(isEnabled: true),
            dateProvider: { clock.date }
        )

        tracker.recordInjectedText("Texte dicté", targetBundleID: "com.example.Editor")
        clock.date = clock.date.addingTimeInterval(61)

        XCTAssertNil(tracker.current())
    }

    @MainActor
    func testAcceptingProposalAddsVariantToPersonalDictionary() throws {
        let settings = TestCorrectionLearningSettings(isEnabled: true)
        let repository = LearnedCorrectionRepository(storage: MemoryLearnedCorrectionStorage())
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        let dictionary = MemoryPersonalDictionary()
        let tracker = RecentDictationTracker(settings: settings)
        let controller = CorrectionLearningController(
            settings: settings,
            repository: repository,
            dictionary: dictionary,
            watcher: makeWatcher(),
            tracker: tracker
        )

        controller.acceptPendingProposal()

        XCTAssertEqual(dictionary.entries(), [
            DictionaryEntry(canonical: "devis", variants: ["de vie"])
        ])
        XCTAssertNil(controller.pendingProposal)
    }

    @MainActor
    func testProposalStaysHiddenUntilLearningIsEnabled() throws {
        let settings = TestCorrectionLearningSettings(isEnabled: false)
        let repository = LearnedCorrectionRepository(storage: MemoryLearnedCorrectionStorage())
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        try repository.record(dictated: "de vie", corrected: "devis", at: Date())
        let controller = CorrectionLearningController(
            settings: settings,
            repository: repository,
            dictionary: MemoryPersonalDictionary(),
            watcher: makeWatcher(),
            tracker: RecentDictationTracker(settings: settings)
        )

        XCTAssertNil(controller.pendingProposal)

        controller.setEnabled(true)

        XCTAssertEqual(controller.pendingProposal?.corrected, "devis")
        controller.stop()
    }

    private var sampleEntry: LearnedCorrectionEntry {
        LearnedCorrectionEntry(
            id: UUID(),
            dictated: "de vie",
            corrected: "devis",
            occurrenceCount: 2,
            lastSeen: Date(),
            status: .observed
        )
    }

    @MainActor
    private func makeWatcher() -> SelectionWatcher {
        SelectionWatcher(
            eventMonitor: TestSelectionMonitor(),
            accessibilityReader: TestSelectedTextReader(),
            clipboardReader: TestSelectedTextReader(),
            settings: TestSelectionSettings(),
            ownBundleID: "com.example.DictaMac"
        )
    }
}

private final class MemoryLearnedCorrectionStorage: LearnedCorrectionStoring, @unchecked Sendable {
    private(set) var entries: [LearnedCorrectionEntry] = []
    private(set) var didClear = false

    func load() throws -> [LearnedCorrectionEntry] { entries }

    func save(_ entries: [LearnedCorrectionEntry]) throws {
        self.entries = entries
    }

    func clear() throws {
        entries = []
        didClear = true
    }
}

private final class TestDateBox: @unchecked Sendable {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

private final class TestCorrectionLearningSettings: CorrectionLearningSettings, @unchecked Sendable {
    private(set) var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
}

private final class MemoryPersonalDictionary: PersonalDictionary, @unchecked Sendable {
    private var storedEntries: [DictionaryEntry] = []

    func entries() -> [DictionaryEntry] { storedEntries }

    func replaceEntries(_ entries: [DictionaryEntry]) throws {
        storedEntries = entries
    }

    func addCanonicalTerm(_ canonical: String) throws -> Bool {
        storedEntries.append(DictionaryEntry(canonical: canonical, variants: []))
        return true
    }
}

@MainActor
private final class TestSelectionMonitor: SelectionEventMonitoring {
    func events() -> AsyncStream<SelectionMonitorEvent> { AsyncStream { _ in } }
    func stop() {}
}

@MainActor
private final class TestSelectedTextReader: SelectedTextReading {
    func readSelection() -> SelectionSnapshot? { nil }
}

private struct TestSelectionSettings: SelectionCorrectionSettings {
    let isEnabled = false
    let isClipboardFallbackEnabled = false
    let allowsCloud = false
    let excludedBundleIDs: Set<String> = []
}
