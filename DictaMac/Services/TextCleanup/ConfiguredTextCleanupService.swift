actor ConfiguredTextCleanupService: TextCleanupService {
    private let settings: any TextCleanupSettings
    private let registry: TextCleanupEngineRegistry

    init(settings: any TextCleanupSettings, registry: TextCleanupEngineRegistry) {
        self.settings = settings
        self.registry = registry
    }

    func cleanup(
        _ text: String,
        dictionary: [String],
        context: DictationContext
    ) async throws -> String {
        guard let service = registry.service(for: settings.configuredEngine) else { return text }
        return try await service.cleanup(text, dictionary: dictionary, context: context)
    }
}
