struct TextCleanupEngineRegistry: Sendable {
    private let services: [TextCleanupEngine: any TextCleanupService]

    init(services: [TextCleanupEngine: any TextCleanupService]) {
        self.services = services
    }

    func service(for engine: TextCleanupEngine) -> (any TextCleanupService)? {
        services[engine]
    }
}
