#if DEBUG
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

actor MLXCleanupBenchmarkGenerator: CleanupBenchmarkModelGenerating {
    private var container: ModelContainer?
    private let modelsRoot: URL

    init(modelsRoot: URL = LocalCleanupModelManager.modelsRoot) {
        self.modelsRoot = modelsRoot
    }

    func isModelDownloaded(_ modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: completionMarker(for: modelID).path)
    }

    func load(modelID: String) async throws {
        guard isModelDownloaded(modelID) else { throw ModelError.notDownloaded }
        configureMemoryLimits()
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(directory: directory(for: modelID))
        )
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        guard let container else { throw ModelError.notLoaded }
        return try await container.perform { context in
            let rawInput = try await context.processor.prepare(input: UserInput(prompt: text))
            let tokenLimit = max(1, Int((Double(rawInput.text.tokens.size) * 1.3).rounded(.up)))
            let input = try await context.processor.prepare(input: UserInput(messages: messages))
            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0),
                context: context
            ) { tokens in
                if Task.isCancelled || tokens.count >= min(maxTokens, tokenLimit) { return .stop }
                return .more
            }.output
        }
    }

    func unload() {
        container = nil
        MLX.GPU.clearCache()
    }

    private func directory(for modelID: String) -> URL {
        modelsRoot.appendingPathComponent(modelID, isDirectory: true)
    }

    private func completionMarker(for modelID: String) -> URL {
        directory(for: modelID).appendingPathComponent(".download-complete")
    }

    private func configureMemoryLimits() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryLimit = Int(min(physicalMemory / 4, 4 * 1_024 * 1_024 * 1_024))
        MLX.GPU.set(cacheLimit: 64 * 1_024 * 1_024)
        MLX.GPU.set(memoryLimit: memoryLimit, relaxed: false)
    }

    private enum ModelError: LocalizedError {
        case notDownloaded
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .notDownloaded: "Modèle non téléchargé"
            case .notLoaded: "Modèle non chargé"
            }
        }
    }
}
#endif
