import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import OSLog

actor LocalCleanupModelManager: LocalTextGenerating {
    private var container: ModelContainer?
    private var loadedModelID: String?
    private var isWarmedUp = false
    private var activationTask: Task<Void, Never>?
    private let downloader = ResumableModelDownloader()
    private let settings: any TextCleanupSettings & TextCleanupSettingsWriting
    private let modelState: LocalCleanupModelState
    private let modelLoadingGate: any ModelLoadingGating
    private let diagnosticLog: any DiagnosticLogging
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "LocalCleanupModel"
    )

    init(
        settings: any TextCleanupSettings & TextCleanupSettingsWriting,
        modelState: LocalCleanupModelState,
        modelLoadingGate: any ModelLoadingGating,
        diagnosticLog: any DiagnosticLogging
    ) {
        self.settings = settings
        self.modelState = modelState
        self.modelLoadingGate = modelLoadingGate
        self.diagnosticLog = diagnosticLog
    }

    var isReady: Bool { container != nil && isWarmedUp }

    static var modelsRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("DictaMac/Models/Cleanup", isDirectory: true)
    }

    nonisolated func requestEmergencyUnload() {
        Task { await self.unload(reason: "Modèle local déchargé par l’arrêt d’urgence") }
    }

    func activateConfiguredModel() {
        guard settings.configuredEngine == .local, settings.localDownloadApproved else { return }
        let requested = settings.configuredLocalModel
        if container != nil, loadedModelID == requested, isWarmedUp { return }
        activationTask?.cancel()
        activationTask = Task { [weak self] in await self?.downloadAndLoad(modelID: requested) }
    }

    func approveDownloadAndActivate() {
        settings.approveLocalDownload()
        activateConfiguredModel()
    }

    func cancelDownload() {
        activationTask?.cancel()
        activationTask = nil
        Task { @MainActor in
            modelState.unloaded("Téléchargement annulé — reprise disponible")
        }
    }

    func unload(reason: String = "Modèle déchargé") {
        activationTask?.cancel()
        activationTask = nil
        container = nil
        loadedModelID = nil
        isWarmedUp = false
        MLX.GPU.clearCache()
        Task { @MainActor [modelState] in modelState.unloaded(reason) }
        logger.info("local cleanup model unloaded")
        ProcessMemoryDiagnostics.logFootprint(.mlxUnloaded, diagnosticLog: diagnosticLog)
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        guard let container else { throw LocalCleanupError.modelNotReady }
        return try await container.perform { context in
            let rawInput = try await context.processor.prepare(input: UserInput(prompt: text))
            let textTokenLimit = max(1, Int((Double(rawInput.text.tokens.size) * 1.3).rounded(.up)))
            let effectiveMaxTokens = min(maxTokens, textTokenLimit)
            let input = try await context.processor.prepare(input: UserInput(messages: messages))
            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0),
                context: context
            ) { tokens in
                if Task.isCancelled || tokens.count >= effectiveMaxTokens { return .stop }
                return .more
            }.output
        }
    }

    private func downloadAndLoad(modelID: String) async {
        do {
            try await modelLoadingGate.run { [weak self] in
                await self?.downloadAndLoadWithoutCompetition(modelID: modelID)
            }
        } catch {
            await MainActor.run { modelState.failed(error) }
        }
    }

    private func downloadAndLoadWithoutCompetition(modelID: String) async {
        let loadStart = ContinuousClock.now
        diagnosticLog.stage(.modelLoad, phase: "begin")
        let signpostID = PerformanceSignposts.signposter.makeSignpostID()
        let signpostState = PerformanceSignposts.signposter.beginInterval(
            "Model load",
            id: signpostID,
            "engine=mlx model=\(modelID, privacy: .public)"
        )
        defer {
            PerformanceSignposts.signposter.endInterval("Model load", signpostState)
            ProcessMemoryDiagnostics.logFootprint(.mlxLoadFinished, diagnosticLog: diagnosticLog)
            diagnosticLog.stage(
                .modelLoad,
                phase: "end",
                duration: Self.seconds(loadStart.duration(to: .now))
            )
        }
        do {
            try await loadModel(modelID: modelID)
        } catch is CancellationError {
            activationTask = nil
            await MainActor.run {
                modelState.unloaded("Téléchargement annulé — reprise disponible")
            }
        } catch {
            activationTask = nil
            await MainActor.run { modelState.failed(error) }
            logger.error("local cleanup model load failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func loadModel(modelID: String) async throws {
        try FileManager.default.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)
        let modelDirectory = Self.modelsRoot.appendingPathComponent(modelID, isDirectory: true)
        await MainActor.run { modelState.downloading(progress: 0) }
        try await downloader.download(modelID: modelID, to: modelDirectory) { progress in
            Task { @MainActor [modelState = self.modelState] in
                modelState.downloading(progress: progress)
            }
        }
        try Task.checkCancellation()
        await MainActor.run { modelState.loading() }
        configureMemoryLimits()
        let model = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(directory: modelDirectory)
        )
        try Task.checkCancellation()
        container = model
        loadedModelID = modelID
        isWarmedUp = false
        try await warmUp(modelID: modelID)
    }

    private func configureMemoryLimits() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryLimit = Int(min(physicalMemory / 4, 4 * 1_024 * 1_024 * 1_024))
        MLX.GPU.set(cacheLimit: 64 * 1_024 * 1_024)
        MLX.GPU.set(memoryLimit: memoryLimit, relaxed: false)
    }

    private func warmUp(modelID: String) async throws {
        await MainActor.run { modelState.loaded(model: modelID) }
        let start = ContinuousClock.now
        _ = try await generate(
            text: "Bonjour, ceci est un test court.",
            messages: [["role": "user", "content": "Réponds uniquement: Bonjour."]],
            maxTokens: 8
        )
        let duration = Self.seconds(start.duration(to: .now))
        isWarmedUp = true
        activationTask = nil
        await MainActor.run { modelState.ready(model: modelID) }
        logger.info("local cleanup warmup duration=\(duration, format: .fixed(precision: 3))s tokens=8")
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
