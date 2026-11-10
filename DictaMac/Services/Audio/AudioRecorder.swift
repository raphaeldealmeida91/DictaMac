import Foundation
import OSLog

enum AudioRecorderError: LocalizedError, Equatable {
    case alreadyRecording
    case microphonePermissionRequired
    case inputUnavailable
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Un enregistrement est déjà en cours."
        case .microphonePermissionRequired:
            "L’autorisation d’accéder au microphone est requise."
        case .inputUnavailable:
            "Aucun périphérique d’entrée audio n’est disponible."
        case .converterCreationFailed:
            "Impossible de créer le convertisseur audio."
        }
    }
}

/// Orchestrates microphone capture while replaceable collaborators own system concerns.
final class AudioRecorder: AudioRecording, @unchecked Sendable {
    typealias LevelHandler = @MainActor @Sendable (Float) -> Void
    typealias ErrorHandler = @MainActor @Sendable (AudioRecorderError) -> Void

    static let sampleRate = 16_000.0
    // Fn presses shorter than 300 ms are filtered before recording starts.
    // This smaller audio floor only rejects captures too short to transcribe.
    static let minimumDuration: TimeInterval = 0.050

    var onLevelUpdate: LevelHandler? {
        didSet { sampleAccumulator.setLevelHandler(onLevelUpdate) }
    }
    var onError: ErrorHandler?

    var lastRecordingDuration: TimeInterval {
        stateLock.withLock { storedRecordingDuration }
    }

    private let engine: any AudioCaptureEngineManaging
    private let sampleAccumulator: any AudioSampleAccumulating
    private let permissionProvider: any MicrophonePermissionProviding
    private let environmentObserver: any AudioEnvironmentObserving
    private let diagnosticLog: any DiagnosticLogging
    private let stateLock = NSLock()
    private var storedRecordingDuration: TimeInterval = 0
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "AudioRecorder"
    )

    convenience init(
        emergencyAudioRegistry: any AudioEmergencyStopRegistering,
        diagnosticLog: any DiagnosticLogging
    ) {
        let accumulator = AudioSampleAccumulator()
        self.init(
            engine: AudioCaptureEngine(
                sampleRate: Self.sampleRate,
                sampleAccumulator: accumulator
            ),
            sampleAccumulator: accumulator,
            permissionProvider: SystemMicrophonePermissionProvider(),
            environmentObserver: AudioEnvironmentObserver(),
            emergencyStopRegistrar: emergencyAudioRegistry,
            diagnosticLog: diagnosticLog
        )
    }

    init(
        engine: any AudioCaptureEngineManaging,
        sampleAccumulator: any AudioSampleAccumulating,
        permissionProvider: any MicrophonePermissionProviding,
        environmentObserver: any AudioEnvironmentObserving,
        emergencyStopRegistrar: any AudioEmergencyStopRegistering,
        diagnosticLog: any DiagnosticLogging
    ) {
        self.engine = engine
        self.sampleAccumulator = sampleAccumulator
        self.permissionProvider = permissionProvider
        self.environmentObserver = environmentObserver
        self.diagnosticLog = diagnosticLog
        observeEnvironment()
        emergencyStopRegistrar.install { [weak self] timeout in
            self?.performEmergencyStop(timeout: timeout) ?? true
        }
        refreshMicrophonePermission()
    }

    deinit {
        environmentObserver.stop()
    }

    func start() throws {
        guard permissionProvider.isAuthorized else {
            logMicrophonePermission()
            throw AudioRecorderError.microphonePermissionRequired
        }
        stateLock.withLock { storedRecordingDuration = 0 }
        try engine.start()
    }

    /// Returns mono 16 kHz samples, or an empty array for captures too short to transcribe.
    func stop() -> [Float] {
        let samples = sampleAccumulator.finishCapture()
        let duration = Double(samples.count) / Self.sampleRate
        stateLock.withLock { storedRecordingDuration = duration }
        engine.stop()
        return duration >= Self.minimumDuration ? samples : []
    }

    /// Returns samples captured after `offset` without stopping the recorder.
    func capturedSamples(since offset: Int) -> [Float] {
        sampleAccumulator.samples(since: offset)
    }

    private func observeEnvironment() {
        environmentObserver.start(
            permissionChanged: { [weak self] in self?.refreshMicrophonePermission() },
            configurationChanged: { [weak self] in self?.handleConfigurationChange() },
            systemWillSleep: { [weak self] in self?.handleSystemWillSleep() },
            systemDidWake: { [weak self] in self?.handleSystemDidWake() }
        )
    }

    private func handleConfigurationChange() {
        resetAudioEngine(shouldPrepare: permissionProvider.isAuthorized)
    }

    private func handleSystemWillSleep() {
        resetAudioEngine(shouldPrepare: false)
    }

    private func handleSystemDidWake() {
        guard permissionProvider.isAuthorized else { return }
        engine.prepareWhenIdle()
    }

    private func resetAudioEngine(shouldPrepare: Bool) {
        engine.handleConfigurationChange(shouldPrepare: shouldPrepare) { [weak self] inputWasLost in
            guard inputWasLost else { return }
            self?.reportInputLoss(error: .inputUnavailable)
        }
    }

    private func refreshMicrophonePermission() {
        logMicrophonePermission()
        guard permissionProvider.isAuthorized else {
            engine.handlePermissionRevocation { [weak self] inputWasLost in
                guard inputWasLost else { return }
                self?.reportInputLoss(error: .microphonePermissionRequired)
            }
            return
        }
        engine.prepareWhenIdle()
    }

    private func reportInputLoss(error: AudioRecorderError) {
        diagnosticLog.inputLost()
        DispatchQueue.main.async { [weak self] in self?.onError?(error) }
    }

    private func performEmergencyStop(timeout: TimeInterval) -> Bool {
        sampleAccumulator.discard()
        return engine.emergencyStop(timeout: timeout)
    }

    private func logMicrophonePermission() {
        logger.info(
            "Permission microphone: \(self.permissionProvider.statusDescription, privacy: .public)"
        )
    }
}
