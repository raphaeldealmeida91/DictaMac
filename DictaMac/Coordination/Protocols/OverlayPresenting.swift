@MainActor
protocol OverlayPresenting: AnyObject {
    func showRecording()
    func updateLevel(_ rms: Float)
    func showTranscribing(message: String)
    func showMessage(_ message: String)
    func showError(_ message: String)
    func hide()
}

extension OverlayPresenting {
    func showTranscribing() {
        showTranscribing(message: "Transcription…")
    }
}
