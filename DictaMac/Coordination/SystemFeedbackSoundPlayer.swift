import AppKit

@MainActor
final class SystemFeedbackSoundPlayer: FeedbackSoundPlaying {
    private enum SoundName {
        static let start = NSSound.Name("Tink")
        static let stop = NSSound.Name("Pop")
    }

    private let settings: any FeedbackSoundSettings

    init(settings: any FeedbackSoundSettings) {
        self.settings = settings
    }

    func playStart() {
        play(SoundName.start)
    }

    func playStop() {
        play(SoundName.stop)
    }

    private func play(_ name: NSSound.Name) {
        guard settings.isEnabled else { return }
        NSSound(named: name)?.play()
    }
}
