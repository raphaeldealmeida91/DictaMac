@preconcurrency import AVFoundation
import AppKit
import Foundation
import OSLog

enum AudioRecorderError: LocalizedError {
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

/// Captures microphone audio as mono, 16 kHz Float32 samples.
@MainActor
final class AudioRecorder {
    typealias LevelHandler = @MainActor @Sendable (Float) -> Void
    typealias ErrorHandler = @MainActor @Sendable (AudioRecorderError) -> Void

    static let sampleRate = 16_000.0
    // Fn presses shorter than 300 ms are filtered before recording starts.
    // This smaller audio floor only rejects captures too short to transcribe.
    static let minimumDuration: TimeInterval = 0.050

    var onLevelUpdate: LevelHandler? {
        didSet { captureBuffer.setLevelHandler(onLevelUpdate) }
    }
    var onError: ErrorHandler?

    private(set) var lastRecordingDuration: TimeInterval = 0

    private var engine: AVAudioEngine?
    private let captureBuffer = CaptureBuffer()
    private var configurationObserver: NSObjectProtocol?
    private var permissionObserver: NSObjectProtocol?
    private var applicationActiveObserver: NSObjectProtocol?
    private var isRecording = false
    private var tapIsInstalled = false
    private var engineIsPrepared = false
    private var isHandlingConfigurationChange = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "AudioRecorder"
    )

    init() {
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .microphonePermissionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMicrophonePermission() }
        }
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMicrophonePermission() }
        }

        refreshMicrophonePermission()
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        if let permissionObserver {
            NotificationCenter.default.removeObserver(permissionObserver)
        }
        if let applicationActiveObserver {
            NotificationCenter.default.removeObserver(applicationActiveObserver)
        }
    }

    func start() throws {
        guard !isRecording else { throw AudioRecorderError.alreadyRecording }
        guard microphoneIsAuthorized else {
            logMicrophonePermission()
            throw AudioRecorderError.microphonePermissionRequired
        }

        if !engineIsPrepared {
            do {
                try prepareEngine()
            } catch {
                tearDownEngine()
                throw error
            }
        }
        guard let engine else {
            throw AudioRecorderError.inputUnavailable
        }

        captureBuffer.beginCapture()
        lastRecordingDuration = 0

        do {
            try engine.start()
            isRecording = true
            logger.info("Moteur audio démarré")
        } catch {
            captureBuffer.discard()
            tearDownEngine()
            throw error
        }
    }

    /// Returns mono 16 kHz samples, or an empty array for captures too short to transcribe.
    func stop() -> [Float] {
        guard isRecording else { return [] }

        isRecording = false
        engine?.stop()
        logger.info("Moteur audio arrêté")

        let samples = captureBuffer.finishCapture()
        lastRecordingDuration = Double(samples.count) / Self.sampleRate

        guard lastRecordingDuration >= Self.minimumDuration else { return [] }
        return samples
    }

    /// Returns samples captured after `offset` without stopping the recorder.
    /// The capture buffer remains the source of truth returned by `stop()`.
    func capturedSamples(since offset: Int) -> [Float] {
        captureBuffer.samples(since: offset)
    }

    private var microphoneIsAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func prepareEngine() throws {
        guard microphoneIsAuthorized else {
            throw AudioRecorderError.microphonePermissionRequired
        }

        let engine = engine ?? AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info(
            "Format d’entrée détecté: \(inputFormat.sampleRate, format: .fixed(precision: 0)) Hz, \(inputFormat.channelCount) canal(aux)"
        )
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.inputUnavailable
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) {
            [captureBuffer] inputBuffer, _ in
            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let capacity = max(
                1,
                AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 32
            )
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else { return }

            var suppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) {
                _, inputStatus in
                guard !suppliedInput else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }

            guard conversionError == nil,
                  status != .error,
                  outputBuffer.frameLength > 0,
                  let channel = outputBuffer.floatChannelData?[0] else { return }

            captureBuffer.append(channel, count: Int(outputBuffer.frameLength))
        }
        tapIsInstalled = true
        engine.prepare()
        engineIsPrepared = true
        observeConfigurationChanges(for: engine)
        logger.info("Moteur audio prêt")
    }

    private func observeConfigurationChanges(for engine: AVAudioEngine) {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    private func removeTap() {
        guard tapIsInstalled, let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapIsInstalled = false
    }

    private func handleConfigurationChange() {
        guard !isHandlingConfigurationChange, let engine else { return }
        isHandlingConfigurationChange = true
        defer { isHandlingConfigurationChange = false }

        let shouldResume = isRecording

        engine.stop()
        if shouldResume {
            logger.info("Moteur audio arrêté pour changement de configuration")
        }
        removeTap()
        engine.reset()
        engineIsPrepared = false

        do {
            try prepareEngine()
            if shouldResume {
                try engine.start()
                logger.info("Moteur audio redémarré après changement de configuration")
            }
        } catch {
            let recorderError = error as? AudioRecorderError ?? .inputUnavailable
            logger.error(
                "Reconfiguration audio impossible: \(error.localizedDescription, privacy: .public)"
            )
            tearDownEngine()
            if shouldResume {
                isRecording = false
                captureBuffer.discard()
                lastRecordingDuration = 0
                onError?(recorderError)
            }
        }
    }

    private func refreshMicrophonePermission() {
        logMicrophonePermission()

        guard microphoneIsAuthorized else {
            if engine != nil {
                let wasRecording = isRecording
                isRecording = false
                captureBuffer.discard()
                lastRecordingDuration = 0
                tearDownEngine()
                if wasRecording {
                    onError?(.microphonePermissionRequired)
                }
            }
            return
        }

        guard !engineIsPrepared, !isRecording else { return }
        do {
            try prepareEngine()
        } catch {
            logger.error(
                "Préparation audio impossible: \(error.localizedDescription, privacy: .public)"
            )
            tearDownEngine()
        }
    }

    private func tearDownEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine?.stop()
        removeTap()
        engine?.reset()
        engine = nil
        engineIsPrepared = false
        logger.info("Moteur audio arrêté")
    }

    private func logMicrophonePermission() {
        let status = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: "non demandée"
        case .restricted: "restreinte"
        case .denied: "refusée"
        case .authorized: "autorisée"
        @unknown default: "inconnue"
        }
        logger.info("Permission microphone: \(status, privacy: .public)")
    }
}

private final class CaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var isCapturing = false
    private var levelHandler: AudioRecorder.LevelHandler?

    func setLevelHandler(_ handler: AudioRecorder.LevelHandler?) {
        lock.withLock { levelHandler = handler }
    }

    func beginCapture() {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            isCapturing = true
        }
    }

    func append(_ source: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }

        var sumOfSquares: Float = 0
        for index in 0..<count {
            let sample = source[index]
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(count))

        let handler: AudioRecorder.LevelHandler? = lock.withLock {
            guard isCapturing else { return nil }
            samples.append(contentsOf: UnsafeBufferPointer(start: source, count: count))
            return levelHandler
        }

        if let handler {
            DispatchQueue.main.async { handler(rms) }
        }
    }

    func finishCapture() -> [Float] {
        lock.withLock {
            isCapturing = false
            let result = samples
            samples.removeAll(keepingCapacity: true)
            return result
        }
    }

    func samples(since offset: Int) -> [Float] {
        lock.withLock {
            guard isCapturing, offset < samples.count else { return [] }
            return Array(samples[max(0, offset)...])
        }
    }

    func discard() {
        lock.withLock {
            isCapturing = false
            samples.removeAll(keepingCapacity: true)
        }
    }
}
