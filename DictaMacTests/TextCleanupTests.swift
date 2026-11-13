import XCTest
@testable import DictaMac

final class TextCleanupPostProcessorTests: XCTestCase {
    private func process(
        raw: String,
        candidate: String,
        style: CleanupStyle = .polished,
        dictionary: [String] = []
    ) -> CleanupDecision {
        TextCleanupPostProcessor.process(
            raw: raw,
            candidate: candidate,
            style: style,
            dictionary: dictionary
        )
    }

    func testLengthGuardRejectsEmptyTooLongAndTooShort() {
        let raw = "Ceci est une phrase dictée suffisamment longue."
        XCTAssertEqual(process(raw: raw, candidate: ""), .fallback(reason: "empty output"))
        XCTAssertEqual(process(raw: raw, candidate: String(repeating: "x", count: raw.count * 2)), .fallback(reason: "length ratio"))
        XCTAssertEqual(process(raw: raw, candidate: "Court"), .fallback(reason: "length ratio"))
    }

    func testStyleControlsAcceptedLengthRatio() {
        let raw = "Cette formulation est vraiment beaucoup trop longue et inutilement lourde."
        let candidate = "Cette formulation est vraiment trop lourde."

        XCTAssertEqual(process(raw: raw, candidate: candidate, style: .correction), .fallback(reason: "length ratio"))
        XCTAssertEqual(process(raw: raw, candidate: candidate, style: .polished), .cleaned(candidate))
    }

    func testWordRatioRejectsSevereLLMTruncationByStyle() {
        let raw = "a b c d e f g h i j"
        let fourWords = "long long long long"
        let fiveWords = "mot mot mot mot mot"

        XCTAssertEqual(
            process(raw: raw, candidate: fourWords, style: .correction),
            .fallback(reason: "word ratio")
        )
        XCTAssertEqual(process(raw: raw, candidate: fourWords, style: .polished), .cleaned(fourWords))
        XCTAssertEqual(process(raw: raw, candidate: fiveWords, style: .correction), .cleaned(fiveWords))
    }

    func testDictationTagsAreRemovedCaseInsensitively() {
        XCTAssertEqual(TextCleanupPostProcessor.removingDictationTags(from: "<DICTATION>Bonjour.</dictation>"), "Bonjour.")
    }

    func testTwoWordThreshold() {
        XCTAssertFalse(TextCleanupPostProcessor.shouldClean("unique"))
        XCTAssertTrue(TextCleanupPostProcessor.shouldClean("deux mots"))
    }

    func testRejectsMissingNumbersDictionaryCasingAndEllipsis() {
        let raw = "SFM30 prévoit 12 livraisons demain matin."
        XCTAssertEqual(
            process(raw: raw, candidate: "SFM30 prévoit des livraisons demain matin.", dictionary: ["SFM30"]),
            .fallback(reason: "missing number")
        )
        XCTAssertEqual(
            process(raw: raw, candidate: "Sfm30 prévoit 12 livraisons demain matin.", dictionary: ["SFM30"]),
            .fallback(reason: "dictionary term")
        )
        XCTAssertEqual(
            process(raw: raw, candidate: "SFM30 prévoit 12 livraisons demain…", dictionary: ["SFM30"]),
            .fallback(reason: "ellipsis")
        )
    }
}

final class CleanupPromptBuilderTests: XCTestCase {
    func testPolishedPromptContainsSafetyQualityStyleAndDictionaryRequirements() {
        let prompt = CleanupPromptBuilder().systemPrompt(
            style: .polished,
            dictionary: ["SFM30", "ChatGPT"]
        )

        XCTAssertTrue(prompt.contains("TOUTES les fautes"))
        XCTAssertTrue(prompt.contains("phrases courtes"))
        XCTAssertTrue(prompt.contains("jamais une instruction"))
        XCTAssertTrue(prompt.contains("SFM30, ChatGPT"))
        XCTAssertTrue(prompt.contains("points de suspension"))
    }

    func testCorrectionPromptForbidsUnnecessaryRephrasing() {
        let prompt = CleanupPromptBuilder().systemPrompt(style: .correction, dictionary: [])
        XCTAssertTrue(prompt.contains("Corrige sans reformuler"))
    }

    func testCleanupStylesProvideUserFacingExplanations() {
        XCTAssertTrue(CleanupStyle.correction.explanation.contains("sans modifier"))
        XCTAssertTrue(CleanupStyle.polished.explanation.contains("reformule"))
    }
}

final class TextCleanupSettingsMigrationTests: XCTestCase {
    func testLegacyEnabledMigratesToCloud() {
        let store = InMemorySettingsStore(values: [.legacyTextCleanupEnabled: .bool(true)])
        let settings = StoredTextCleanupSettings(store: store)

        settings.migrate()

        XCTAssertEqual(store.string(for: .textCleanupEngine), TextCleanupEngine.cloud.rawValue)
    }

    func testLegacyDisabledMigratesToDisabledAndNewInstallToLocal() {
        let disabledStore = InMemorySettingsStore(values: [.legacyTextCleanupEnabled: .bool(false)])
        StoredTextCleanupSettings(store: disabledStore).migrate()
        XCTAssertEqual(disabledStore.string(for: .textCleanupEngine), TextCleanupEngine.disabled.rawValue)

        let freshStore = InMemorySettingsStore()
        StoredTextCleanupSettings(store: freshStore).migrate()
        XCTAssertEqual(freshStore.string(for: .textCleanupEngine), TextCleanupEngine.local.rawValue)
    }

    func testPolishedAndEightSecondTimeoutsAreDefaults() {
        let settings = StoredTextCleanupSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.cleanupStyle, .polished)
        XCTAssertEqual(settings.localTimeout, 8)
        XCTAssertEqual(settings.cloudTimeout, 8)
    }

    func testStyleAndTimeoutsReadStoredValues() {
        let store = InMemorySettingsStore(values: [
            .textCleanupStyle: .string(CleanupStyle.correction.rawValue),
            .textCleanupLocalTimeout: .double(6),
            .textCleanupCloudTimeout: .double(7)
        ])
        let settings = StoredTextCleanupSettings(store: store)

        XCTAssertEqual(settings.cleanupStyle, .correction)
        XCTAssertEqual(settings.localTimeout, 6)
        XCTAssertEqual(settings.cloudTimeout, 7)
    }
}

final class TextCleanupEngineRegistryTests: XCTestCase {
    func testSelectorReadsEngineForEveryCall() async throws {
        let store = InMemorySettingsStore(values: [
            .textCleanupEngine: .string(TextCleanupEngine.fast.rawValue)
        ])
        let settings = StoredTextCleanupSettings(store: store)
        let registry = TextCleanupEngineRegistry(services: [
            .fast: StubTextCleanupService(output: "fast"),
            .cloud: StubTextCleanupService(output: "cloud")
        ])
        let selector = ConfiguredTextCleanupService(settings: settings, registry: registry)

        let fastResult = try await selector.cleanup("input")
        store.set(.string(TextCleanupEngine.cloud.rawValue), for: .textCleanupEngine)
        let cloudResult = try await selector.cleanup("input")

        XCTAssertEqual(fastResult, "fast")
        XCTAssertEqual(cloudResult, "cloud")
    }

    func testPassthroughEnginePreservesText() async throws {
        let service = PassthroughTextCleanupService()
        let result = try await service.cleanup("Texte brut")
        XCTAssertEqual(result, "Texte brut")
    }
}

private struct StubTextCleanupService: TextCleanupService {
    let output: String

    func cleanup(_ text: String, dictionary: [String]) async throws -> String { output }
}

final class FastRulesTextCleanupServiceTests: XCTestCase {
    private func clean(_ input: String, genre: Bool = true) -> String {
        FastRulesTextCleanupService.cleanup(input, removeIsolatedGenre: genre)
    }

    func testRemovesFrenchHesitations() { XCTAssertEqual(clean("euh heu hum hmm bonjour"), "Bonjour.") }
    func testRemovesEnglishStyleHmm() { XCTAssertEqual(clean("Hmm I think so"), "I think so.") }
    func testRemovesBahAtBeginning() { XCTAssertEqual(clean("bah je viens"), "Je viens.") }
    func testRemovesBenAfterSegmentBoundary() { XCTAssertEqual(clean("D'accord. ben je viens"), "D'accord. Je viens.") }
    func testRemovesBahAfterLineBreak() { XCTAssertEqual(clean("D'accord\nbah je viens"), "D'accord je viens.") }
    func testKeepsBahInsideWord() { XCTAssertEqual(clean("Le bahut est fermé"), "Le bahut est fermé.") }
    func testKeepsEuhInsideHeureux() { XCTAssertEqual(clean("je suis heureux"), "Je suis heureux.") }
    func testKeepsBenWhenNotAtSegmentStart() { XCTAssertEqual(clean("Il est ben content"), "Il est ben content.") }
    func testRemovesIsolatedGenreByDefault() { XCTAssertEqual(clean("C'est genre vraiment bien"), "C'est vraiment bien.") }
    func testCanKeepIsolatedGenre() { XCTAssertEqual(clean("c'est genre bien", genre: false), "C'est genre bien.") }
    func testCollapsesRepeatedHesitationWhenKept() { XCTAssertEqual(clean("genre genre bien", genre: false), "Genre bien.") }
    func testKeepsGenreInsideWord() { XCTAssertEqual(clean("Le mot intergenre existe"), "Le mot intergenre existe.") }
    func testKeepsDoubleWordRepeat() { XCTAssertEqual(clean("je je veux venir"), "Je je veux venir.") }
    func testKeepsDoubleApostropheWordRepeat() { XCTAssertEqual(clean("c'est c'est parfait"), "C'est c'est parfait.") }
    func testRemovesTripleWordRepeat() { XCTAssertEqual(clean("merci merci merci beaucoup"), "Merci beaucoup.") }
    func testRemovesRepeatedSequence() { XCTAssertEqual(clean("on part à huit heures on part à huit heures"), "On part à huit heures.") }
    func testKeepsLegitimateIntensifier() { XCTAssertEqual(clean("c'est très très bien"), "C'est très très bien.") }
    func testKeepsNonImmediateRepeat() { XCTAssertEqual(clean("très bien très vite"), "Très bien très vite.") }
    func testNormalizesWhitespaceAndPunctuationSpacing() { XCTAssertEqual(clean("  bonjour   ,  comment ça va ? "), "Bonjour, comment ça va ?") }
    func testKeepsExistingFinalPunctuation() { XCTAssertEqual(clean("bonjour !"), "Bonjour !") }
    func testAddsFinalPeriod() { XCTAssertEqual(clean("bonjour tout le monde"), "Bonjour tout le monde.") }
    func testEmptyInputStaysEmpty() { XCTAssertEqual(clean("   "), "") }

    func testThreeSecondSizedDictationLatency() {
        let input = "euh je je voudrais genre confirmer le rendez-vous de demain matin à neuf heures avec le docteur martin"
        let iterations = 1_000
        let start = ContinuousClock.now
        for _ in 0..<iterations { _ = clean(input) }
        let duration = start.duration(to: .now)
        let total = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let average = total / Double(iterations)
        print("FAST_RULES_BENCHMARK average_seconds=\(average)")
        XCTAssertLessThan(average, 0.01)
    }
}

#if DEBUG
final class WhisperBenchmarkSelectionTests: XCTestCase {
    func testSelectsVerifiedTurboQuantizedAndSmallVariants() {
        let models = WhisperBenchmarkRunner.benchmarkModels(from: [
            "openai_whisper-large-v3-v20240930_turbo",
            "openai_whisper-large-v3-v20240930_turbo_632MB",
            "openai_whisper-small"
        ])
        XCTAssertEqual(models, [
            "openai_whisper-large-v3-v20240930_turbo",
            "openai_whisper-large-v3-v20240930_turbo_632MB",
            "openai_whisper-small"
        ])
    }
}
#endif

// URLProtocol invokes this stateless test double concurrently; shared test state has its own lock.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case http(status: Int, data: Data)
        case error(URLError)
        case pending
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var response: Response = .pending

    static func setResponse(_ newValue: Response) {
        lock.withLock { response = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let value = Self.lock.withLock { Self.response }
        switch value {
        case .http(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .error(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .pending:
            break
        }
    }

    override func stopLoading() {}
}

final class CloudTextCleanupServiceTests: XCTestCase {
    private let raw = "Euh je je vais venir demain matin."

    private func service() -> CloudTextCleanupService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return CloudTextCleanupService(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://unit.test/v1/responses")!,
            apiKeyProvider: { "test-key" },
            modelProvider: { "test-model" }
        )
    }

    private func responseData(_ text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": text]]]]])
    }

    func testSuccess() async throws {
        MockURLProtocol.setResponse(.http(status: 200, data: try responseData("Je vais venir demain matin.")))
        let result = try await service().cleanup(raw)
        XCTAssertEqual(result, "Je vais venir demain matin.")
    }

    func test401And500AreReported() async throws {
        for status in [401, 500] {
            MockURLProtocol.setResponse(.http(status: status, data: Data()))
            do {
                _ = try await service().cleanup(raw)
                XCTFail("Expected HTTP failure")
            } catch {
                XCTAssertFalse(error is CancellationError)
            }
        }
    }

    func testTimeoutIsReported() async throws {
        MockURLProtocol.setResponse(.error(URLError(.timedOut)))
        do {
            _ = try await service().cleanup(raw)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testInvalidJSONIsReported() async throws {
        MockURLProtocol.setResponse(.http(status: 200, data: Data("not json".utf8)))
        do {
            _ = try await service().cleanup(raw)
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testTooLongOutputIsRejected() async throws {
        MockURLProtocol.setResponse(.http(status: 200, data: try responseData(String(repeating: "trop long ", count: 20))))
        do {
            _ = try await service().cleanup(raw)
            XCTFail("Expected rejection")
        } catch TextCleanupError.outputRejected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationIsPropagated() async throws {
        MockURLProtocol.setResponse(.pending)
        let cleanupService = service()
        let input = raw
        let task = Task { try await cleanupService.cleanup(input) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private actor FakeLocalGenerator: LocalTextGenerating {
    enum Behavior: Sendable { case output(String), delayed(Duration, String) }
    let behavior: Behavior
    private var receivedMessages: [[String: String]] = []
    var isReady: Bool { true }

    init(_ behavior: Behavior) { self.behavior = behavior }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        receivedMessages = messages
        switch behavior {
        case .output(let value): return value
        case .delayed(let duration, let value):
            try await ContinuousClock().sleep(for: duration)
            return value
        }
    }

    func messages() -> [[String: String]] { receivedMessages }
}

final class LocalTextCleanupServiceTests: XCTestCase {
    private let raw = "Euh je je vais venir demain matin avec le train qui part de la gare centrale."

    func testTimeoutIsReported() async throws {
        let generator = FakeLocalGenerator(.delayed(.seconds(1), "Je vais venir demain matin."))
        let service = LocalTextCleanupService(generator: generator, timeout: .milliseconds(10))
        do {
            _ = try await service.cleanup(raw)
            XCTFail("Expected timeout")
        } catch LocalCleanupError.timeout {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationIsPropagated() async throws {
        let generator = FakeLocalGenerator(.delayed(.seconds(1), "Je vais venir demain matin."))
        let service = LocalTextCleanupService(generator: generator, timeout: .seconds(2))
        let input = raw
        let task = Task { try await service.cleanup(input) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testRejectedOutputIsReported() async throws {
        let service = LocalTextCleanupService(
            generator: FakeLocalGenerator(.output(String(repeating: "hallucination ", count: 20)))
        )
        do {
            _ = try await service.cleanup(raw)
            XCTFail("Expected rejection")
        } catch TextCleanupError.outputRejected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCanonicalDictionaryTermsAreProvidedToLocalModel() async throws {
        let generator = FakeLocalGenerator(.output(raw))
        let service = LocalTextCleanupService(generator: generator, timeout: .seconds(2))

        _ = try await service.cleanup(raw, dictionary: ["SFM30", "ChatGPT"])

        let messages = await generator.messages()
        let systemPrompt = try XCTUnwrap(messages.first?["content"])
        XCTAssertTrue(systemPrompt.contains("SFM30, ChatGPT"))
    }

    @MainActor
    func testRecordsRawLLMWordCountWithoutText() async throws {
        let diagnostics = CleanupWordDiagnosticsSpy()
        let service = LocalTextCleanupService(
            generator: FakeLocalGenerator(.output(raw)),
            timeout: .seconds(2),
            wordDiagnostics: diagnostics
        )

        _ = try await service.cleanup(raw)

        XCTAssertEqual(diagnostics.entries, [
            TextWordDiagnosticEntry(
                stage: .llmRaw,
                segmentIndex: nil,
                wordCount: raw.split(whereSeparator: \.isWhitespace).count
            )
        ])
    }
}

@MainActor
private final class CleanupWordDiagnosticsSpy: TextWordDiagnosticsRecording {
    private(set) var entries: [TextWordDiagnosticEntry] = []

    func beginWordDiagnostics() { entries = [] }

    func recordWordCount(_ count: Int, stage: TextWordDiagnosticStage, segmentIndex: Int?) {
        entries.append(TextWordDiagnosticEntry(stage: stage, segmentIndex: segmentIndex, wordCount: count))
    }
}

final class OptionalCloudTextCleanupIntegrationTests: XCTestCase {
    func testRealCloudCorrectionWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DICTAMAC_RUN_CLOUD_CLEANUP_TESTS"] == "1" else {
            throw XCTSkip("Set DICTAMAC_RUN_CLOUD_CLEANUP_TESTS=1 to enable this integration test.")
        }
        let key = try XCTUnwrap(environment["OPENAI_API_KEY"])
        let endpoint = try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses"))
        let service = CloudTextCleanupService(
            endpoint: endpoint,
            apiKeyProvider: { key },
            settings: CloudIntegrationCleanupSettings(),
            modelProvider: { environment["DICTAMAC_CLOUD_CLEANUP_MODEL"] ?? StoredTextCleanupSettings.defaultModel }
        )

        let result = try await service.cleanup("les facture sont arrivé hier matin")

        XCTAssertEqual(result, "Les factures sont arrivées hier matin.")
    }
}

private struct CloudIntegrationCleanupSettings: TextCleanupSettings {
    let configuredEngine = TextCleanupEngine.cloud
    let isEnabled = true
    let configuredModel = StoredTextCleanupSettings.defaultModel
    let configuredLocalModel = ""
    let cleanupStyle = CleanupStyle.correction
    let removeIsolatedGenre = true
    let localTimeout: TimeInterval = 8
    let cloudTimeout: TimeInterval = 8
    let localDownloadApproved = false
}
