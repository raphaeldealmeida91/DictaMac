import Foundation
import OSLog

actor ConfiguredSelectionCorrectionService: SelectionCorrectionService {
    static let maximumDuration: Duration = .seconds(6)

    private let selectionSettings: any SelectionCorrectionSettings
    private let cleanupSettings: any TextCleanupSettings
    private let localGenerator: any LocalTextGenerating
    private let cloudGenerator: any TextGenerating
    private let promptBuilder: SelectionCorrectionPromptBuilder
    private let validator: SelectionCorrectionValidator
    private let diff: SelectionCorrectionDiff
    private let fastRules: SelectionCorrectionFastRules
    private let timeout: Duration
    private let apiKeyProvider: @Sendable () throws -> String?
    private let activateLocalModel: @Sendable () async -> Void
    private let safeMode: any SafeModeControlling
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "selection"
    )

    init(
        selectionSettings: any SelectionCorrectionSettings,
        cleanupSettings: any TextCleanupSettings,
        localGenerator: any LocalTextGenerating,
        cloudGenerator: any TextGenerating,
        apiKeyProvider: @escaping @Sendable () throws -> String? = { try TextCleanupAPIKeyStore.load() },
        activateLocalModel: @escaping @Sendable () async -> Void = {},
        safeMode: any SafeModeControlling = SafeModeState(),
        timeout: Duration = ConfiguredSelectionCorrectionService.maximumDuration,
        promptBuilder: SelectionCorrectionPromptBuilder = SelectionCorrectionPromptBuilder(),
        validator: SelectionCorrectionValidator = SelectionCorrectionValidator(),
        diff: SelectionCorrectionDiff = SelectionCorrectionDiff(),
        fastRules: SelectionCorrectionFastRules = SelectionCorrectionFastRules()
    ) {
        self.selectionSettings = selectionSettings
        self.cleanupSettings = cleanupSettings
        self.localGenerator = localGenerator
        self.cloudGenerator = cloudGenerator
        self.apiKeyProvider = apiKeyProvider
        self.activateLocalModel = activateLocalModel
        self.safeMode = safeMode
        self.timeout = timeout
        self.promptBuilder = promptBuilder
        self.validator = validator
        self.diff = diff
        self.fastRules = fastRules
    }

    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        try Task.checkCancellation()
        let engine = await engineStatus()
        logger.info("engine selected engine=\(engine.rawValue, privacy: .public) length=\(text.count)")
        let candidate = try await candidate(for: text, dictionary: dictionary, engine: engine)
        try Task.checkCancellation()
        guard validator.accepts(original: text, candidate: candidate, dictionary: dictionary) else {
            logger.info("result=validator_rejected length=\(text.count)")
            return .unchanged(text)
        }
        let correction = SelectionCorrection(
            original: text,
            corrected: candidate,
            changes: diff.changes(from: text, to: candidate)
        )
        let result = correction.changes.isEmpty ? "unchanged" : "suggestion"
        logger.info("result=\(result, privacy: .public) length=\(text.count)")
        return correction
    }

    func engineStatus() async -> SelectionCorrectionEngine {
        if selectionSettings.allowsCloud, hasAPIKey {
            return .cloud
        }
        guard !safeMode.isEnabled else { return .rulesOnly }
        if await localGenerator.isReady {
            return .local
        }
        return .rulesOnly
    }

    func engineUnavailableMessage() async -> String? {
        safeMode.isEnabled ? SafeModeState.localCleanupUnavailableMessage : nil
    }

    func prepare() async {
        let isReady = await localGenerator.isReady
        guard cleanupSettings.configuredEngine == .local,
              cleanupSettings.localDownloadApproved,
              !isReady else { return }
        await activateLocalModel()
    }

    private func candidate(
        for text: String,
        dictionary: [String],
        engine: SelectionCorrectionEngine
    ) async throws -> String {
        switch engine {
        case .cloud:
            return try await generate(with: cloudGenerator, text: text, dictionary: dictionary)
        case .local:
            return try await generate(with: localGenerator, text: text, dictionary: dictionary)
        case .rulesOnly:
            return fastRules.correct(text)
        }
    }

    private var hasAPIKey: Bool {
        guard let key = try? apiKeyProvider() else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generate(
        with generator: any TextGenerating,
        text: String,
        dictionary: [String]
    ) async throws -> String {
        let messages = messages(text: text, dictionary: dictionary)
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await generator.generate(text: text, messages: messages, maxTokens: .max)
            }
            group.addTask { [timeout] in
                try await ContinuousClock().sleep(for: timeout)
                throw SelectionCorrectionError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    private func messages(text: String, dictionary: [String]) -> [[String: String]] {
        [
            ["role": "system", "content": promptBuilder.systemPrompt(dictionary: dictionary)],
            ["role": "user", "content": "<selection>\(text)</selection>"]
        ]
    }
}
