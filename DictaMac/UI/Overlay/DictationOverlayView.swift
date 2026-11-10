import SwiftUI

struct DictationOverlayView: View {
    @ObservedObject var model: DictationOverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.presentation {
            case .recording:
                RecordingPill(levels: model.levels)
                    .transition(transition)
            case .transcribing(let message):
                TranscribingPill(message: message)
                    .transition(transition)
            case .message(let message):
                MessagePill(kind: .message, message: message)
                    .transition(transition)
            case .error(let message):
                MessagePill(kind: .error, message: message)
                    .transition(transition)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.stateTransition, value: model.presentation)
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .opacity.combined(with: .scale(scale: Theme.Overlay.transitionScale))
    }
}
