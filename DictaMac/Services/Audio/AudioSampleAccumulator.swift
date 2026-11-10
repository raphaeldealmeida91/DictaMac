import Foundation

// Samples, capture state, and the callback are accessed exclusively under lock.
final class AudioSampleAccumulator: AudioSampleAccumulating, @unchecked Sendable {
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
        let rms = Self.rms(source: source, count: count)
        let handler = lock.withLock { () -> AudioRecorder.LevelHandler? in
            guard isCapturing else { return nil }
            samples.append(contentsOf: UnsafeBufferPointer(start: source, count: count))
            return levelHandler
        }
        if let handler { DispatchQueue.main.async { handler(rms) } }
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

    private static func rms(source: UnsafePointer<Float>, count: Int) -> Float {
        var sumOfSquares: Float = 0
        for index in 0..<count {
            let sample = source[index]
            sumOfSquares += sample * sample
        }
        return sqrt(sumOfSquares / Float(count))
    }
}
