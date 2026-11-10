import SwiftUI

struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let control: Control

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.large) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                if let description {
                    Text(description)
                        .font(Theme.Typography.description)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.large)
            control
        }
        .padding(.vertical, Theme.Spacing.small)
    }
}

#Preview {
    SettingsRow(title: "Lancer au démarrage", description: "Ouvre DictaMac à la connexion.") {
        Toggle("", isOn: .constant(true)).labelsHidden()
    }
    .padding(Theme.Spacing.xLarge)
}
