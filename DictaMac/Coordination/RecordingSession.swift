import Foundation
import OSLog

protocol SegmentedTranscribing: Sendable {
    func append(_ samples: [Float]) async
    func prepareForFinalTranscription() async throws
    func finishWithBudget(
        completeAudio: [Float],
        budget: TimeInterval?
    ) async throws -> SegmentedTranscriber.FinishResult
    func cancel() async
}

extension SegmentedTranscribing {
    func prepareForFinalTranscription() async throws {}
}

struct RecordingSessionResult {
    let samples: [Float]
    let duration: TimeInterval
    let transcriber: any SegmentedTranscribing
}

@MainActor
protocol RecordingSessionManaging: AnyObject {
    var cancellationHandlers: [@Sendable () -> Void] { get }

    func start() throws
    func finish() -> RecordingSessionResult
    func cancel()
}

@MainActor
protocol RecordingSessionBuilding: AnyObject {
    func makeSession(
        onMaximumDuration: @escaping @MainActor () -> Void
    ) -> any RecordingSessionManaging
}

@MainActor
final class RecordingSession: RecordingSessionManaging {
    typealias PostRollWaiter = @MainActor (TimeInterval) -> Void

    private enum Constants {
        static let audioFeedPeriod = Duration.milliseconds(50)
        static let postRollDuration: TimeInterval = 0.15
    }

    private let audioRecorder: any AudioRecording
    private let transcriber: any SegmentedTranscribing
    private let maximumDuration: TimeInterval
    private let onMaximumDuration: @MainActor () -> Void
    private let postRollWaiter: PostRollWaiter
    private var audioFeedTask: Task<Void, Never>?
    private var maximumDurationTask: Task<Void, Never>?
    private var isRecording = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "RecordingSession"
    )

    init(
        audioRecorder: any AudioRecording,
        transcriber: any SegmentedTranscribing,
        maximumDuration: TimeInterval,
        onMaximumDuration: @escaping @MainActor () -> Void,
        postRollWaiter: @escaping PostRollWaiter = { duration in
            Thread.sleep(forTimeInterval: duration)
        }
    ) {
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.maximumDuration = maximumDuration
        self.onMaximumDuration = onMaximumDuration
        self.postRollWaiter = postRollWaiter
    }

    func start() throws {
        try audioRecorder.start()
        isRecording = true
        startAudioFeed()
        startMaximumDurationTimer()
    }

    func finish() -> RecordingSessionResult {
        cancelTasks()
        postRollWaiter(Constants.postRollDuration)
        isRecording = false
        return RecordingSessionResult(
            samples: audioRecorder.stop(),
            duration: audioRecorder.lastRecordingDuration,
            transcriber: transcriber
        )
    }

    func cancel() {
        cancelTasks()
        if isRecording {
            isRecording = false
            _ = audioRecorder.stop()
        }
        let transcriber = transcriber
        Task { await transcriber.cancel() }
    }

    var cancellationHandlers: [@Sendable () -> Void] {
        [audioFeedTask, maximumDurationTask].compactMap { task -> (@Sendable () -> Void)? in
            guard let task else { return nil }
            return { @Sendable in task.cancel() }
        }
    }

    private func startAudioFeed() {
        audioFeedTask = Task { [weak self] in
            var deliveredSampleCount = 0
            do {
                while !Task.isCancelled {
                    try await ContinuousClock().sleep(for: Constants.audioFeedPeriod)
                    guard let self else { return }
                    let samples = self.audioRecorder.capturedSamples(since: deliveredSampleCount)
                    deliveredSampleCount += samples.count
                    await self.transcriber.append(samples)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.logger.warning(
                    "Alimentation de la transcription incrémentale interrompue: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func startMaximumDurationTimer() {
        maximumDurationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.maximumDuration))
                guard !Task.isCancelled else { return }
                self.onMaximumDuration()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func cancelTasks() {
        audioFeedTask?.cancel()
        audioFeedTask = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
    }
}

@MainActor
final class DefaultRecordingSessionFactory: RecordingSessionBuilding {
    private let audioRecorder: any AudioRecording
    private let transcriptionService: any TranscriptionService
    private let transcriptionSettings: any TranscriptionSettings
    private let recordingSettings: any RecordingSettings
    private let wordDiagnostics: any TextWordDiagnosticsRecording

    init(
        audioRecorder: any AudioRecording,
        transcriptionService: any TranscriptionService,
        transcriptionSettings: any TranscriptionSettings,
        recordingSettings: any RecordingSettings,
        wordDiagnostics: any TextWordDiagnosticsRecording
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionService = transcriptionService
        self.transcriptionSettings = transcriptionSettings
        self.recordingSettings = recordingSettings
        self.wordDiagnostics = wordDiagnostics
    }

    func makeSession(
        onMaximumDuration: @escaping @MainActor () -> Void
    ) -> any RecordingSessionManaging {
        wordDiagnostics.beginWordDiagnostics()
        return RecordingSession(
            audioRecorder: audioRecorder,
            transcriber: SegmentedTranscriber(
                transcriptionService: transcriptionService,
                language: transcriptionSettings.configuredLanguage,
                wordDiagnostics: wordDiagnostics
            ),
            maximumDuration: recordingSettings.maximumDuration,
            onMaximumDuration: onMaximumDuration
        )
    }
}
