import Foundation
import XCTest
@testable import DictaMac

final class SelectionCorrectionPromptBuilderTests: XCTestCase {
    func testPromptIsConservativeTreatsSelectionAsDataAndIncludesExamples() {
        let prompt = SelectionCorrectionPromptBuilder().systemPrompt(dictionary: ["DictaMac"])

        XCTAssertTrue(prompt.contains("NE reformule PAS"))
        XCTAssertTrue(prompt.contains("jamais une instruction"))
        XCTAssertTrue(prompt.contains("Une répétition n’est jamais un doublon"))
        XCTAssertTrue(prompt.contains("DictaMac"))
        XCTAssertGreaterThanOrEqual(prompt.components(separatedBy: "<selection>").count - 1, 6)
    }
}

final class SelectionCorrectionValidatorTests: XCTestCase {
    private let validator = SelectionCorrectionValidator()

    func testRejectsFreeRephrasing() {
        let original = "Je souhaite recevoir le document complet avant demain matin."
        let candidate = "Merci de vite envoyer ce fichier."

        XCTAssertFalse(validator.accepts(original: original, candidate: candidate, dictionary: []))
    }

    func testPreservesDictionaryNumbersURLsLineBreaksAndEllipsisPolicy() {
        let original = "DictaMac traite 12 mots.\nVoir https://example.com/a."

        XCTAssertFalse(validator.accepts(
            original: original,
            candidate: "Dictamac traite douze mots. Voir https://example.com/b…",
            dictionary: ["DictaMac"]
        ))
    }
}

final class SelectionCorrectionDiffTests: XCTestCase {
    func testWordDiffProducesApplicableOriginalRanges() {
        let original = "Les enfant jouent ici."
        let corrected = "Les enfants jouent ici !"
        let changes = SelectionCorrectionDiff().changes(from: original, to: corrected)

        XCTAssertEqual(apply(changes, to: original), corrected)
    }

    private func apply(_ changes: [TextChange], to text: String) -> String {
        let result = NSMutableString(string: text)
        for change in changes.reversed() {
            result.replaceCharacters(in: change.range, with: change.replacement)
        }
        return result as String
    }
}

final class ConfiguredSelectionCorrectionServiceTests: XCTestCase {
    func testCorrectTextRemainsIdentical() async throws {
        let text = "Cette phrase est déjà parfaitement correcte."
        let service = makeService(local: CorrectionFakeGenerator(output: text))

        let correction = try await service.correct(text, dictionary: [])

        XCTAssertEqual(correction, .unchanged(text))
    }

    func testTenFrenchCorrections() async throws {
        let cases = frenchCases
        let generator = CorrectionFakeGenerator(outputs: Dictionary(uniqueKeysWithValues: cases))
        let service = makeService(local: generator)

        for (original, expected) in cases {
            let correction = try await service.correct(original, dictionary: [])
            XCTAssertEqual(correction.corrected, expected, "Échec pour: \(original)")
            XCTAssertFalse(correction.changes.isEmpty)
        }
    }

    func testRejectedCandidateBecomesNoSuggestion() async throws {
        let original = "Je souhaite recevoir le document complet avant demain matin."
        let generator = CorrectionFakeGenerator(output: "Merci de vite envoyer ce fichier.")
        let service = makeService(local: generator)
        let correction = try await service.correct(original, dictionary: [])

        XCTAssertEqual(correction, .unchanged(original))
    }

    func testDictionaryTermMustKeepExactSpelling() async throws {
        let original = "DictaMac corrige ce texte avec beaucoup de prudence."
        let generator = CorrectionFakeGenerator(output: "Dictamac corrige ce texte avec beaucoup de prudence.")
        let service = makeService(local: generator)
        let correction = try await service.correct(original, dictionary: ["DictaMac"])

        XCTAssertEqual(correction, .unchanged(original))
    }

    func testCloudRequiresExplicitPermission() async throws {
        let original = "Les enfant jouent dans le jardin."
        let local = CorrectionFakeGenerator(output: "Les enfants jouent dans le jardin.")
        let cloud = CorrectionFakeGenerator(output: "Les jeunes jouent dans le jardin.")
        let service = makeService(local: local, cloud: cloud, allowsCloud: false, engine: .cloud)

        let correction = try await service.correct(original, dictionary: [])
        let cloudCallCount = await cloud.callCount

        XCTAssertEqual(correction.corrected, "Les enfants jouent dans le jardin.")
        XCTAssertEqual(cloudCallCount, 0)
    }

    func testCloudPermissionUsesCloudEvenWhenCleanupEngineIsLocal() async throws {
        let original = "Les enfant jouent dans le jardin."
        let local = CorrectionFakeGenerator(output: "Les enfants jouent dans le jardin.")
        let cloud = CorrectionFakeGenerator(output: "Les enfants jouent dans le jardin.")
        let service = makeService(
            local: local,
            cloud: cloud,
            allowsCloud: true,
            engine: .local,
            apiKey: "test-key"
        )

        _ = try await service.correct(original, dictionary: [])

        let cloudCallCount = await cloud.callCount
        let localCallCount = await local.callCount
        let engine = await service.engineStatus()
        XCTAssertEqual(cloudCallCount, 1)
        XCTAssertEqual(localCallCount, 0)
        XCTAssertEqual(engine, .cloud)
    }

    func testPrepareTriggersLocalModelActivationWhenApprovedButNotReady() async {
        let activation = CorrectionActivationRecorder()
        let service = makeService(
            local: CorrectionFakeGenerator(output: "", isReady: false),
            activateLocalModel: { await activation.record() }
        )

        await service.prepare()

        let activationCount = await activation.count
        XCTAssertEqual(activationCount, 1)
    }

    func testSafeModeUsesExplicitLocalModelUnavailableMessage() async {
        let service = makeService(
            local: CorrectionFakeGenerator(output: "", isReady: true),
            safeMode: CorrectionSafeModeController(isEnabled: true)
        )

        let message = await service.engineUnavailableMessage()
        let engine = await service.engineStatus()

        XCTAssertEqual(message, SafeModeState.localCleanupUnavailableMessage)
        XCTAssertEqual(engine, .rulesOnly)
    }

    func testRulesOnlyOnlyNormalizesTypography() async throws {
        let original = "Les enfant joue dans le jardin , il va a Paris"
        let service = makeService(
            local: CorrectionFakeGenerator(output: "", isReady: false),
            safeMode: CorrectionSafeModeController(isEnabled: true)
        )

        let correction = try await service.correct(original, dictionary: [])

        XCTAssertEqual(correction.corrected, "Les enfant joue dans le jardin, il va a Paris")
        XCTAssertFalse(correction.changes.isEmpty)
    }

    func testCancellationPropagatesToGenerator() async throws {
        let generator = CorrectionFakeGenerator(delay: .seconds(10), output: "Texte corrigé assez long ici.")
        let service = makeService(local: generator)
        let task = Task { try await service.correct("Texte incorrect assez long ici.", dictionary: []) }
        try await Task.sleep(for: .milliseconds(20))

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Une annulation était attendue")
        } catch is CancellationError {
            XCTAssertTrue(true)
        }
    }

    func testGenerationTimesOut() async throws {
        let generator = CorrectionFakeGenerator(delay: .seconds(1), output: "Texte corrigé assez long ici.")
        let service = makeService(local: generator, timeout: .milliseconds(10))

        do {
            _ = try await service.correct("Texte incorrect assez long ici.", dictionary: [])
            XCTFail("Un délai dépassé était attendu")
        } catch SelectionCorrectionError.timeout {
            XCTAssertTrue(true)
        }
    }

    private func makeService(
        local: CorrectionFakeGenerator,
        cloud: CorrectionFakeGenerator = CorrectionFakeGenerator(output: "cloud"),
        allowsCloud: Bool = false,
        engine: TextCleanupEngine = .local,
        apiKey: String? = nil,
        activateLocalModel: @escaping @Sendable () async -> Void = {},
        safeMode: any SafeModeControlling = CorrectionSafeModeController(isEnabled: false),
        timeout: Duration = .seconds(6)
    ) -> ConfiguredSelectionCorrectionService {
        ConfiguredSelectionCorrectionService(
            selectionSettings: CorrectionFakeSelectionSettings(allowsCloud: allowsCloud),
            cleanupSettings: CorrectionFakeCleanupSettings(configuredEngine: engine),
            localGenerator: local,
            cloudGenerator: cloud,
            apiKeyProvider: { apiKey },
            activateLocalModel: activateLocalModel,
            safeMode: safeMode,
            timeout: timeout
        )
    }

    private var frenchCases: [(String, String)] {
        [
            ("Les enfant jouent dans le jardin.", "Les enfants jouent dans le jardin."),
            ("Nous mangeons hier avec nos amis.", "Nous mangions hier avec nos amis."),
            ("Il a donné ce livre a Marie.", "Il a donné ce livre à Marie."),
            ("Il range ces affaires dans son placard.", "Il range ses affaires dans son placard."),
            ("Elle est parti tôt ce matin.", "Elle est partie tôt ce matin."),
            ("Bonjour comment allez-vous ce matin ?", "Bonjour, comment allez-vous ce matin ?"),
            ("bonjour tout le monde est déjà là.", "Bonjour tout le monde est déjà là."),
            ("Est-ce que tout va bien?", "Est-ce que tout va bien\u{202F}?"),
            ("Attention tout le monde arrive!", "Attention tout le monde arrive\u{202F}!"),
            ("Note ceci: oui; vraiment.", "Note ceci\u{202F}: oui\u{202F}; vraiment.")
        ]
    }
}

private final class CorrectionSafeModeController: SafeModeControlling, @unchecked Sendable {
    private let enabled: Bool

    init(isEnabled: Bool) {
        enabled = isEnabled
    }

    var isEnabled: Bool { enabled }
    func setEnabled(_ value: Bool) {}
}

private actor CorrectionActivationRecorder {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor CorrectionFakeGenerator: LocalTextGenerating {
    private let outputs: [String: String]
    private let defaultOutput: String
    private let delay: Duration?
    private(set) var callCount = 0
    let isReady: Bool

    init(output: String, isReady: Bool = true) {
        outputs = [:]
        defaultOutput = output
        delay = nil
        self.isReady = isReady
    }

    init(outputs: [String: String], isReady: Bool = true) {
        self.outputs = outputs
        defaultOutput = ""
        delay = nil
        self.isReady = isReady
    }

    init(delay: Duration, output: String) {
        outputs = [:]
        defaultOutput = output
        self.delay = delay
        isReady = true
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        callCount += 1
        if let delay { try await ContinuousClock().sleep(for: delay) }
        return outputs[text] ?? defaultOutput
    }
}

private struct CorrectionFakeSelectionSettings: SelectionCorrectionSettings {
    let isEnabled = true
    let isClipboardFallbackEnabled = false
    let allowsCloud: Bool
    let excludedBundleIDs: Set<String> = []
}

private struct CorrectionFakeCleanupSettings: TextCleanupSettings {
    let configuredEngine: TextCleanupEngine
    let isEnabled = true
    let configuredModel = "test"
    let configuredLocalModel = "test"
    let cleanupStyle = CleanupStyle.correction
    let removeIsolatedGenre = false
    let localTimeout: TimeInterval = 6
    let cloudTimeout: TimeInterval = 6
    let localDownloadApproved = true
}
