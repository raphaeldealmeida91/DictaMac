import Foundation

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

    init(
        selectionSettings: any SelectionCorrectionSettings,
        cleanupSettings: any TextCleanupSettings,
        localGenerator: any LocalTextGenerating,
        cloudGenerator: any TextGenerating,
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
        self.timeout = timeout
        self.promptBuilder = promptBuilder
        self.validator = validator
        self.diff = diff
        self.fastRules = fastRules
    }

    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        try Task.checkCancellation()
        let candidate = try await candidate(for: text, dictionary: dictionary)
        try Task.checkCancellation()
        guard validator.accepts(original: text, candidate: candidate, dictionary: dictionary) else {
            return .unchanged(text)
        }
        return SelectionCorrection(
            original: text,
            corrected: candidate,
            changes: diff.changes(from: text, to: candidate)
        )
    }

    private func candidate(for text: String, dictionary: [String]) async throws -> String {
        if selectionSettings.allowsCloud, cleanupSettings.configuredEngine == .cloud {
            return try await generate(with: cloudGenerator, text: text, dictionary: dictionary)
        }
        if await localGenerator.isReady {
            return try await generate(with: localGenerator, text: text, dictionary: dictionary)
        }
        return fastRules.correct(text)
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
