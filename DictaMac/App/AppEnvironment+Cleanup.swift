import Foundation

extension AppEnvironment {
    static func makeCleanupService(
        settings: StoredTextCleanupSettings,
        manager: LocalCleanupModelManager,
        wordDiagnostics: any TextWordDiagnosticsRecording
    ) -> ConfiguredTextCleanupService {
        let endpoint = URL(string: "https://api.openai.com/v1/responses")
            ?? URL(fileURLWithPath: "/v1/responses")
        let registry = TextCleanupEngineRegistry(services: [
            .disabled: PassthroughTextCleanupService(),
            .fast: FastRulesTextCleanupService(settings: settings),
            .local: LocalTextCleanupService(
                generator: manager,
                settings: settings,
                wordDiagnostics: wordDiagnostics
            ),
            .cloud: CloudTextCleanupService(
                endpoint: endpoint,
                settings: settings,
                wordDiagnostics: wordDiagnostics
            )
        ])
        return ConfiguredTextCleanupService(settings: settings, registry: registry)
    }
}
