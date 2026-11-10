import SwiftUI

struct TranscribingPill: View {
    let message: String

    var body: some View {
        OverlayPillContainer {
            HStack(spacing: Theme.Overlay.itemSpacing) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}

#Preview("Transcription") {
    TranscribingPill(message: "Transcription…")
        .padding(Theme.Spacing.xLarge)
}
