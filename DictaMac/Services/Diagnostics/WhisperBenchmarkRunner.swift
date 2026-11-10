#if DEBUG
import CoreML
import Foundation
import OSLog
import WhisperKit

actor WhisperBenchmarkRunner {
    private let settings: any TranscriptionSettings
    private let modelLoadingGate: any ModelLoadingGating
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "WhisperBenchmark"
    )

    init(
        settings: any TranscriptionSettings,
        modelLoadingGate: any ModelLoadingGating
    ) {
        self.settings = settings
        self.modelLoadingGate = modelLoadingGate
    }

    func run(
        wavURL: URL,
        status: @escaping @Sendable (String) -> Void
    ) async -> [WhisperBenchmarkResult] {
        let available: [String]
        do {
            available = try await WhisperKit.fetchAvailableModels(
                matching: ["*large-v3*", "*small*"]
            )
        } catch {
            return [WhisperBenchmarkResult(
                model: "WhisperKit",
                duration: 0,
                text: "",
                error: "Liste des modèles indisponible : \(error.localizedDescription)"
            )]
        }

        let models = Self.benchmarkModels(from: available)
        var output: [WhisperBenchmarkResult] = []
        for model in models {
            status("Benchmark : \(model)…")
            output.append(await benchmark(model: model, wavURL: wavURL))
        }
        return output
    }

    static func benchmarkModels(from available: [String]) -> [String] {
        let turbo = available.first { $0 == StoredTranscriptionSettings.defaultModel }
            ?? available.first { $0.contains("large-v3") && $0.contains("turbo") && !$0.hasSuffix("MB") }
        let quantized = available
            .filter {
                $0.contains("large-v3")
                    && $0.contains("turbo")
                    && $0.range(of: #"_\d+MB$"#, options: .regularExpression) != nil
            }
            .sorted()
            .first
        let small = available.first { $0 == "openai_whisper-small" }
            ?? available.first { $0 == "small" }
            ?? available.first { $0.contains("whisper-small") && !$0.contains(".") }
        return [turbo, quantized, small].compactMap { $0 }.reduce(into: []) { models, model in
            if !models.contains(model) { models.append(model) }
        }
    }

    private func benchmark(model: String, wavURL: URL) async -> WhisperBenchmarkResult {
        do {
            let result = try await modelLoadingGate.run { [settings] in
                let directory = try Self.modelsDirectory()
                let folder = try await WhisperKit.download(variant: model, downloadBase: directory)
                let kit = try await WhisperKit(WhisperKitConfig(
                    modelFolder: folder.path,
                    computeOptions: ModelComputeOptions(
                        melCompute: .cpuAndGPU,
                        audioEncoderCompute: .cpuAndNeuralEngine,
                        textDecoderCompute: .cpuAndNeuralEngine
                    ),
                    verbose: false,
                    prewarm: false,
                    load: true,
                    download: false
                ))
                let start = ContinuousClock.now
                let language = settings.configuredLanguage
                let results = try await kit.transcribe(
                    audioPath: wavURL.path,
                    decodeOptions: DecodingOptions(
                        language: language,
                        detectLanguage: language == nil,
                        skipSpecialTokens: true,
                        withoutTimestamps: true
                    )
                )
                let duration = Self.seconds(start.duration(to: .now))
                let text = results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return WhisperBenchmarkResult(
                    model: model,
                    duration: duration,
                    text: text,
                    error: nil
                )
            }
            logger.info(
                "benchmark model=\(model, privacy: .public) duration=\(result.duration, format: .fixed(precision: 3))s"
            )
            return result
        } catch {
            logger.error(
                "benchmark model=\(model, privacy: .public) failed error=\(error.localizedDescription, privacy: .private)"
            )
            return WhisperBenchmarkResult(
                model: model,
                duration: 0,
                text: "",
                error: error.localizedDescription
            )
        }
    }

    private static func modelsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("DictaMac/Models/Benchmark", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
#endif
