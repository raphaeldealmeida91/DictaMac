import Foundation

enum OverlayPresentation: Equatable {
    case recording
    case transcribing(String)
    case message(String)
    case error(String)
}

@MainActor
final class DictationOverlayModel: ObservableObject {
    @Published private(set) var presentation: OverlayPresentation = .recording
    @Published private(set) var levels = DictationOverlayModel.emptyLevels

    func startRecording() {
        levels = Self.emptyLevels
        presentation = .recording
    }

    func updateLevel(_ rms: Float) {
        guard presentation == .recording else { return }
        let decibels = Theme.Overlay.decibelMultiplier * log10(max(rms, Theme.Overlay.rmsFloor))
        let normalized = min(
            max((decibels - Theme.Overlay.decibelFloor) / -Theme.Overlay.decibelFloor, Theme.Overlay.levelFloor),
            Theme.Overlay.normalizedMaximum
        )
        levels.removeFirst()
        levels.append(normalized)
    }

    func showTranscribing(_ message: String) {
        presentation = .transcribing(message)
    }

    func showMessage(_ message: String) {
        presentation = .message(message)
    }

    func showError(_ message: String) {
        presentation = .error(message)
    }

    private static var emptyLevels: [Float] {
        Array(repeating: Theme.Overlay.levelFloor, count: Theme.Overlay.levelCount)
    }
}
