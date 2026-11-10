import SwiftUI

struct OverlayPillContainer<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let tint: Color?
    @ViewBuilder let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .font(Theme.Typography.overlay)
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Overlay.horizontalPadding)
            .frame(width: Theme.Overlay.width, height: Theme.Overlay.height)
            .background {
                Capsule().fill(.regularMaterial)
                if let tint {
                    Capsule().fill(tint.opacity(Theme.Border.standardOpacity))
                }
            }
            .overlay {
                Capsule().stroke(
                    .primary.opacity(borderOpacity),
                    lineWidth: Theme.Border.width
                )
            }
            .shadow(
                color: .black.opacity(Theme.Shadow.colorOpacity),
                radius: Theme.Shadow.radius,
                y: Theme.Shadow.y
            )
    }

    private var borderOpacity: Double {
        contrast == .increased
            ? Theme.Border.increasedContrastOpacity
            : Theme.Border.standardOpacity
    }
}
