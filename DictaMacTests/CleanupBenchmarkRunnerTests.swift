import XCTest
@testable import DictaMac

#if DEBUG
final class CleanupBenchmarkRunnerTests: XCTestCase {
    func testFixtureContainsThirtyUniqueCasesAndRequiredCoverage() throws {
        let cases = try Self.loadCases()
        let requiredTags: Set<String> = [
            "hésitation", "auto-correction", "énumération", "e-mail",
            "message-court", "termes-techniques", "nombres", "phrase-longue"
        ]

        XCTAssertEqual(cases.count, 30)
        XCTAssertEqual(Set(cases.map(\.id)).count, 30)
        XCTAssertTrue(requiredTags.isSubset(of: Set(cases.flatMap(\.tags))))
        XCTAssertTrue(cases.allSatisfy { !$0.raw.isEmpty && !$0.expected.isEmpty })
    }

    func testNormalizedEditDistanceMedianAndPercentile95() {
        XCTAssertEqual(CleanupBenchmarkMetrics.normalizedEditDistance("chat", "chat"), 0)
        XCTAssertEqual(CleanupBenchmarkMetrics.normalizedEditDistance("chat", "chut"), 0.25)
        XCTAssertEqual(CleanupBenchmarkMetrics.normalizedEditDistance("", "abc"), 1)
        XCTAssertEqual(CleanupBenchmarkMetrics.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(CleanupBenchmarkMetrics.percentile95(Array(1...20).map(Double.init)), 19)
    }

    func testRunnerMeasuresDownloadedModelAndSkipsMissingModel() async {
        let cases = [
            makeCase(id: "accepted", raw: "texte propre", expected: "Texte propre."),
            makeCase(id: "rejected", raw: "autre texte brut", expected: "Texte attendu.")
        ]
        let generator = CleanupBenchmarkGeneratorStub(
            downloadedModels: ["local/model"],
            outputs: ["texte propre": "Texte propre.", "autre texte brut": ""]
        )
        let runner = CleanupBenchmarkRunner(generator: generator)

        let results = await runner.run(models: ["local/model", "missing/model"], cases: cases)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].modelID, "local/model")
        XCTAssertEqual(results[0].caseCount, 2)
        XCTAssertEqual(results[0].validatorRejectionRate, 0.5)
        XCTAssertEqual(results[0].normalizedEditDistance, 0.5)
        XCTAssertEqual(results[0].outcome, .completed)
        XCTAssertEqual(results[1].outcome, .skipped("modèle non téléchargé — ignoré sans accès réseau"))
        let loadedModels = await generator.loadedModels
        XCTAssertEqual(loadedModels, ["local/model"])
    }

    func testConfiguredModelsAreCustomizableAndDeduplicated() {
        XCTAssertEqual(
            CleanupBenchmarkRunner.configuredModels(environment: [
                "DICTAMAC_CLEANUP_BENCHMARK_MODELS": "org/model-a, org/model-b,org/model-a"
            ]),
            ["org/model-a", "org/model-b"]
        )
        XCTAssertEqual(CleanupBenchmarkRunner.configuredModels(environment: [:]), CleanupBenchmarkRunner.defaultModels)
    }

    func testMarkdownContainsOneRowPerConfiguredModel() {
        let completed = CleanupBenchmarkResult(
            modelID: "org/model-a",
            caseCount: 30,
            medianLatency: 1.25,
            percentile95Latency: 2.5,
            validatorRejectionRate: 0.1,
            normalizedEditDistance: 0.125,
            outcome: .completed
        )
        let skipped = CleanupBenchmarkResult.skipped(modelID: "org/model-b", reason: "absent")

        let report = CleanupBenchmarkMarkdownReport.render(
            results: [completed, skipped],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.contains("| org/model-a | 30 | 1.250 s | 2.500 s | 10.0 % | 0.1250 | Terminé |"))
        XCTAssertTrue(report.contains("| org/model-b | 0 | — | — | — | — | Ignoré : absent |"))
    }

    private func makeCase(id: String, raw: String, expected: String) -> CleanupBenchmarkCase {
        CleanupBenchmarkCase(
            id: id,
            raw: raw,
            expected: expected,
            usage: "other",
            tags: ["test"],
            dictionary: []
        )
    }

    fileprivate static func loadCases() throws -> [CleanupBenchmarkCase] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "cleanup-benchmark-cases",
            withExtension: "json"
        ))
        return try JSONDecoder().decode([CleanupBenchmarkCase].self, from: Data(contentsOf: url))
    }
}

final class CleanupBenchmarkIntegrationTests: XCTestCase {
    func testBenchmarkDownloadedModelsAndWriteMarkdown() async throws {
        guard ProcessInfo.processInfo.environment["DICTAMAC_RUN_CLEANUP_BENCHMARK"] == "1" else {
            throw XCTSkip("Benchmark lourd désactivé ; définir DICTAMAC_RUN_CLEANUP_BENCHMARK=1 pour l’exécuter.")
        }
        let environment = ProcessInfo.processInfo.environment
        let models = CleanupBenchmarkRunner.configuredModels(environment: environment)
        let cases = try CleanupBenchmarkRunnerTests.loadCases()
        let runner = CleanupBenchmarkRunner(generator: MLXCleanupBenchmarkGenerator())

        let results = await runner.run(models: models, cases: cases) { status in
            print("CLEANUP_BENCHMARK \(status)")
        }

        let outputURL = Self.repositoryRoot.appendingPathComponent("docs/cleanup-benchmark.md")
        try CleanupBenchmarkMarkdownReport.write(results: results, to: outputURL)
        XCTAssertEqual(results.map(\.modelID), models)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor CleanupBenchmarkGeneratorStub: CleanupBenchmarkModelGenerating {
    private let downloadedModels: Set<String>
    private let outputs: [String: String]
    private(set) var loadedModels: [String] = []

    init(downloadedModels: Set<String>, outputs: [String: String]) {
        self.downloadedModels = downloadedModels
        self.outputs = outputs
    }

    func isModelDownloaded(_ modelID: String) -> Bool {
        downloadedModels.contains(modelID)
    }

    func load(modelID: String) {
        loadedModels.append(modelID)
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) -> String {
        outputs[text] ?? text
    }

    func unload() {}
}
#endif
