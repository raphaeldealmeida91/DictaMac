import Foundation

protocol AudioSampleAccumulating: Sendable {
    func setLevelHandler(_ handler: AudioRecorder.LevelHandler?)
    func beginCapture()
    func append(_ source: UnsafePointer<Float>, count: Int)
    func finishCapture() -> [Float]
    func samples(since offset: Int) -> [Float]
    func discard()
}
