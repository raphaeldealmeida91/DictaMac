enum DiagnosticStage: String, Sendable {
    case modelLoad = "model_load"
    case recording
    case transcription
    case cleanup
    case injection
}
