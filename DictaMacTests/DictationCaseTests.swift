import Foundation
import OSLog
import XCTest
@testable import DictaMac

final class DictationCaseTests: XCTestCase {
    private struct DictationCase: Decodable {
        let id: String
        let raw: String
        let expected: String
        let tags: [String]
        let knownFailure: Bool?
        let requiresAI: Bool?

        var isKnownFailure: Bool { knownFailure == true }
    }

    func testReferenceCases() async throws {
        let cases = try loadCases()
        var passedCount = 0
        var knownFailureCount = 0

        for dictationCase in cases {
            let corrected = DictionaryCorrector.correct(
                dictationCase.raw,
                entries: DictionaryEntry.defaults
            )
            let actual = try await cleanup(corrected, for: dictationCase)
            if dictationCase.isKnownFailure {
                knownFailureCount += 1
            } else if actual == dictationCase.expected {
                passedCount += 1
            } else {
                XCTFail("Reference case failed: \(dictationCase.id)")
            }
        }

        logSummary(passed: passedCount, knownFailures: knownFailureCount)
    }

    private func cleanup(_ text: String, for dictationCase: DictationCase) async throws -> String {
        guard dictationCase.requiresAI == true else {
            return FastRulesTextCleanupService.cleanup(text)
        }
        let generator = ReferenceCaseGenerator(output: dictationCase.expected)
        let service = LocalTextCleanupService(
            generator: generator,
            settings: ReferenceCaseCleanupSettings(),
            timeout: .seconds(1)
        )
        return try await service.cleanup(
            text,
            dictionary: DictionaryEntry.defaults.map(\.canonical)
        )
    }

    func testReferenceCorpusMetadata() throws {
        let cases = try loadCases()
        let identifiers = Set(cases.map(\.id))

        XCTAssertGreaterThanOrEqual(cases.count, 40)
        XCTAssertEqual(identifiers.count, cases.count, "Reference case identifiers must be unique")
        XCTAssertTrue(cases.allSatisfy { !$0.tags.isEmpty }, "Every reference case must have tags")
    }

    private func loadCases() throws -> [DictationCase] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "dictation-cases", withExtension: "json"))
        return try JSONDecoder().decode([DictationCase].self, from: Data(contentsOf: url))
    }

    private func logSummary(passed: Int, knownFailures: Int) {
        let logger = Logger(subsystem: "com.dictamac.tests", category: "DictationCases")
        logger.info("Reference cases passed=\(passed, privacy: .public) known_failures=\(knownFailures, privacy: .public)")
    }
}

private actor ReferenceCaseGenerator: LocalTextGenerating {
    let output: String
    var isReady: Bool { true }

    init(output: String) {
        self.output = output
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        output
    }
}

private struct ReferenceCaseCleanupSettings: TextCleanupSettings {
    let configuredEngine = TextCleanupEngine.local
    let isEnabled = true
    let configuredModel = ""
    let configuredLocalModel = ""
    let cleanupStyle = CleanupStyle.polished
    let removeIsolatedGenre = true
    let localTimeout: TimeInterval = 8
    let cloudTimeout: TimeInterval = 8
    let localDownloadApproved = true
}
