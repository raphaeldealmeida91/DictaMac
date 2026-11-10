import Foundation

extension Notification.Name {
    static let emergencyStopRequested = Notification.Name("DictaMac.emergencyStopRequested")
}

enum EmergencyStage: String, Sendable {
    case finalTranscription = "final_transcription"
    case cleanup
    case injection
}
