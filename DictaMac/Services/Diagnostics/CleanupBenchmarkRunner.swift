#if DEBUG
import Foundation
import OSLog

actor CleanupBenchmarkRunner {
    static let defaultModels = [
        StoredTextCleanupSettings.lightLocalModel,
        StoredTextCleanupSettings.defaultLocalModel,
        StoredTextCleanupSettings.qualityLocalModel
    ]

    private let generator: any CleanupBenchmarkModelGenerating
    private let promptBuilder: CleanupPromptBuilder
    private let validator: DictationCleanupValidator
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "CleanupBenchmark"
    )

    init(
        generator: any CleanupBenchmarkModelGenerating,
        promptBuilder: CleanupPromptBuilder = CleanupPromptBuilder(),
        validator: DictationCleanupValidator = DictationCleanupValidator()
    ) {
        self.generator = generator
        self.promptBuilder = promptBuilder
        self.validator = validator
    }

    func run(
        models: [String],
        cases: [CleanupBenchmarkCase],
        status: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> [CleanupBenchmarkResult] {
        var results: [CleanupBenchmarkResult] = []
        for modelID in Self.uniqueModels(models) {
            results.append(await benchmark(modelID: modelID, cases: cases, status: status))
        }
        return results
    }

    static func configuredModels(environment: [String: String]) -> [String] {
        guard let value = environment["DICTAMAC_CLEANUP_BENCHMARK_MODELS"] else {
            return defaultModels
        }
        let models = value.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return models.isEmpty ? defaultModels : uniqueModels(models)
    }

    private func benchmark(
        modelID: String,
        cases: [CleanupBenchmarkCase],
        status: @escaping @Sendable (String) -> Void
    ) async -> CleanupBenchmarkResult {
        guard await generator.isModelDownloaded(modelID) else {
            let reason = "modèle non téléchargé — ignoré sans accès réseau"
            status("\(modelID) : \(reason)")
            logger.info("cleanup benchmark model=\(modelID, privacy: .public) skipped reason=not_downloaded")
            return .skipped(modelID: modelID, reason: reason)
        }
        do {
            status("Chargement local de \(modelID)…")
            try await generator.load(modelID: modelID)
            try await warmUp()
            let result = try await measure(modelID: modelID, cases: cases, status: status)
            await generator.unload()
            return result
        } catch {
            await generator.unload()
            logger.error("cleanup benchmark model=\(modelID, privacy: .public) failed error=\(error.localizedDescription, privacy: .private)")
            return .failed(modelID: modelID, reason: error.localizedDescription)
        }
    }

    private func measure(
        modelID: String,
        cases: [CleanupBenchmarkCase],
        status: @escaping @Sendable (String) -> Void
    ) async throws -> CleanupBenchmarkResult {
        var latencies: [Double] = []
        var distances: [Double] = []
        var rejectionCount = 0
        for (index, benchmarkCase) in cases.enumerated() {
            status("\(modelID) : cas \(index + 1)/\(cases.count)")
            let measurement = try await measure(benchmarkCase)
            latencies.append(measurement.latency)
            distances.append(measurement.distance)
            rejectionCount += measurement.wasRejected ? 1 : 0
        }
        return completedResult(
            modelID: modelID,
            latencies: latencies,
            distances: distances,
            rejectionCount: rejectionCount
        )
    }

    private func measure(_ benchmarkCase: CleanupBenchmarkCase) async throws -> CaseMeasurement {
        let messages = messages(for: benchmarkCase)
        let start = ContinuousClock.now
        let candidate = try await generator.generate(
            text: benchmarkCase.raw,
            messages: messages,
            maxTokens: .max
        )
        let latency = Self.seconds(start.duration(to: .now))
        let cleaned = TextCleanupPostProcessor.removingDictationTags(from: candidate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = validator.validate(
            original: benchmarkCase.raw,
            candidate: candidate,
            dictionary: benchmarkCase.dictionary
        )
        return CaseMeasurement(
            latency: latency,
            distance: CleanupBenchmarkMetrics.normalizedEditDistance(cleaned, benchmarkCase.expected),
            wasRejected: validation.isRejected
        )
    }

    private func completedResult(
        modelID: String,
        latencies: [Double],
        distances: [Double],
        rejectionCount: Int
    ) -> CleanupBenchmarkResult {
        let count = latencies.count
        return CleanupBenchmarkResult(
            modelID: modelID,
            caseCount: count,
            medianLatency: CleanupBenchmarkMetrics.median(latencies),
            percentile95Latency: CleanupBenchmarkMetrics.percentile95(latencies),
            validatorRejectionRate: count > 0 ? Double(rejectionCount) / Double(count) : 0,
            normalizedEditDistance: distances.isEmpty ? 0 : distances.reduce(0, +) / Double(distances.count),
            outcome: .completed
        )
    }

    private func warmUp() async throws {
        let text = "Bonjour, ceci est un test court."
        _ = try await generator.generate(
            text: text,
            messages: [
                ["role": "system", "content": "Réponds uniquement avec le texte fourni."],
                ["role": "user", "content": text]
            ],
            maxTokens: 16
        )
    }

    private func messages(for benchmarkCase: CleanupBenchmarkCase) -> [[String: String]] {
        [
            ["role": "system", "content": promptBuilder.systemPrompt(
                style: .polished,
                dictionary: benchmarkCase.dictionary,
                context: benchmarkCase.context
            )],
            ["role": "user", "content": "<dictation>\(benchmarkCase.raw)</dictation>"]
        ]
    }

    private static func uniqueModels(_ models: [String]) -> [String] {
        models.reduce(into: []) { result, model in
            if !result.contains(model) { result.append(model) }
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private struct CaseMeasurement {
        let latency: Double
        let distance: Double
        let wasRejected: Bool
    }
}

private extension DictationCleanupValidator.Result {
    var isRejected: Bool {
        if case .rejected = self { return true }
        return false
    }
}
#endif
