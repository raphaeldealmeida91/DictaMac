import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
            content
            if let footer {
                Text(footer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview {
    SettingsCard(title: "Transcription", footer: "Les modèles restent sur ce Mac.") {
        Text("Contenu de la section")
    }
    .padding(Theme.Spacing.xLarge)
}
