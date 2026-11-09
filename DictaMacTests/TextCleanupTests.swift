import XCTest
@testable import DictaMac

final class TextCleanupPostProcessorTests: XCTestCase {
    func testLengthGuardRejectsEmptyTooLongAndTooShort() {
        let raw = "Ceci est une phrase dictée suffisamment longue."
        XCTAssertEqual(TextCleanupPostProcessor.process(raw: raw, candidate: ""), .fallback(reason: "empty output"))
        XCTAssertEqual(TextCleanupPostProcessor.process(raw: raw, candidate: String(repeating: "x", count: raw.count * 2)), .fallback(reason: "length ratio"))
        XCTAssertEqual(TextCleanupPostProcessor.process(raw: raw, candidate: "Court"), .fallback(reason: "length ratio"))
    }

    func testLengthGuardAcceptsShortInputContraction() {
        XCTAssertEqual(TextCleanupPostProcessor.process(raw: "euh oui oui", candidate: "Oui."), .cleaned("Oui."))
    }

    func testDictationTagsAreRemovedCaseInsensitively() {
        XCTAssertEqual(TextCleanupPostProcessor.removingDictationTags(from: "<DICTATION>Bonjour.</dictation>"), "Bonjour.")
    }

    func testFourWordThreshold() {
        XCTAssertFalse(TextCleanupPostProcessor.shouldClean("un deux trois"))
        XCTAssertTrue(TextCleanupPostProcessor.shouldClean("un deux trois quatre"))
    }
}

final class TextCleanupPreferencesTests: XCTestCase {
    func testLegacyEnabledMigratesToCloudAndPreservesOtherValues() throws {
        let name = "TextCleanupPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: TextCleanupPreferences.enabledKey)
        defaults.set("sentinel", forKey: "unrelated.key")
        TextCleanupPreferences.migrate(in: defaults)
        XCTAssertEqual(defaults.string(forKey: TextCleanupPreferences.engineKey), TextCleanupEngine.cloud.rawValue)
        XCTAssertEqual(defaults.string(forKey: "unrelated.key"), "sentinel")
    }

    func testLegacyDisabledMigratesToDisabledAndNewInstallToFastRules() throws {
        let disabledName = "TextCleanupPreferencesTests-\(UUID().uuidString)"
        let disabled = try XCTUnwrap(UserDefaults(suiteName: disabledName))
        defer { disabled.removePersistentDomain(forName: disabledName) }
        disabled.set(false, forKey: TextCleanupPreferences.enabledKey)
        TextCleanupPreferences.migrate(in: disabled)
        XCTAssertEqual(disabled.string(forKey: TextCleanupPreferences.engineKey), TextCleanupEngine.disabled.rawValue)

        let freshName = "TextCleanupPreferencesTests-\(UUID().uuidString)"
        let fresh = try XCTUnwrap(UserDefaults(suiteName: freshName))
        defer { fresh.removePersistentDomain(forName: freshName) }
        TextCleanupPreferences.migrate(in: fresh)
        XCTAssertEqual(fresh.string(forKey: TextCleanupPreferences.engineKey), TextCleanupEngine.fast.rawValue)
    }
}

final class FastRulesTextCleanupServiceTests: XCTestCase {
    private func clean(_ input: String, genre: Bool = true) -> String {
        FastRulesTextCleanupService.cleanup(input, removeIsolatedGenre: genre)
    }

    func testRemovesFrenchHesitations() { XCTAssertEqual(clean("euh heu hum hmm bonjour"), "Bonjour.") }
    func testRemovesEnglishStyleHmm() { XCTAssertEqual(clean("Hmm I think so"), "I think so.") }
    func testRemovesBahAtBeginning() { XCTAssertEqual(clean("bah je viens"), "Je viens.") }
    func testRemovesBenAfterSegmentBoundary() { XCTAssertEqual(clean("D'accord. ben je viens"), "D'accord. je viens.") }
    func testRemovesBahAfterLineBreak() { XCTAssertEqual(clean("D'accord\nbah je viens"), "D'accord je viens.") }
    func testKeepsBahInsideWord() { XCTAssertEqual(clean("Le bahut est fermé"), "Le bahut est fermé.") }
    func testKeepsEuhInsideHeureux() { XCTAssertEqual(clean("je suis heureux"), "Je suis heureux.") }
    func testKeepsBenWhenNotAtSegmentStart() { XCTAssertEqual(clean("Il est ben content"), "Il est ben content.") }
    func testRemovesIsolatedGenreByDefault() { XCTAssertEqual(clean("C'est genre vraiment bien"), "C'est vraiment bien.") }
    func testCanKeepIsolatedGenre() { XCTAssertEqual(clean("c'est genre bien", genre: false), "C'est genre bien.") }
    func testKeepsGenreInsideWord() { XCTAssertEqual(clean("Le mot intergenre existe"), "Le mot intergenre existe.") }
    func testRemovesImmediateWordRepeat() { XCTAssertEqual(clean("je je veux venir"), "Je veux venir.") }
    func testRemovesApostropheWordRepeat() { XCTAssertEqual(clean("c'est c'est parfait"), "C'est parfait.") }
    func testKeepsNonImmediateRepeat() { XCTAssertEqual(clean("très bien très vite"), "Très bien très vite.") }
    func testNormalizesWhitespaceAndPunctuationSpacing() { XCTAssertEqual(clean("  bonjour   ,  comment ça va ? "), "Bonjour, comment ça va?") }
    func testKeepsExistingFinalPunctuation() { XCTAssertEqual(clean("bonjour !"), "Bonjour!") }
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

    func test401And500Fallback() async throws {
        for status in [401, 500] {
            MockURLProtocol.setResponse(.http(status: status, data: Data()))
            let result = try await service().cleanup(raw)
            XCTAssertEqual(result, raw)
        }
    }

    func testTimeoutFallback() async throws {
        MockURLProtocol.setResponse(.error(URLError(.timedOut)))
        let result = try await service().cleanup(raw)
        XCTAssertEqual(result, raw)
    }

    func testInvalidJSONFallback() async throws {
        MockURLProtocol.setResponse(.http(status: 200, data: Data("not json".utf8)))
        let result = try await service().cleanup(raw)
        XCTAssertEqual(result, raw)
    }

    func testTooLongOutputFallsBack() async throws {
        MockURLProtocol.setResponse(.http(status: 200, data: try responseData(String(repeating: "trop long ", count: 20))))
        let result = try await service().cleanup(raw)
        XCTAssertEqual(result, raw)
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
    var isReady: Bool { true }

    init(_ behavior: Behavior) { self.behavior = behavior }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        switch behavior {
        case .output(let value): return value
        case .delayed(let duration, let value):
            try await ContinuousClock().sleep(for: duration)
            return value
        }
    }
}

final class LocalTextCleanupServiceTests: XCTestCase {
    private let raw = "Euh je je vais venir demain matin avec le train qui part de la gare centrale."

    func testTimeoutFallsBackWithoutModel() async throws {
        let generator = FakeLocalGenerator(.delayed(.seconds(1), "Je vais venir demain matin."))
        let service = LocalTextCleanupService(generator: generator, timeout: .milliseconds(10))
        let result = try await service.cleanup(raw)
        XCTAssertEqual(result, raw)
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

    func testRejectedOutputFallsBack() async throws {
        let service = LocalTextCleanupService(
            generator: FakeLocalGenerator(.output(String(repeating: "hallucination ", count: 20)))
        )
        let result = try await service.cleanup(raw)
        XCTAssertEqual(result, raw)
    }
}
