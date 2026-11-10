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
// Engine mutations run on controlQueue; callbacks and captured samples cross queues through safe wrappers.
final class AudioRecorder: AudioRecording, @unchecked Sendable {
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

    var lastRecordingDuration: TimeInterval {
        stateLock.withLock { storedRecordingDuration }
    }

    private var engine: AVAudioEngine?
    private let captureBuffer = CaptureBuffer()
    private let stateLock = NSLock()
    private let audioQueue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.audio-engine",
        qos: .userInitiated
    )
    private let configurationQueue = OperationQueue()
    private var configurationObserver: NSObjectProtocol?
    private var permissionObserver: NSObjectProtocol?
    private var applicationActiveObserver: NSObjectProtocol?
    private var isRecording = false
    private var tapIsInstalled = false
    private var engineIsPrepared = false
    private var isHandlingConfigurationChange = false
    private var storedRecordingDuration: TimeInterval = 0
    private let diagnosticLog: any DiagnosticLogging
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "AudioRecorder"
    )

    init(
        emergencyAudioRegistry: EmergencyAudioRegistry,
        diagnosticLog: any DiagnosticLogging
    ) {
        self.diagnosticLog = diagnosticLog
        configurationQueue.name = "com.raphaeldealmeida.DictaMac.audio-configuration"
        configurationQueue.maxConcurrentOperationCount = 1
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .microphonePermissionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMicrophonePermission()
        }
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMicrophonePermission()
        }

        refreshMicrophonePermission()
        emergencyAudioRegistry.install { [weak self] timeout in
            self?.emergencyStop(timeout: timeout) ?? true
        }
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
        guard microphoneIsAuthorized else {
            logMicrophonePermission()
            throw AudioRecorderError.microphonePermissionRequired
        }

        captureBuffer.beginCapture()
        stateLock.withLock { storedRecordingDuration = 0 }

        do {
            try audioQueue.sync {
                guard !isRecording else { throw AudioRecorderError.alreadyRecording }
                if !engineIsPrepared {
                    do {
                        try prepareEngine()
                    } catch {
                        tearDownEngine()
                        throw error
                    }
                }
                guard let engine else { throw AudioRecorderError.inputUnavailable }
                try engine.start()
                isRecording = true
                logger.info("Moteur audio démarré")
            }
        } catch {
            captureBuffer.discard()
            throw error
        }
    }

    /// Returns mono 16 kHz samples, or an empty array for captures too short to transcribe.
    func stop() -> [Float] {
        let samples = captureBuffer.finishCapture()
        let duration = Double(samples.count) / Self.sampleRate
        stateLock.withLock { storedRecordingDuration = duration }
        requestEngineStop()

        guard duration >= Self.minimumDuration else { return [] }
        return samples
    }

    private func requestEngineStop() {
        let completion = DispatchSemaphore(value: 0)
        audioQueue.async { [weak self] in
            guard let self else {
                completion.signal()
                return
            }
            self.isRecording = false
            self.engine?.stop()
            self.removeTap()
            self.engineIsPrepared = false
            self.logger.info("Moteur audio arrêté")
            completion.signal()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            if completion.wait(timeout: .now()) == .timedOut {
                self?.logger.fault("audio stop timeout=2.000s")
            }
        }
    }

    private func emergencyStop(timeout: TimeInterval) -> Bool {
        captureBuffer.discard()
        let completion = DispatchSemaphore(value: 0)
        audioQueue.async { [weak self] in
            guard let self else {
                completion.signal()
                return
            }
            self.isRecording = false
            self.engine?.stop()
            self.removeTap()
            self.engine?.reset()
            self.engine = nil
            self.engineIsPrepared = false
            completion.signal()
        }
        return completion.wait(timeout: .now() + timeout) == .success
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
            queue: configurationQueue
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func removeTap() {
        guard tapIsInstalled, let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapIsInstalled = false
    }

    private func handleConfigurationChange() {
        audioQueue.async { [weak self] in
            guard let self, !self.isHandlingConfigurationChange, let engine = self.engine else { return }
            self.isHandlingConfigurationChange = true
            defer { self.isHandlingConfigurationChange = false }

            let inputWasLost = self.isRecording
            self.isRecording = false
            if inputWasLost {
                self.logger.error("input_lost")
                self.diagnosticLog.inputLost()
                DispatchQueue.main.async { [weak self] in self?.onError?(.inputUnavailable) }
            }
            engine.stop()
            self.removeTap()
            engine.reset()
            self.engineIsPrepared = false

            guard !inputWasLost else {
                self.tearDownEngine()
                return
            }
            do {
                try self.prepareEngine()
            } catch {
                self.logger.error(
                    "Reconfiguration audio impossible: \(error.localizedDescription, privacy: .public)"
                )
                self.tearDownEngine()
            }
        }
    }

    private func refreshMicrophonePermission() {
        logMicrophonePermission()

        guard microphoneIsAuthorized else {
            audioQueue.async { [weak self] in
                guard let self, self.engine != nil else { return }
                let wasRecording = self.isRecording
                self.isRecording = false
                self.tearDownEngine()
                if wasRecording {
                    self.diagnosticLog.inputLost()
                    DispatchQueue.main.async { [weak self] in
                        self?.onError?(.microphonePermissionRequired)
                    }
                }
            }
            return
        }

        audioQueue.async { [weak self] in
            guard let self, !self.engineIsPrepared, !self.isRecording else { return }
            do {
                try self.prepareEngine()
            } catch {
                self.logger.error(
                    "Préparation audio impossible: \(error.localizedDescription, privacy: .public)"
                )
                self.tearDownEngine()
            }
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

// Samples, capture state, and the callback are accessed exclusively under lock.
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
