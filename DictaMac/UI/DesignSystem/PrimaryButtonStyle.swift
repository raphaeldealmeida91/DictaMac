import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.body.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.vertical, Theme.Spacing.small)
            .foregroundStyle(Color.white)
            .background(Color.accentColor.opacity(
                configuration.isPressed
                    ? Theme.Interaction.pressedOpacity
                    : 1
            ))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .animation(
                reduceMotion ? nil : .easeOut(duration: Theme.Motion.quickDuration),
                value: configuration.isPressed
            )
    }
}

#Preview {
    Button("Charger le modèle") {}
        .buttonStyle(PrimaryButtonStyle())
        .padding(Theme.Spacing.xLarge)
}
