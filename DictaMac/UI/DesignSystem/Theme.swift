import SwiftUI

enum Theme {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let callout: CGFloat = 10
    }

    enum Typography {
        static let sectionTitle: Font = .headline
        static let rowTitle: Font = .body.weight(.medium)
        static let body: Font = .body
        static let description: Font = .subheadline
        static let caption: Font = .caption
        static let overlay: Font = .callout.weight(.medium)
    }

    enum Motion {
        static let quickDuration: TimeInterval = 0.16
        static let standardDuration: TimeInterval = 0.24
        static let pulseDuration: TimeInterval = 0.9
        static let waveformResponse = Animation.spring(response: 0.22, dampingFraction: 0.76)
        static let stateTransition = Animation.easeInOut(duration: standardDuration)
        static let pulse = Animation.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
    }

    enum Border {
        static let width: CGFloat = 0.5
        static let standardOpacity = 0.14
        static let increasedContrastOpacity = 0.34
    }

    enum Interaction {
        static let pressedOpacity = 0.8
        static let secondaryPressedOpacity = 0.72
    }

    enum Shadow {
        static let colorOpacity = 0.12
        static let radius: CGFloat = 4
        static let y: CGFloat = 1
    }

    enum Overlay {
        static let width: CGFloat = 208
        static let height: CGFloat = 44
        static let panelWidth: CGFloat = 216
        static let panelHeight: CGFloat = 52
        static let bottomInset: CGFloat = 28
        static let horizontalPadding = Spacing.large
        static let itemSpacing = Spacing.small
        static let recordingDotSize: CGFloat = 8
        static let recordingDotMinimumOpacity = 0.55
        static let recordingDotPulseScale: CGFloat = 1.18
        static let waveformWidth: CGFloat = 48
        static let waveformHeight: CGFloat = 22
        static let waveformBarWidth: CGFloat = 2
        static let waveformBarSpacing: CGFloat = 2
        static let waveformMinimumHeight: CGFloat = 3
        static let waveformOpacity = 0.78
        static let levelFloor: Float = 0.08
        static let levelCount = 12
        static let decibelFloor: Float = -55
        static let decibelMultiplier: Float = 20
        static let normalizedMaximum: Float = 1
        static let rmsFloor: Float = 0.000_001
        static let messageDisplayDuration = Duration.seconds(2)
        static let transitionScale = 0.97
        static let previewLevels: [Float] = [
            0.1, 0.2, 0.45, 0.8, 0.55, 0.3, 0.7, 1, 0.6, 0.35, 0.2, 0.1
        ]
    }

    enum Settings {
        static let windowWidth: CGFloat = 720
        static let windowHeight: CGFloat = 520
        static let sidebarWidth: CGFloat = 190
        static let contentMaximumWidth: CGFloat = 620
        static let controlWidth: CGFloat = 260
        static let compactControlWidth: CGFloat = 96
        static let valueWidth: CGFloat = 56
        static let editorHeight: CGFloat = 76
        static let dictionaryTermWidth: CGFloat = 160
        static let progressHeight: CGFloat = 3
        static let durationStep: Double = 10
        static let localTimeoutRange = 0.5...10.0
        static let localTimeoutStep = 0.1
        static let localTimeoutFractionDigits = 1
        static let durationFractionDigits = 0
        static let timingFractionDigits = 3
        static let percentFractionDigits = 0
        static let sectionTransitionScale = 0.99
    }

    enum MenuBar {
        static let width: CGFloat = 340
        static let historyRowHeight: CGFloat = 48
        static let historyLimit = 6
        static let historyWordLimit = 24
        static let copiedFeedbackDuration = Duration.seconds(1.4)
        static let statusDotSize: CGFloat = 7
    }
}
