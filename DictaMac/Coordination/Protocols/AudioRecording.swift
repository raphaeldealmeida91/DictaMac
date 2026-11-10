import Foundation

protocol AudioRecording: AnyObject, Sendable {
    var onLevelUpdate: (@MainActor @Sendable (Float) -> Void)? { get set }
    var onError: (@MainActor @Sendable (AudioRecorderError) -> Void)? { get set }
    var lastRecordingDuration: TimeInterval { get }

    func start() throws
    func stop() -> [Float]
    func capturedSamples(since offset: Int) -> [Float]
}
