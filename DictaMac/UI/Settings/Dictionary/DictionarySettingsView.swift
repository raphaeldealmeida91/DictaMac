import SwiftUI

struct DictionarySettingsView: View {
    @StateObject private var viewModel: DictionarySettingsViewModel

    init(viewModel: DictionarySettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SettingsSectionContainer(title: "Dictionnaire") {
            InfoCallout(
                kind: .information,
                message: "Les formes correctes guident Whisper et sont respectées par le nettoyage du texte."
            )
            SettingsCard(
                title: "Termes personnels",
                footer: "Indiquez les erreurs de reconnaissance connues en les séparant par des virgules."
            ) {
                entries
                actions
            }
        }
        .onAppear(perform: viewModel.reload)
    }

    private var entries: some View {
        VStack(spacing: Theme.Spacing.small) {
            ForEach($viewModel.drafts) { $draft in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                    TextField("Forme correcte", text: $draft.canonical)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Theme.Settings.dictionaryTermWidth)
                    TextField("Variantes", text: $draft.variants)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        viewModel.removeEntry(id: draft.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Supprimer \(draft.canonical)")
                }
                if draft.id != viewModel.drafts.last?.id { Divider() }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.small) {
            Button("Ajouter", systemImage: "plus", action: viewModel.addEntry)
                .buttonStyle(SecondaryButtonStyle())
            Button("Importer…", action: viewModel.importJSON)
                .buttonStyle(SecondaryButtonStyle())
            Button("Exporter…", action: viewModel.exportJSON)
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Enregistrer", action: viewModel.save)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, Theme.Spacing.small)
    }
}

#Preview {
    DictionarySettingsView(viewModel: DictionarySettingsViewModel(
        dictionary: PreviewPersonalDictionary(),
        fileManager: PreviewDictionaryFileManager()
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
}
