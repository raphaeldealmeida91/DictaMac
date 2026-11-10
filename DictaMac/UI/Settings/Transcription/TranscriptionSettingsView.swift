import SwiftUI

struct TranscriptionSettingsView: View {
    @StateObject private var viewModel: TranscriptionSettingsViewModel

    init(viewModel: TranscriptionSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SettingsSectionContainer(title: "Transcription") {
            SettingsCard(
                title: "Modèle et langue",
                footer: "Le modèle de repli est \(viewModel.fallbackModel) si le modèle choisi ne peut pas être chargé."
            ) {
                SettingsRow(title: "Modèle Whisper", description: "Identifiant d’un modèle compatible WhisperKit.") {
                    TextField(StoredTranscriptionSettings.defaultModel, text: $viewModel.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Theme.Settings.controlWidth)
                }
                Divider()
                SettingsRow(title: "Langue", description: "Code de langue utilisé pour la transcription.") {
                    HStack(spacing: Theme.Spacing.medium) {
                        TextField("fr", text: $viewModel.language)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Theme.Settings.compactControlWidth)
                            .disabled(viewModel.automaticLanguage)
                        Toggle("Automatique", isOn: $viewModel.automaticLanguage)
                    }
                }
                if viewModel.isLowMemoryMac {
                    InfoCallout(
                        kind: .warning,
                        message: "Avec moins de 16 Go de mémoire, le modèle small est recommandé ; évitez large-v3-turbo non quantifié."
                    )
                }
            }

            SettingsCard(
                title: "Vocabulaire",
                footer: "Séparez les mots ou expressions par une virgule ou un retour à la ligne."
            ) {
                TextEditor(text: $viewModel.vocabulary)
                    .font(Theme.Typography.body)
                    .frame(height: Theme.Settings.editorHeight)
                    .padding(Theme.Spacing.small)
                    .background(.quaternary.opacity(Theme.Border.standardOpacity), in: RoundedRectangle(
                        cornerRadius: Theme.Radius.control
                    ))
            }

            SettingsCard(
                title: "État du modèle",
                footer: viewModel.loadError ?? "Le chargement et la transcription restent entièrement sur ce Mac."
            ) {
                HStack(spacing: Theme.Spacing.small) {
                    StatusBadge(status: viewModel.modelIsReady ? .ready : (viewModel.modelIsBusy ? .loading : .error))
                    Text(viewModel.modelStatus)
                        .font(Theme.Typography.description)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Appliquer et charger", action: viewModel.applyAndLoad)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(viewModel.modelIsBusy)
                }
                if let progress = viewModel.downloadProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(height: Theme.Settings.progressHeight)
                }
            }
        }
    }
}

#Preview {
    TranscriptionSettingsView(viewModel: TranscriptionSettingsViewModel(
        store: InMemorySettingsStore(),
        state: PreviewTranscriptionModelState(),
        loader: PreviewTranscriptionModelLoader(),
        recommendedModel: StoredTranscriptionSettings.defaultModel,
        isLowMemoryMac: false
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
}
