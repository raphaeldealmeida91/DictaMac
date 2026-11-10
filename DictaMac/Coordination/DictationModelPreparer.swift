import Foundation

protocol LocalCleanupModelActivating: Sendable {
    func activateConfiguredModel() async
}

@MainActor
protocol DictationModelPreparing: AnyObject {
    func prepare() async throws
}

@MainActor
protocol DictationModelReadinessProviding: AnyObject {
    var isReady: Bool { get }
    var progress: Double? { get }
}

@MainActor
final class DictationModelPreparer: DictationModelPreparing {
    private enum Constants {
        static let localModelActivationDelay = Duration.seconds(1)
    }

    private let transcriptionService: any TranscriptionService
    private let textCleanupSettings: any TextCleanupSettings
    private let localModelManager: any LocalCleanupModelActivating

    init(
        transcriptionService: any TranscriptionService,
        textCleanupSettings: any TextCleanupSettings,
        localModelManager: any LocalCleanupModelActivating
    ) {
        self.transcriptionService = transcriptionService
        self.textCleanupSettings = textCleanupSettings
        self.localModelManager = localModelManager
    }

    func prepare() async throws {
        try await transcriptionService.prepare()
        guard textCleanupSettings.configuredEngine == .local,
              textCleanupSettings.localDownloadApproved else { return }
        try await ContinuousClock().sleep(for: Constants.localModelActivationDelay)
        await localModelManager.activateConfiguredModel()
    }
}

extension LocalCleanupModelManager: LocalCleanupModelActivating {}
