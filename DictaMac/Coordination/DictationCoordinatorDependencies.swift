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
    let modelReadiness: any DictationModelReadinessProviding
    let cancellationRegistry: any EmergencyCancellationRegistering
    let diagnosticLog: any DiagnosticLogging
    let activityModel: AppActivityModel
    let frontmostApplicationName: () -> String?
}
