import Foundation
import OSLog

/// Incrementally transcribes overlapping audio windows while keeping the
/// underlying `TranscriptionService` unaware of segmentation.
actor SegmentedTranscriber {
    struct Configuration: Sendable {
        let sampleRate: Int
        let segmentDuration: TimeInterval
        let overlapDuration: TimeInterval
        let maximumBacklog: Int

        init(
            sampleRate: Int,
            segmentDuration: TimeInterval,
            overlapDuration: TimeInterval,
            maximumBacklog: Int = 3
        ) {
            self.sampleRate = sampleRate
            self.segmentDuration = segmentDuration
            self.overlapDuration = overlapDuration
            self.maximumBacklog = max(1, maximumBacklog)
        }

        static let standard = Configuration(
            sampleRate: 16_000,
            segmentDuration: 4,
            overlapDuration: 0.5,
            maximumBacklog: 3
        )

        var segmentSampleCount: Int {
            max(1, Int((Double(sampleRate) * segmentDuration).rounded()))
        }

        var overlapSampleCount: Int {
            min(
                segmentSampleCount - 1,
                max(0, Int((Double(sampleRate) * overlapDuration).rounded()))
            )
        }

        var strideSampleCount: Int { segmentSampleCount - overlapSampleCount }
    }

    private struct TranscribedSegment: Sendable {
        let index: Int
        let text: String
    }

    private let transcriptionService: any TranscriptionService
    private let language: String?
    private let configuration: Configuration
    private var audio: [Float] = []
    private var segments: [TranscribedSegment] = []
    private var nextSegmentStart = 0
    private var nextSegmentIndex = 0
    private var worker: Task<Void, Never>?
    private var segmentFailed = false
    private var backlogExceeded = false
    private var isCancelled = false
    private var isFinishing = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "IncrementalTranscription"
    )

    init(
        transcriptionService: any TranscriptionService,
        language: String?,
        configuration: Configuration = .standard
    ) {
        self.transcriptionService = transcriptionService
        self.language = language
        self.configuration = configuration
    }

    /// Adds newly captured, contiguous samples and starts any complete segment.
    func append(_ samples: [Float]) {
        guard !samples.isEmpty, !isCancelled, !isFinishing else { return }
        audio.append(contentsOf: samples)
        if pendingCompleteSegmentCount > configuration.maximumBacklog {
            backlogExceeded = true
            logger.warning(
                "incremental backlog exceeded limit=\(self.configuration.maximumBacklog); intermediate segments dropped"
            )
        }
        startWorkerIfNeeded()
    }

    /// Finishes incremental work and transcribes only the overlapping tail.
    /// `completeAudio` replaces the accumulated stream to close any capture race.
    func finish(completeAudio: [Float]) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }

            if backlogExceeded {
                return try await transcribeCompleteAudio(reason: "backlog_exceeded")
            }

            isFinishing = true
            audio = completeAudio
            startWorkerIfNeeded()
            if let worker {
                await worker.value
            }

            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }

            if segmentFailed {
                return try await transcribeCompleteAudio(reason: "segment_error")
            }

            // Preserve the original single-pass behavior for short dictations.
            guard completeAudio.count >= configuration.segmentSampleCount else {
                return try await transcribeCompleteAudio(reason: "short_dictation")
            }

            var completed = segments.sorted { $0.index < $1.index }
            if nextSegmentStart < completeAudio.count {
                let finalSamples = Array(completeAudio[nextSegmentStart...])
                let finalIndex = nextSegmentIndex
                let start = ContinuousClock.now
                do {
                    let text = try await transcriptionService.transcribe(
                        finalSamples,
                        language: language
                    )
                    let elapsed = Self.seconds(start.duration(to: .now))
                    logger.info(
                        "incremental segment index=\(finalIndex) phase=final audio=\(Double(finalSamples.count) / Double(self.configuration.sampleRate), format: .fixed(precision: 3))s duration=\(elapsed, format: .fixed(precision: 3))s"
                    )
                    completed.append(TranscribedSegment(index: finalIndex, text: text))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.warning(
                        "incremental final segment failed; full fallback error=\(error.localizedDescription, privacy: .public)"
                    )
                    return try await transcribeCompleteAudio(reason: "final_segment_error")
                }
            }

            return Self.assemble(completed.map(\.text))
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        worker?.cancel()
        logger.debug("incremental transcription cancelled")
    }

    static func assemble(_ texts: [String]) -> String {
        var assembled: [String] = []

        for text in texts {
            let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }
            guard !assembled.isEmpty else {
                assembled = words
                continue
            }

            let maximumOverlap = min(assembled.count, words.count)
            var overlap = 0
            if maximumOverlap > 0 {
                for candidate in stride(from: maximumOverlap, through: 1, by: -1) {
                    let suffix = assembled.suffix(candidate).map(Self.comparableWord)
                    let prefix = words.prefix(candidate).map(Self.comparableWord)
                    if suffix == prefix {
                        overlap = candidate
                        break
                    }
                }
            }
            if overlap > 0, let incomingBoundary = words.prefix(overlap).last {
                assembled[assembled.count - 1] = Self.mergingBoundaryPunctuation(
                    existing: assembled[assembled.count - 1],
                    incoming: incomingBoundary
                )
            }
            assembled.append(contentsOf: words.dropFirst(overlap))
        }

        return assembled.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startWorkerIfNeeded() {
        guard worker == nil,
              !isCancelled,
              !segmentFailed,
              !backlogExceeded,
              hasCompleteSegment else { return }

        worker = Task { [weak self] in
            await self?.runWorker()
        }
    }

    private var hasCompleteSegment: Bool {
        audio.count >= nextSegmentStart + configuration.segmentSampleCount
    }

    private var pendingCompleteSegmentCount: Int {
        guard hasCompleteSegment else { return 0 }
        return 1 + (audio.count - nextSegmentStart - configuration.segmentSampleCount)
            / configuration.strideSampleCount
    }

    private func runWorker() async {
        while !isCancelled, !segmentFailed, !backlogExceeded, hasCompleteSegment {
            let startOffset = nextSegmentStart
            let endOffset = startOffset + configuration.segmentSampleCount
            let samples = Array(audio[startOffset..<endOffset])
            let index = nextSegmentIndex
            nextSegmentStart += configuration.strideSampleCount
            nextSegmentIndex += 1

            let start = ContinuousClock.now
            do {
                let text = try await transcriptionService.transcribe(samples, language: language)
                let elapsed = Self.seconds(start.duration(to: .now))
                segments.append(TranscribedSegment(index: index, text: text))
                logger.info(
                    "incremental segment index=\(index) phase=streaming audio=\(Double(samples.count) / Double(self.configuration.sampleRate), format: .fixed(precision: 3))s duration=\(elapsed, format: .fixed(precision: 3))s"
                )
            } catch is CancellationError {
                isCancelled = true
                break
            } catch {
                segmentFailed = true
                logger.warning(
                    "incremental segment failed index=\(index) duration=\(Self.seconds(start.duration(to: .now)), format: .fixed(precision: 3))s error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        worker = nil
    }

    private func transcribeCompleteAudio(reason: String) async throws -> String {
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let text = try await transcriptionService.transcribe(audio, language: language)
        let elapsed = Self.seconds(start.duration(to: .now))
        logger.info(
            "incremental full transcription reason=\(reason, privacy: .public) audio=\(Double(self.audio.count) / Double(self.configuration.sampleRate), format: .fixed(precision: 3))s duration=\(elapsed, format: .fixed(precision: 3))s"
        )
        return text
    }

    private static func comparableWord(_ word: String) -> String {
        word
            .trimmingCharacters(in: .punctuationCharacters)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func mergingBoundaryPunctuation(existing: String, incoming: String) -> String {
        let existingBase = existing.dropLast(existing.reversed().prefix(while: Self.isPunctuation).count)
        let incomingSuffix = incoming.reversed().prefix(while: Self.isPunctuation).reversed()
        return String(existingBase) + String(incomingSuffix)
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
