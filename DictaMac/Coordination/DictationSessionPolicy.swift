import Foundation

struct DictationSessionPolicy {
    enum StopReason: Equatable {
        case released
        case maximumDuration
    }

    private(set) var state: DictationState = .idle
    private(set) var generation = 0
    private(set) var lastStopReason: StopReason?

    mutating func beginRecording() -> Int? {
        guard state == .idle else { return nil }
        generation += 1
        state = .recording
        lastStopReason = nil
        return generation
    }

    mutating func beginTranscription(for generation: Int, reason: StopReason) -> Bool {
        guard self.generation == generation, state == .recording else { return false }
        lastStopReason = reason
        state = .transcribing
        return true
    }

    mutating func beginInjection(for generation: Int) -> Bool {
        guard self.generation == generation, state == .transcribing else { return false }
        state = .injecting
        return true
    }

    @discardableResult
    mutating func cancel() -> Bool {
        guard state != .idle else { return false }
        generation += 1
        state = .idle
        lastStopReason = nil
        return true
    }

    mutating func complete(generation: Int) {
        guard self.generation == generation else { return }
        state = .idle
    }
}

enum RecordingDurationPreferences {
    static let maximumDurationKey = "recording.maximumDuration"
    static let defaultMaximumDuration: TimeInterval = 120
    static let allowedRange: ClosedRange<TimeInterval> = 10...600

    static var maximumDuration: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: maximumDurationKey)
        let value = stored > 0 ? stored : defaultMaximumDuration
        return min(max(value, allowedRange.lowerBound), allowedRange.upperBound)
    }
}
