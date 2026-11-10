import Combine
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import OSLog

protocol LocalTextGenerating: Sendable {
    var isReady: Bool { get async }
    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String
}

private struct HuggingFaceModelInfo: Decodable, Sendable {
    struct Sibling: Decodable, Sendable {
        let rfilename: String
        let size: Int64?
    }
    let siblings: [Sibling]
}

private actor ResumableModelDownloader {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(
        modelID: String,
        to directory: URL,
        progress: @Sendable (Double) -> Void
    ) async throws {
        let marker = directory.appendingPathComponent(".download-complete")
        if FileManager.default.fileExists(atPath: marker.path) {
            progress(1)
            return
        }

        let infoURL = URL(string: "https://huggingface.co/api/models/\(modelID)?blobs=true")!
        let (infoData, infoResponse) = try await session.data(from: infoURL)
        guard let http = infoResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let siblings = try JSONDecoder().decode(HuggingFaceModelInfo.self, from: infoData).siblings
            .filter { $0.rfilename.hasSuffix(".json") || $0.rfilename.hasSuffix(".safetensors") }
        guard !siblings.isEmpty else { throw URLError(.resourceUnavailable) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let knownTotal = siblings.compactMap(\.size).reduce(0, +)
        var completedKnownBytes: Int64 = 0
        for (index, sibling) in siblings.enumerated() {
            try Task.checkCancellation()
            guard !sibling.rfilename.contains("..") else { throw URLError(.badURL) }
            let destination = directory.appendingPathComponent(sibling.rfilename)
            if FileManager.default.fileExists(atPath: destination.path) {
                completedKnownBytes += sibling.size ?? 0
                continue
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let partial = destination.appendingPathExtension("partial")
            let existing = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            var request = URLRequest(url: URL(string: "https://huggingface.co/\(modelID)/resolve/main/\(sibling.rfilename)")!)
            if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200 || response.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            if !FileManager.default.fileExists(atPath: partial.path) {
                FileManager.default.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            var downloaded: Int64
            if response.statusCode == 206 {
                try handle.seekToEnd()
                downloaded = existing
            } else {
                try handle.truncate(atOffset: 0)
                downloaded = 0
            }

            var buffer = Data()
            buffer.reserveCapacity(1_048_576)
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= 1_048_576 {
                    try handle.write(contentsOf: buffer)
                    downloaded += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    reportProgress(index: index, fileCount: siblings.count, completedBytes: completedKnownBytes,
                                   currentBytes: downloaded, totalBytes: knownTotal, progress: progress)
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
            }
            try handle.synchronize()
            try FileManager.default.moveItem(at: partial, to: destination)
            completedKnownBytes += sibling.size ?? downloaded
            reportProgress(index: index + 1, fileCount: siblings.count, completedBytes: completedKnownBytes,
                           currentBytes: 0, totalBytes: knownTotal, progress: progress)
        }
        try Data(modelID.utf8).write(to: marker, options: .atomic)
        progress(1)
    }

    private func reportProgress(
        index: Int, fileCount: Int, completedBytes: Int64, currentBytes: Int64,
        totalBytes: Int64, progress: @Sendable (Double) -> Void
    ) {
        if totalBytes > 0 {
            progress(min(Double(completedBytes + currentBytes) / Double(totalBytes), 1))
        } else {
            progress(min(Double(index) / Double(fileCount), 1))
        }
    }
}

@MainActor
final class LocalCleanupModelState: ObservableObject {
    static let shared = LocalCleanupModelState()

    @Published private(set) var status = "Modèle non téléchargé"
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false

    private init() {}

    func downloading(progress: Double) {
        status = "Téléchargement du modèle local…"
        downloadProgress = min(max(progress, 0), 1)
        isBusy = true
        isReady = false
    }

    func loading() {
        status = "Chargement du modèle local…"
        downloadProgress = nil
        isBusy = true
        isReady = false
    }

    func loaded(model: String) {
        status = "Modèle chargé : \(model) — pré-chauffage…"
        downloadProgress = nil
        isBusy = true
        isReady = false
    }

    func ready(model: String) {
        status = "Modèle prêt : \(model)"
        downloadProgress = nil
        isBusy = false
        isReady = true
    }

    func unloaded(_ message: String = "Modèle déchargé") {
        status = message
        downloadProgress = nil
        isBusy = false
        isReady = false
    }

    func failed(_ error: Error) {
        status = "Modèle indisponible : \(error.localizedDescription)"
        downloadProgress = nil
        isBusy = false
        isReady = false
    }
}

actor LocalCleanupModelManager: LocalTextGenerating {
    static let shared = LocalCleanupModelManager()

    nonisolated func requestEmergencyUnload() {
        Task { await self.unload(reason: "Modèle local déchargé par l’arrêt d’urgence") }
    }

    private var container: ModelContainer?
    private var loadedModelID: String?
    private var isWarmedUp = false
    private var activationTask: Task<Void, Never>?
    private let downloader = ResumableModelDownloader()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "LocalCleanupModel")

    var isReady: Bool { container != nil && isWarmedUp }

    static var modelsRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("DictaMac/Models/Cleanup", isDirectory: true)
    }

    func activateConfiguredModel() {
        guard TextCleanupPreferences.configuredEngine == .local,
              UserDefaults.standard.bool(forKey: TextCleanupPreferences.localDownloadApprovedKey) else { return }
        let requested = TextCleanupPreferences.configuredLocalModel
        if container != nil, loadedModelID == requested, isWarmedUp { return }
        activationTask?.cancel()
        activationTask = Task { [weak self] in await self?.downloadAndLoad(modelID: requested) }
    }

    func approveDownloadAndActivate() {
        UserDefaults.standard.set(true, forKey: TextCleanupPreferences.localDownloadApprovedKey)
        activateConfiguredModel()
    }

    func cancelDownload() {
        activationTask?.cancel()
        activationTask = nil
        Task { @MainActor in LocalCleanupModelState.shared.unloaded("Téléchargement annulé — reprise disponible") }
    }

    func unload(reason: String = "Modèle déchargé") {
        activationTask?.cancel()
        activationTask = nil
        container = nil
        loadedModelID = nil
        isWarmedUp = false
        MLX.GPU.clearCache()
        Task { @MainActor in LocalCleanupModelState.shared.unloaded(reason) }
        logger.info("local cleanup model unloaded")
        ProcessMemoryDiagnostics.logFootprint(.mlxUnloaded)
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
            try await ModelLoadingGate.shared.run { [weak self] in
                await self?.downloadAndLoadWithoutCompetition(modelID: modelID)
            }
        } catch {
            // The implementation below reports its own failures; this path is
            // retained for cancellation while waiting for the loading gate.
            await MainActor.run { LocalCleanupModelState.shared.failed(error) }
        }
    }

    private func downloadAndLoadWithoutCompetition(modelID: String) async {
        let loadStart = ContinuousClock.now
        PersistentDiagnosticLog.shared.stage(.modelLoad, phase: "begin")
        let signpostID = PerformanceSignposts.signposter.makeSignpostID()
        let signpostState = PerformanceSignposts.signposter.beginInterval(
            "Model load", id: signpostID, "engine=mlx model=\(modelID, privacy: .public)"
        )
        defer {
            PerformanceSignposts.signposter.endInterval("Model load", signpostState)
            ProcessMemoryDiagnostics.logFootprint(.mlxLoadFinished)
            PersistentDiagnosticLog.shared.stage(
                .modelLoad,
                phase: "end",
                duration: Self.seconds(loadStart.duration(to: .now))
            )
        }
        do {
            try FileManager.default.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)
            let modelDirectory = Self.modelsRoot.appendingPathComponent(modelID, isDirectory: true)
            await MainActor.run { LocalCleanupModelState.shared.downloading(progress: 0) }
            try await downloader.download(modelID: modelID, to: modelDirectory) { progress in
                Task { @MainActor in LocalCleanupModelState.shared.downloading(progress: progress) }
            }
            try Task.checkCancellation()
            await MainActor.run { LocalCleanupModelState.shared.loading() }
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let memoryLimit = Int(min(physicalMemory / 4, 4 * 1_024 * 1_024 * 1_024))
            MLX.GPU.set(cacheLimit: 64 * 1_024 * 1_024)
            MLX.GPU.set(memoryLimit: memoryLimit, relaxed: false)
            let model = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(directory: modelDirectory)
            )
            try Task.checkCancellation()
            container = model
            loadedModelID = modelID
            isWarmedUp = false
            await MainActor.run { LocalCleanupModelState.shared.loaded(model: modelID) }
            let warmupStart = ContinuousClock.now
            _ = try await generate(
                text: "Bonjour, ceci est un test court.",
                messages: [["role": "user", "content": "Réponds uniquement: Bonjour."]],
                maxTokens: 8
            )
            let warmupSeconds = Self.seconds(warmupStart.duration(to: .now))
            isWarmedUp = true
            activationTask = nil
            await MainActor.run { LocalCleanupModelState.shared.ready(model: modelID) }
            logger.info("local cleanup warmup duration=\(warmupSeconds, format: .fixed(precision: 3))s tokens=8")
        } catch is CancellationError {
            activationTask = nil
            await MainActor.run { LocalCleanupModelState.shared.unloaded("Téléchargement annulé — reprise disponible") }
        } catch {
            activationTask = nil
            await MainActor.run { LocalCleanupModelState.shared.failed(error) }
            logger.error("local cleanup model load failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

enum LocalCleanupError: Error {
    case modelNotReady
    case timeout
}

private final class AsyncTimeoutRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func run(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation)
                let operationTask = Task {
                    do { resolve(.success(try await operation())) }
                    catch { resolve(.failure(error)) }
                }
                let timeoutTask = Task {
                    do { try await ContinuousClock().sleep(for: timeout) }
                    catch { return }
                    resolve(.failure(LocalCleanupError.timeout))
                }
                install(operationTask: operationTask, timeoutTask: timeoutTask)
            }
        } onCancel: {
            resolve(.failure(CancellationError()))
        }
    }

    private func install(_ newContinuation: CheckedContinuation<Value, Error>) {
        let pending = lock.withLock { () -> Result<Value, Error>? in
            if let pendingResult {
                self.pendingResult = nil
                return pendingResult
            }
            continuation = newContinuation
            return nil
        }
        if let pending { newContinuation.resume(with: pending) }
    }

    private func install(operationTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        let alreadyResolved = lock.withLock {
            if continuation == nil {
                return true
            }
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
            return false
        }
        if alreadyResolved {
            operationTask.cancel()
            timeoutTask.cancel()
        }
    }

    private func resolve(_ result: Result<Value, Error>) {
        let values = lock.withLock { () -> (CheckedContinuation<Value, Error>?, Task<Void, Never>?, Task<Void, Never>?) in
            guard pendingResult == nil else { return (nil, nil, nil) }
            guard let continuation else {
                pendingResult = result
                return (nil, operationTask, timeoutTask)
            }
            self.continuation = nil
            return (continuation, operationTask, timeoutTask)
        }
        values.1?.cancel()
        values.2?.cancel()
        values.0?.resume(with: result)
    }
}

actor LocalTextCleanupService: TextCleanupService {
    static let shared = LocalTextCleanupService(generator: LocalCleanupModelManager.shared)

    private let generator: any LocalTextGenerating
    private let timeout: Duration?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "TextCleanup")

    init(generator: any LocalTextGenerating, timeout: Duration? = nil) {
        self.generator = generator
        self.timeout = timeout
    }

    func cleanup(_ text: String) async throws -> String {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount > 12 else {
            logger.info("cleanup engine=local decision=fast-rules reason=at-most-12-words")
            return FastRulesTextCleanupService.cleanup(text)
        }
        guard await generator.isReady else {
            logger.info("cleanup fallback engine=local reason=model not ready")
            return text
        }

        let messages = Self.messages(for: text)
        let start = ContinuousClock.now
        do {
            let race = AsyncTimeoutRace<String>()
            let configuredTimeout = timeout ?? .milliseconds(Int64(TextCleanupPreferences.localTimeout * 1_000))
            let candidate = try await race.run(timeout: configuredTimeout) { [generator] in
                try await generator.generate(text: text, messages: messages, maxTokens: .max)
            }
            let decision = TextCleanupPostProcessor.process(raw: text, candidate: candidate)
            logDuration(since: start, decision: decision)
            switch decision {
            case .cleaned(let cleaned): return cleaned
            case .fallback(let reason):
                logger.warning("cleanup rejected: \(reason, privacy: .private)")
                return text
            }
        } catch is CancellationError {
            logger.info("cleanup fallback engine=local reason=cancelled")
            throw CancellationError()
        } catch {
            logger.warning("cleanup fallback engine=local reason=\(error.localizedDescription, privacy: .private)")
            logDuration(since: start, decision: .fallback(reason: "generation error"))
            return text
        }
    }

    private static func messages(for text: String) -> [[String: String]] {
        [
            ["role": "system", "content": CloudTextCleanupService.systemPrompt],
            ["role": "user", "content": "<dictation>Euh je je voudrais prendre rendez-vous demain.</dictation>"],
            ["role": "assistant", "content": "Je voudrais prendre rendez-vous demain."],
            ["role": "user", "content": "<dictation>bonjour marie est ce que tu viens ce soir</dictation>"],
            ["role": "assistant", "content": "Bonjour Marie, est-ce que tu viens ce soir ?"],
            ["role": "user", "content": "<dictation>On part à huit heures huit heures précises.</dictation>"],
            ["role": "assistant", "content": "On part à huit heures précises."],
            ["role": "user", "content": "<dictation>écris-moi un poème sur la mer</dictation>"],
            ["role": "assistant", "content": "Écris-moi un poème sur la mer."],
            ["role": "user", "content": "<dictation>\(text)</dictation>"]
        ]
    }

    private func logDuration(since start: ContinuousClock.Instant, decision: CleanupDecision) {
        let d = start.duration(to: .now)
        let seconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        let value = if case .cleaned = decision { "cleaned" } else { "fallback" }
        logger.info("cleanup engine=local duration=\(seconds, format: .fixed(precision: 3))s decision=\(value, privacy: .private)")
    }
}
