import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.body.weight(.medium))
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.vertical, Theme.Spacing.small)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .stroke(.primary.opacity(borderOpacity), lineWidth: Theme.Border.width)
            }
            .opacity(
                configuration.isPressed
                    ? Theme.Interaction.secondaryPressedOpacity
                    : 1
            )
    }

    private var borderOpacity: Double {
        contrast == .increased
            ? Theme.Border.increasedContrastOpacity
            : Theme.Border.standardOpacity
    }
}

#Preview {
    Button("Annuler") {}
        .buttonStyle(SecondaryButtonStyle())
        .padding(Theme.Spacing.xLarge)
}
