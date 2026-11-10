import CoreML
import Foundation
import OSLog
import WhisperKit

actor WhisperKitTranscriptionService: TranscriptionService {
    static let shared = WhisperKitTranscriptionService()

    private let settings: any TranscriptionSettings
    private let modelPathStore: any TranscriptionModelPathStoring
    private var whisperKit: WhisperKit?
    private var preparedForModelRequest: String?
    private var preparationTask: Task<Void, Error>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Transcription"
    )

    init(
        settings: any TranscriptionSettings = StoredTranscriptionSettings(),
        modelPathStore: any TranscriptionModelPathStoring = StoredTranscriptionSettings()
    ) {
        self.settings = settings
        self.modelPathStore = modelPathStore
    }

    nonisolated func requestEmergencyUnload() {
        Task { await self.unload(reason: "Whisper déchargé par l’arrêt d’urgence") }
    }

    func prepare() async throws {
        let requestedModel = settings.configuredModel
        if whisperKit != nil, preparedForModelRequest == requestedModel { return }
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.prepare(requestedModel: requestedModel)
        }
        preparationTask = task
        do {
            try await task.value
            preparationTask = nil
        } catch {
            preparationTask = nil
            await TranscriptionModelState.shared.failed(error)
            throw error
        }
    }

    func reloadConfiguredModel() async throws {
        if let preparationTask { try await preparationTask.value }
        whisperKit = nil
        preparedForModelRequest = nil
        try await prepare()
    }

    func unload(reason: String = "Modèle déchargé") async {
        preparationTask?.cancel()
        preparationTask = nil
        whisperKit = nil
        preparedForModelRequest = nil
        await TranscriptionModelState.shared.unloaded(reason)
        ProcessMemoryDiagnostics.logFootprint(.whisperUnloaded)
    }

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        try await prepare()
        guard let whisperKit else { throw WhisperKitTranscriptionError.modelNotPrepared }
        let signpostID = PerformanceSignposts.signposter.makeSignpostID()
        let state = PerformanceSignposts.signposter.beginInterval(
            "Transcription", id: signpostID, "samples=\(samples.count)"
        )
        defer { PerformanceSignposts.signposter.endInterval("Transcription", state) }
        return try await transcribeWithKit(
            whisperKit,
            samples: samples,
            language: language,
            vocabulary: settings.vocabulary
        )
    }

    private func transcribeWithKit(
        _ whisperKit: WhisperKit,
        samples: [Float],
        language: String?,
        vocabulary: String
    ) async throws -> String {
        let options = DecodingOptions(
            language: language,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens(for: vocabulary, whisperKit: whisperKit)
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        return WhisperTranscriptionTextCleaner.clean(results.map(\.text).joined(separator: " "))
    }

    private func promptTokens(for vocabulary: String, whisperKit: WhisperKit) -> [Int]? {
        let words = vocabulary
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty, let tokenizer = whisperKit.tokenizer else { return nil }
        let prompt = "Vocabulaire : " + words.joined(separator: ", ") + "."
        let tokens = tokenizer.encode(text: prompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    private func prepare(requestedModel: String) async throws {
        do {
            try await load(model: requestedModel)
        } catch where requestedModel != StoredTranscriptionSettings.fallbackModel {
            await TranscriptionModelState.shared.usingFallback(after: requestedModel)
            try await load(model: StoredTranscriptionSettings.fallbackModel)
        }
        preparedForModelRequest = requestedModel
    }

    private func load(model: String) async throws {
        try await ModelLoadingGate.shared.run { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.loadWithoutCompetition(model: model)
        }
    }

    private func loadWithoutCompetition(model: String) async throws {
        let loadStart = ContinuousClock.now
        PersistentDiagnosticLog.shared.stage(.modelLoad, phase: "begin")
        let signpostID = PerformanceSignposts.signposter.makeSignpostID()
        let signpostState = PerformanceSignposts.signposter.beginInterval(
            "Model load", id: signpostID, "engine=whisper model=\(model, privacy: .public)"
        )
        defer {
            PerformanceSignposts.signposter.endInterval("Model load", signpostState)
            ProcessMemoryDiagnostics.logFootprint(.whisperLoaded)
        }
        let (folder, reusedCompiledCache) = try await modelFolder(for: model)
        await TranscriptionModelState.shared.loading(model)
        let preparedKit = try await WhisperKit(configuration(for: folder))
        recordLoad(start: loadStart, reusedCompiledCache: reusedCompiledCache)
        whisperKit = preparedKit
        await TranscriptionModelState.shared.loaded(model)
        try await warmUp(preparedKit, model: model)
    }

    private func modelFolder(for model: String) async throws -> (URL, Bool) {
        if let storedFolder = storedFolder(for: model) {
            return (storedFolder, WhisperModelFiles.containsCompiledModels(in: storedFolder))
        }
        let modelsDirectory = try WhisperModelFiles.modelsDirectory()
        await TranscriptionModelState.shared.downloading(model, progress: 0)
        let folder = try await WhisperKit.download(variant: model, downloadBase: modelsDirectory) { progress in
            Task { @MainActor in
                TranscriptionModelState.shared.downloading(model, progress: progress.fractionCompleted)
            }
        }
        modelPathStore.setStoredModelPath(folder.path, for: model)
        return (folder, false)
    }

    private func configuration(for folder: URL) -> WhisperKitConfig {
        WhisperKitConfig(
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
        )
    }

    private func warmUp(_ kit: WhisperKit, model: String) async throws {
        if SafeModeState.isEnabled {
            await TranscriptionModelState.shared.ready(model)
            return
        }
        await TranscriptionModelState.shared.warmingUp(model)
        let start = ContinuousClock.now
        _ = try await transcribeWithKit(
            kit,
            samples: Array(repeating: 0, count: 16_000),
            language: "fr",
            vocabulary: ""
        )
        let seconds = Self.seconds(start.duration(to: .now))
        logger.info("whisper warmup duration=\(seconds, format: .fixed(precision: 3))s audio=1.000s")
        await TranscriptionModelState.shared.ready(model)
    }

    private func storedFolder(for model: String) -> URL? {
        guard let path = modelPathStore.storedModelPath(for: model) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func recordLoad(start: ContinuousClock.Instant, reusedCompiledCache: Bool) {
        let seconds = Self.seconds(start.duration(to: .now))
        logger.info(
            "whisper model load duration=\(seconds, format: .fixed(precision: 3))s compiled_cache_reused=\(reusedCompiledCache)"
        )
        PersistentDiagnosticLog.shared.modelLoadCompleted(
            duration: seconds,
            reusedCompiledCache: reusedCompiledCache
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
