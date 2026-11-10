import Combine
import CoreML
import Foundation
import OSLog
import WhisperKit

protocol TranscriptionService: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float], language: String?) async throws -> String
}

enum TranscriptionPreferences {
    static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"
    static let fallbackModel = "small"
    static let lowMemoryThreshold: UInt64 = 16 * 1_024 * 1_024 * 1_024
    static var isLowMemoryMac: Bool { ProcessInfo.processInfo.physicalMemory < lowMemoryThreshold }
    static var recommendedModel: String { isLowMemoryMac ? fallbackModel : defaultModel }

    static let modelKey = "transcription.model"
    static let automaticLanguageKey = "transcription.automaticLanguage"
    static let languageKey = "transcription.language"
    static let vocabularyKey = "transcription.vocabulary"

    static var configuredModel: String {
        if SafeModeState.isEnabled { return fallbackModel }
        let value = UserDefaults.standard.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? recommendedModel
    }

    static var configuredLanguage: String? {
        guard !UserDefaults.standard.bool(forKey: automaticLanguageKey) else { return nil }
        let value = UserDefaults.standard.string(forKey: languageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? "fr"
    }

    static var vocabulary: String {
        UserDefaults.standard.string(forKey: vocabularyKey) ?? ""
    }
}

@MainActor
final class TranscriptionModelState: ObservableObject {
    static let shared = TranscriptionModelState()

    @Published private(set) var status = "Modèle non chargé"
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var loadedModel: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false

    private init() {}

    func downloading(_ model: String, progress: Double) {
        status = "Téléchargement de \(model)…"
        downloadProgress = min(max(progress, 0), 1)
        isBusy = true
        isReady = false
    }

    func loading(_ model: String) {
        status = "Chargement de \(model)…"
        downloadProgress = nil
        isBusy = true
        isReady = false
    }

    func usingFallback(after model: String) {
        status = "Échec de \(model), tentative avec \(TranscriptionPreferences.fallbackModel)…"
        downloadProgress = nil
        isBusy = true
        isReady = false
    }

    func loaded(_ model: String) {
        status = "Modèle chargé : \(model)"
        downloadProgress = nil
        loadedModel = model
        isBusy = true
        isReady = false
    }

    func warmingUp(_ model: String) {
        status = "Modèle chargé : \(model) — pré-chauffage…"
        downloadProgress = nil
        loadedModel = model
        isBusy = true
        isReady = false
    }

    func ready(_ model: String) {
        status = "Modèle prêt : \(model)"
        downloadProgress = nil
        loadedModel = model
        isBusy = false
        isReady = true
    }

    func unloaded(_ message: String) {
        status = message
        downloadProgress = nil
        loadedModel = nil
        isBusy = false
        isReady = false
    }

    func failed(_ error: Error) {
        status = "Modèle indisponible : \(error.localizedDescription)"
        downloadProgress = nil
        loadedModel = nil
        isBusy = false
        isReady = false
    }
}

enum WhisperKitTranscriptionError: LocalizedError {
    case modelNotPrepared

    var errorDescription: String? {
        switch self {
        case .modelNotPrepared:
            "Le modèle WhisperKit n’est pas chargé."
        }
    }
}

actor WhisperKitTranscriptionService: TranscriptionService {
    static let shared = WhisperKitTranscriptionService()

    private static let storedModelPathsKey = "transcription.storedModelPaths"

    private var whisperKit: WhisperKit?
    private var preparedForModelRequest: String?
    private var preparationTask: Task<Void, Error>?

    nonisolated func requestEmergencyUnload() {
        Task { await self.unload(reason: "Whisper déchargé par l’arrêt d’urgence") }
    }

    func prepare() async throws {
        let requestedModel = TranscriptionPreferences.configuredModel
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

    /// Applies the model currently entered in Settings and keeps the replacement loaded.
    func reloadConfiguredModel() async throws {
        if let preparationTask {
            try await preparationTask.value
        }
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
            "Transcription", id: signpostID,
            "samples=\(samples.count)"
        )
        defer { PerformanceSignposts.signposter.endInterval("Transcription", state) }
        return try await transcribeWithKit(
            whisperKit,
            samples: samples,
            language: language,
            vocabulary: TranscriptionPreferences.vocabulary
        )
    }

    private func transcribeWithKit(
        _ whisperKit: WhisperKit,
        samples: [Float],
        language: String?,
        vocabulary: String
    ) async throws -> String {
        let promptTokens: [Int]? = {
            let words = vocabulary
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !words.isEmpty, let tokenizer = whisperKit.tokenizer else { return nil }

            let prompt = "Vocabulaire : " + words.joined(separator: ", ") + "."
            let tokens = tokenizer.encode(text: prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            return tokens.isEmpty ? nil : tokens
        }()

        let options = DecodingOptions(
            language: language,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens
        )
        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )
        return Self.clean(results.map(\.text).joined(separator: " "))
    }

    private func prepare(requestedModel: String) async throws {
        do {
            try await load(model: requestedModel)
        } catch where requestedModel != TranscriptionPreferences.fallbackModel {
            await TranscriptionModelState.shared.usingFallback(after: requestedModel)
            try await load(model: TranscriptionPreferences.fallbackModel)
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
        let folder: URL
        let reusedCompiledCache: Bool
        if let storedFolder = storedFolder(for: model) {
            folder = storedFolder
            reusedCompiledCache = Self.containsCompiledModels(in: storedFolder)
        } else {
            let modelsDirectory = try Self.modelsDirectory()
            await TranscriptionModelState.shared.downloading(model, progress: 0)
            folder = try await WhisperKit.download(
                variant: model,
                downloadBase: modelsDirectory
            ) { progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    TranscriptionModelState.shared.downloading(model, progress: fraction)
                }
            }
            store(folder: folder, for: model)
            reusedCompiledCache = false
        }

        await TranscriptionModelState.shared.loading(model)
        let config = WhisperKitConfig(
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
        let preparedKit = try await WhisperKit(config)
        let loadSeconds = Self.seconds(loadStart.duration(to: .now))
        logger.info(
            "whisper model load duration=\(loadSeconds, format: .fixed(precision: 3))s compiled_cache_reused=\(reusedCompiledCache)"
        )
        PersistentDiagnosticLog.shared.modelLoadCompleted(
            duration: loadSeconds,
            reusedCompiledCache: reusedCompiledCache
        )
        whisperKit = preparedKit
        await TranscriptionModelState.shared.loaded(model)
        if SafeModeState.isEnabled {
            await TranscriptionModelState.shared.ready(model)
            return
        }
        await TranscriptionModelState.shared.warmingUp(model)
        let warmupStart = ContinuousClock.now
        _ = try await transcribeWithKit(
            preparedKit,
            samples: Array(repeating: 0, count: 16_000),
            language: "fr",
            vocabulary: ""
        )
        let warmupSeconds = Self.seconds(warmupStart.duration(to: .now))
        logger.info("whisper warmup duration=\(warmupSeconds, format: .fixed(precision: 3))s audio=1.000s")
        await TranscriptionModelState.shared.ready(model)
    }

    private func storedFolder(for model: String) -> URL? {
        guard let path = UserDefaults.standard.dictionary(forKey: Self.storedModelPathsKey)?[model] as? String else {
            return nil
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func store(folder: URL, for model: String) {
        var paths = UserDefaults.standard.dictionary(forKey: Self.storedModelPathsKey) ?? [:]
        paths[model] = folder.path
        UserDefaults.standard.set(paths, forKey: Self.storedModelPathsKey)
    }

    private static func modelsDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("DictaMac", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func containsCompiledModels(in directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "mlmodelc" { return true }
        }
        return false
    }

    private static func clean(_ text: String) -> String {
        let artifactPattern = #"(?i)\s*[\[\(]\s*(?:blank[_ ]audio|musique|music|silence|inaudible|bruit(?: de fond)?|applaudissements?)\s*[\]\)]\s*"#
        let withoutArtifacts = text.replacingOccurrences(
            of: artifactPattern,
            with: " ",
            options: .regularExpression
        )
        return withoutArtifacts
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Transcription"
    )

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
