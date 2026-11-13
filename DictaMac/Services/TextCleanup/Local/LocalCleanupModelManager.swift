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
    private var activatingModelID: String?
    private var activationID: UUID?
    private var activeGenerationCount = 0
    private let downloader = ResumableModelDownloader()
    private let settings: any TextCleanupSettings & TextCleanupSettingsWriting
    private let modelState: LocalCleanupModelState
    private let modelLoadingGate: any ModelLoadingGating
    private let diagnosticLog: any DiagnosticLogging
    private let safeMode: any SafeModeControlling
    private let inactivityPolicy: any LocalModelInactivityPolicy
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "LocalCleanupModel"
    )

    init(
        settings: any TextCleanupSettings & TextCleanupSettingsWriting,
        modelState: LocalCleanupModelState,
        modelLoadingGate: any ModelLoadingGating,
        diagnosticLog: any DiagnosticLogging,
        safeMode: any SafeModeControlling = SafeModeState(),
        inactivityPolicy: (any LocalModelInactivityPolicy)? = nil
    ) {
        self.settings = settings
        self.modelState = modelState
        self.modelLoadingGate = modelLoadingGate
        self.diagnosticLog = diagnosticLog
        self.safeMode = safeMode
        self.inactivityPolicy = inactivityPolicy ?? DefaultLocalModelInactivityPolicy(
            timeout: { settings.localModelInactivityTimeout }
        )
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
        guard !safeMode.isEnabled else {
            reportInactive(SafeModeState.localCleanupUnavailableMessage, reason: "safe_mode")
            return
        }
        guard settings.configuredEngine == .local else {
            reportInactive("Moteur local non sélectionné", reason: "engine_not_local")
            return
        }
        guard settings.localDownloadApproved else {
            reportInactive("Téléchargement du modèle local non autorisé", reason: "download_not_approved")
            return
        }
        let requested = settings.configuredLocalModel
        if container != nil, loadedModelID == requested, isWarmedUp {
            Task { @MainActor [modelState] in modelState.ready(model: requested) }
            logger.info("local cleanup activation skipped reason=already_ready")
            return
        }
        startActivation(for: requested)
    }

    func prepare() async throws {
        guard !isReady else { return }
        activateConfiguredModel()
        await activationTask?.value
        guard isReady else { throw LocalCleanupError.modelNotReady }
    }

    func approveDownloadAndActivate() {
        settings.approveLocalDownload()
        activateConfiguredModel()
    }

    func cancelDownload() {
        activationTask?.cancel()
        activationTask = nil
        activatingModelID = nil
        activationID = nil
        Task { @MainActor in
            modelState.unloaded("Téléchargement annulé — reprise disponible")
        }
    }

    func unload(reason: String = "Modèle déchargé") {
        inactivityPolicy.cancel()
        activationTask?.cancel()
        activationTask = nil
        activatingModelID = nil
        activationID = nil
        container = nil
        loadedModelID = nil
        isWarmedUp = false
        MLX.GPU.clearCache()
        Task { @MainActor [modelState] in modelState.unloaded(reason) }
        logger.info("local cleanup model unloaded")
        ProcessMemoryDiagnostics.logFootprint(.mlxUnloaded, diagnosticLog: diagnosticLog)
    }

    func refreshInactivityPolicy() {
        guard isReady else { return }
        scheduleInactivityUnload()
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        guard let container else { throw LocalCleanupError.modelNotReady }
        beginGeneration()
        defer { endGeneration() }
        return try await performGeneration(
            container: container,
            text: text,
            messages: messages,
            maxTokens: maxTokens
        )
    }

    private func performGeneration(
        container: ModelContainer,
        text: String,
        messages: [[String: String]],
        maxTokens: Int
    ) async throws -> String {
        try await container.perform { context in
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

    private func startActivation(for modelID: String) {
        if activationTask != nil, activatingModelID == modelID {
            logger.info("local cleanup activation skipped reason=already_activating")
            return
        }
        activationTask?.cancel()
        inactivityPolicy.cancel()
        isWarmedUp = false
        let id = UUID()
        activatingModelID = modelID
        activationID = id
        activationTask = Task { [weak self] in
            await self?.downloadAndLoad(modelID: modelID, activationID: id)
        }
    }

    private func downloadAndLoad(modelID: String, activationID: UUID) async {
        if modelLoadingGate.isLoading {
            await MainActor.run { modelState.waitingForTranscriptionModel() }
            logger.info("local cleanup activation waiting reason=model_loading_gate_busy")
        }
        do {
            try await modelLoadingGate.run { [weak self] in
                try Task.checkCancellation()
                try await self?.downloadAndLoadWithoutCompetition(modelID: modelID)
            }
            finishActivation(id: activationID)
        } catch is CancellationError {
            await reportCancellationIfCurrent(id: activationID)
        } catch {
            await reportFailureIfCurrent(error, id: activationID)
        }
    }

    private func reportInactive(_ message: String, reason: String) {
        Task { @MainActor [modelState] in modelState.unloaded(message) }
        logger.info("local cleanup activation skipped reason=\(reason, privacy: .public)")
    }

    private func downloadAndLoadWithoutCompetition(modelID: String) async throws {
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
        try await loadModel(modelID: modelID)
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
        try Task.checkCancellation()
        let duration = Self.seconds(start.duration(to: .now))
        isWarmedUp = true
        await MainActor.run { modelState.ready(model: modelID) }
        scheduleInactivityUnload()
        logger.info("local cleanup warmup duration=\(duration, format: .fixed(precision: 3))s tokens=8")
    }

    private func finishActivation(id: UUID) {
        guard activationID == id else { return }
        activationTask = nil
        activatingModelID = nil
        activationID = nil
    }

    private func reportCancellationIfCurrent(id: UUID) async {
        guard activationID == id else { return }
        finishActivation(id: id)
        await MainActor.run {
            modelState.unloaded("Téléchargement annulé — reprise disponible")
        }
    }

    private func reportFailureIfCurrent(_ error: Error, id: UUID) async {
        guard activationID == id else { return }
        finishActivation(id: id)
        await MainActor.run { modelState.failed(error) }
        logger.error("local cleanup model load failed: \(error.localizedDescription, privacy: .private)")
    }

    private func beginGeneration() {
        activeGenerationCount += 1
        inactivityPolicy.activityStarted()
    }

    private func endGeneration() {
        activeGenerationCount = max(0, activeGenerationCount - 1)
        scheduleInactivityUnloadAfterActivity()
    }

    private func scheduleInactivityUnloadAfterActivity() {
        inactivityPolicy.activityEnded { [weak self] in
            await self?.unloadIfInactive()
        }
    }

    private func scheduleInactivityUnload() {
        inactivityPolicy.modelBecameReady { [weak self] in
            await self?.unloadIfInactive()
        }
    }

    private func unloadIfInactive() {
        guard activeGenerationCount == 0, container != nil else { return }
        unload(reason: "Modèle local déchargé après inactivité")
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
