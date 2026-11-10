import SwiftUI

struct RecordingPill: View {
    let levels: [Float]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        OverlayPillContainer {
            HStack(spacing: Theme.Overlay.itemSpacing) {
                recordingDot
                waveform
                Text("Écoute…")
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enregistrement en cours")
    }

    private var recordingDot: some View {
        Circle()
            .fill(.red)
            .frame(
                width: Theme.Overlay.recordingDotSize,
                height: Theme.Overlay.recordingDotSize
            )
            .scaleEffect(
                isPulsing ? Theme.Overlay.recordingDotPulseScale : 1
            )
            .opacity(
                isPulsing ? Theme.Overlay.recordingDotMinimumOpacity : 1
            )
            .onAppear { updatePulse() }
            .onChange(of: reduceMotion) { _, _ in updatePulse() }
    }

    private var waveform: some View {
        HStack(spacing: Theme.Overlay.waveformBarSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.primary.opacity(Theme.Overlay.waveformOpacity))
                    .frame(
                        width: Theme.Overlay.waveformBarWidth,
                        height: max(
                            Theme.Overlay.waveformMinimumHeight,
                            CGFloat(level) * Theme.Overlay.waveformHeight
                        )
                    )
            }
        }
        .frame(width: Theme.Overlay.waveformWidth, height: Theme.Overlay.waveformHeight)
        .animation(reduceMotion ? nil : Theme.Motion.waveformResponse, value: levels)
    }

    private func updatePulse() {
        isPulsing = false
        guard !reduceMotion else { return }
        withAnimation(Theme.Motion.pulse) { isPulsing = true }
    }
}

#Preview("Enregistrement") {
    RecordingPill(levels: Theme.Overlay.previewLevels)
        .padding(Theme.Spacing.xLarge)
}
