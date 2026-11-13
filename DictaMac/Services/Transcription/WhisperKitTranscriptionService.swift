import CoreML
import Foundation
import OSLog
import WhisperKit

actor WhisperKitTranscriptionService: TranscriptionService {
    private enum AudioGuard {
        static let sampleRate = 16_000
        static let minimumDuration: TimeInterval = 0.25
        static let minimumPeak: Float = 0.005
        static let minimumRootMeanSquare: Float = 0.0005
    }

    private enum LoadOutcome: String {
        case success
        case failure
        case cancelled
    }

    private let settings: any TranscriptionSettings
    private let modelPathStore: any TranscriptionModelPathStoring
    private let personalDictionary: any PersonalDictionary
    private let modelState: TranscriptionModelState
    private let modelLoadingGate: any ModelLoadingGating
    private let diagnosticLog: any DiagnosticLogging
    private var whisperKit: WhisperKit?
    private var preparedForModelRequest: String?
    private var preparationTask: Task<Void, Error>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Transcription"
    )

    init(
        settings: any TranscriptionSettings,
        modelPathStore: any TranscriptionModelPathStoring,
        personalDictionary: any PersonalDictionary,
        modelState: TranscriptionModelState,
        modelLoadingGate: any ModelLoadingGating,
        diagnosticLog: any DiagnosticLogging
    ) {
        self.settings = settings
        self.modelPathStore = modelPathStore
        self.personalDictionary = personalDictionary
        self.modelState = modelState
        self.modelLoadingGate = modelLoadingGate
        self.diagnosticLog = diagnosticLog
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
            await modelState.failed(error)
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
        await modelState.unloaded(reason)
        ProcessMemoryDiagnostics.logFootprint(.whisperUnloaded, diagnosticLog: diagnosticLog)
    }

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard Self.containsAudibleSpeech(samples) else {
            logger.info("transcription skipped reason=short_or_silent samples=\(samples.count)")
            return ""
        }
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
            dictionary: personalDictionary.entries().map(\.canonical)
        )
    }

    private func transcribeWithKit(
        _ whisperKit: WhisperKit,
        samples: [Float],
        language: String?,
        dictionary: [String]
    ) async throws -> String {
        let options = Self.decodingOptions(
            language: language,
            promptTokens: promptTokens(for: dictionary, whisperKit: whisperKit)
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        return WhisperTranscriptionTextCleaner.clean(results.map(\.text).joined(separator: " "))
    }

    private func promptTokens(for dictionary: [String], whisperKit: WhisperKit) -> [Int]? {
        guard let prompt = Self.dictionaryPrompt(for: dictionary),
              let tokenizer = whisperKit.tokenizer else { return nil }
        let tokens = tokenizer.encode(text: prompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    static func decodingOptions(language: String?, promptTokens: [Int]?) -> DecodingOptions {
        DecodingOptions(
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            promptTokens: promptTokens,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6,
            chunkingStrategy: nil
        )
    }

    static func dictionaryPrompt(for canonicalTerms: [String]) -> String? {
        let terms = canonicalTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = terms.last else { return nil }
        if terms.count == 1 {
            return "La dictée peut contenir le terme \(last)."
        }
        let beginning = terms.dropLast().joined(separator: ", ")
        return "La dictée peut contenir notamment \(beginning) et \(last)."
    }

    static func containsAudibleSpeech(_ samples: [Float]) -> Bool {
        let minimumSamples = Int(AudioGuard.minimumDuration * Double(AudioGuard.sampleRate))
        guard samples.count >= minimumSamples else { return false }
        var peak: Float = 0
        var squaredSum: Double = 0
        for sample in samples {
            let magnitude = abs(sample)
            peak = max(peak, magnitude)
            squaredSum += Double(sample * sample)
        }
        let rootMeanSquare = Float((squaredSum / Double(samples.count)).squareRoot())
        return peak >= AudioGuard.minimumPeak
            && rootMeanSquare >= AudioGuard.minimumRootMeanSquare
    }

    private func prepare(requestedModel: String) async throws {
        do {
            try await load(model: requestedModel)
        } catch where requestedModel != StoredTranscriptionSettings.fallbackModel {
            await modelState.usingFallback(after: requestedModel)
            try await load(model: StoredTranscriptionSettings.fallbackModel)
        }
        preparedForModelRequest = requestedModel
    }

    private func load(model: String) async throws {
        try await modelLoadingGate.run { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.loadWithoutCompetition(model: model)
        }
    }

    private func loadWithoutCompetition(model: String) async throws {
        let loadStart = ContinuousClock.now
        var reusedCompiledCache: Bool?
        var outcome = LoadOutcome.failure
        diagnosticLog.stage(.modelLoad, phase: "begin")
        let signpostID = PerformanceSignposts.signposter.makeSignpostID()
        let signpostState = PerformanceSignposts.signposter.beginInterval(
            "Model load", id: signpostID, "engine=whisper model=\(model, privacy: .public)"
        )
        defer {
            PerformanceSignposts.signposter.endInterval("Model load", signpostState)
            ProcessMemoryDiagnostics.logFootprint(.whisperLoaded, diagnosticLog: diagnosticLog)
            recordLoad(
                start: loadStart,
                reusedCompiledCache: reusedCompiledCache,
                outcome: outcome
            )
        }
        do {
            reusedCompiledCache = try await loadModel(model)
            outcome = .success
        } catch is CancellationError {
            outcome = .cancelled
            throw CancellationError()
        } catch {
            outcome = .failure
            throw error
        }
    }

    private func loadModel(_ model: String) async throws -> Bool {
        let (folder, reusedCompiledCache) = try await modelFolder(for: model)
        await modelState.loading(model)
        let preparedKit = try await WhisperKit(configuration(for: folder))
        whisperKit = preparedKit
        await modelState.loaded(model)
        try await warmUp(preparedKit, model: model)
        return reusedCompiledCache
    }

    private func modelFolder(for model: String) async throws -> (URL, Bool) {
        if let storedFolder = storedFolder(for: model) {
            return (storedFolder, WhisperModelFiles.containsCompiledModels(in: storedFolder))
        }
        let modelsDirectory = try WhisperModelFiles.modelsDirectory()
        await modelState.downloading(model, progress: 0)
        let folder = try await WhisperKit.download(variant: model, downloadBase: modelsDirectory) { progress in
            Task { @MainActor in
                self.modelState.downloading(model, progress: progress.fractionCompleted)
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
            await modelState.ready(model)
            return
        }
        await modelState.warmingUp(model)
        let start = ContinuousClock.now
        _ = try await transcribeWithKit(
            kit,
            samples: Array(repeating: 0, count: 16_000),
            language: "fr",
            dictionary: []
        )
        let seconds = Self.seconds(start.duration(to: .now))
        logger.info("whisper warmup duration=\(seconds, format: .fixed(precision: 3))s audio=1.000s")
        await modelState.ready(model)
    }

    private func storedFolder(for model: String) -> URL? {
        guard let path = modelPathStore.storedModelPath(for: model) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func recordLoad(
        start: ContinuousClock.Instant,
        reusedCompiledCache: Bool?,
        outcome: LoadOutcome
    ) {
        let seconds = Self.seconds(start.duration(to: .now))
        logger.info(
            "whisper model load duration=\(seconds, format: .fixed(precision: 3))s outcome=\(outcome.rawValue, privacy: .public)"
        )
        diagnosticLog.modelLoadEnded(
            duration: seconds,
            reusedCompiledCache: reusedCompiledCache,
            outcome: outcome.rawValue
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
