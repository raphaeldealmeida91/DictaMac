import Foundation

struct DictationSessionPolicy {
    enum StopReason: Equatable {
        case released
        case maximumDuration
        case inputLost
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
