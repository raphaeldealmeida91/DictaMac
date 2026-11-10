import Foundation

@MainActor
struct DictationCoordinatorDependencies {
    let hotkeyProvider: any HotkeyProviding
    let audioRecorder: any AudioRecording
    let overlayPresenter: any OverlayPresenting
    let feedbackSoundPlayer: any FeedbackSoundPlaying
    let recordingSessionFactory: any RecordingSessionBuilding
    let pipeline: any DictationPipelineRunning
    let stageReporter: any DictationStageReporting
    let modelPreparer: any DictationModelPreparing
    let cancellationRegistry: any EmergencyCancellationRegistering
    let activityModel: AppActivityModel
    let frontmostApplicationName: () -> String?
}
