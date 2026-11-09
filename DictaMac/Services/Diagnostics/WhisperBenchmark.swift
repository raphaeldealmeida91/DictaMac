#if DEBUG
import AppKit
import CoreML
import Foundation
import OSLog
import UniformTypeIdentifiers
import WhisperKit

struct WhisperBenchmarkResult: Identifiable, Sendable {
    let id = UUID()
    let model: String
    let duration: TimeInterval
    let text: String
    let error: String?
}

@MainActor
final class WhisperBenchmarkState: ObservableObject {
    static let shared = WhisperBenchmarkState()

    @Published private(set) var isRunning = false
    @Published private(set) var status = "Aucun benchmark lancé"
    @Published private(set) var results: [WhisperBenchmarkResult] = []

    private init() {}

    func chooseWAVAndRun() {
        let panel = NSOpenPanel()
        panel.title = "Choisir le WAV de benchmark"
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isRunning = true
        results = []
        status = "Recherche des variantes WhisperKit…"
        Task { [self] in
            let output = await WhisperBenchmarkRunner.shared.run(wavURL: url) { status in
                Task { @MainActor in self.status = status }
            }
            results = output
            isRunning = false
            status = "Benchmark terminé — \(output.count) modèle(s)"
        }
    }
}

actor WhisperBenchmarkRunner {
    static let shared = WhisperBenchmarkRunner()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "WhisperBenchmark"
    )

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
            do {
                let result = try await ModelLoadingGate.shared.run {
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
                    let results = try await kit.transcribe(
                        audioPath: wavURL.path,
                        decodeOptions: DecodingOptions(
                            language: TranscriptionPreferences.configuredLanguage,
                            detectLanguage: TranscriptionPreferences.configuredLanguage == nil,
                            skipSpecialTokens: true,
                            withoutTimestamps: true
                        )
                    )
                    let duration = Self.seconds(start.duration(to: .now))
                    let text = results.map(\.text).joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return WhisperBenchmarkResult(
                        model: model, duration: duration, text: text, error: nil
                    )
                }
                output.append(result)
                let duration = result.duration
                logger.info("benchmark model=\(model, privacy: .public) duration=\(duration, format: .fixed(precision: 3))s")
            } catch {
                output.append(WhisperBenchmarkResult(
                    model: model,
                    duration: 0,
                    text: "",
                    error: error.localizedDescription
                ))
                logger.error("benchmark model=\(model, privacy: .public) failed error=\(error.localizedDescription, privacy: .private)")
            }
        }
        return output
    }

    static func benchmarkModels(from available: [String]) -> [String] {
        let turbo = available.first { $0 == TranscriptionPreferences.defaultModel }
            ?? available.first { $0.contains("large-v3") && $0.contains("turbo") && !$0.hasSuffix("MB") }
        let quantized = available
            .filter { $0.contains("large-v3") && $0.contains("turbo") && $0.range(of: #"_\d+MB$"#, options: .regularExpression) != nil }
            .sorted()
            .first
        let small = available.first { $0 == "openai_whisper-small" }
            ?? available.first { $0 == "small" }
            ?? available.first { $0.contains("whisper-small") && !$0.contains(".") }
        return [turbo, quantized, small].compactMap { $0 }.reduce(into: []) { models, model in
            if !models.contains(model) { models.append(model) }
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
