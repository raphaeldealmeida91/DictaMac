@preconcurrency import AVFoundation
import Foundation
import OSLog

// Every AVAudioEngine mutation is confined to controlQueue.
final class AudioCaptureEngine: AudioCaptureEngineManaging, @unchecked Sendable {
    private static let tapBufferSize: AVAudioFrameCount = 1_024
    private static let stopTimeout: TimeInterval = 2

    private let sampleRate: Double
    private let sampleAccumulator: any AudioSampleAccumulating
    private let converterBuilder: any AudioSampleConverterBuilding
    private let controlQueue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.audio-engine",
        qos: .userInitiated
    )
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "AudioEngine"
    )
    private var engine: AVAudioEngine?
    private var isRecording = false
    private var tapIsInstalled = false
    private var engineIsPrepared = false
    private var isHandlingConfigurationChange = false

    init(
        sampleRate: Double,
        sampleAccumulator: any AudioSampleAccumulating,
        converterBuilder: any AudioSampleConverterBuilding = AVAudioSampleConverterBuilder()
    ) {
        self.sampleRate = sampleRate
        self.sampleAccumulator = sampleAccumulator
        self.converterBuilder = converterBuilder
    }

    func start() throws {
        try controlQueue.sync {
            guard !isRecording else { throw AudioRecorderError.alreadyRecording }
            if !engineIsPrepared { try prepareEngineOrTearDown() }
            guard let engine else { throw AudioRecorderError.inputUnavailable }
            sampleAccumulator.beginCapture()
            do {
                try engine.start()
                isRecording = true
                logger.info("Moteur audio démarré")
            } catch {
                sampleAccumulator.discard()
                throw error
            }
        }
    }

    func stop() {
        let completion = DispatchSemaphore(value: 0)
        controlQueue.async { [weak self] in
            self?.stopAndRemoveTap(reset: false)
            completion.signal()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.stopTimeout) {
            if completion.wait(timeout: .now()) == .timedOut {
                self.logger.fault("audio stop timeout=2.000s")
            }
        }
    }

    func prepareWhenIdle() {
        controlQueue.async { [weak self] in
            guard let self, !isRecording, !engineIsPrepared else { return }
            do { try prepareEngine() } catch { tearDownEngine() }
        }
    }

    func handleConfigurationChange(
        shouldPrepare: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        controlQueue.async { [weak self] in
            guard let self, !isHandlingConfigurationChange, engine != nil else { return }
            isHandlingConfigurationChange = true
            defer { isHandlingConfigurationChange = false }
            let inputWasLost = isRecording
            stopAndRemoveTap(reset: true)
            if shouldPrepare, !inputWasLost {
                do { try prepareEngine() } catch { tearDownEngine() }
            } else if inputWasLost {
                tearDownEngine()
            }
            completion(inputWasLost)
        }
    }

    func handlePermissionRevocation(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        controlQueue.async { [weak self] in
            guard let self, engine != nil else { return }
            let inputWasLost = isRecording
            tearDownEngine()
            completion(inputWasLost)
        }
    }

    func emergencyStop(timeout: TimeInterval) -> Bool {
        sampleAccumulator.discard()
        let completion = DispatchSemaphore(value: 0)
        controlQueue.async { [weak self] in
            self?.tearDownEngine()
            completion.signal()
        }
        return completion.wait(timeout: .now() + timeout) == .success
    }

    private func prepareEngineOrTearDown() throws {
        do { try prepareEngine() } catch {
            tearDownEngine()
            throw error
        }
    }

    private func prepareEngine() throws {
        let engine = engine ?? AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.inputUnavailable
        }
        guard let converter = converterBuilder.makeConverter(
            from: inputFormat,
            sampleRate: sampleRate
        ) else { throw AudioRecorderError.converterCreationFailed }
        installTap(on: inputNode, format: inputFormat, converter: converter)
        engine.prepare()
        engineIsPrepared = true
    }

    private func installTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        converter: any AudioSampleConverting
    ) {
        let accumulator = sampleAccumulator
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: format
        ) { inputBuffer, _ in
            converter.convert(inputBuffer, sink: accumulator)
        }
        tapIsInstalled = true
    }

    private func stopAndRemoveTap(reset: Bool) {
        isRecording = false
        engine?.stop()
        removeTap()
        if reset { engine?.reset() }
        engineIsPrepared = false
        logger.info("Moteur audio arrêté")
    }

    private func removeTap() {
        guard tapIsInstalled, let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapIsInstalled = false
    }

    private func tearDownEngine() {
        stopAndRemoveTap(reset: true)
        engine = nil
    }
}
