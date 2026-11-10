import SwiftUI

struct GeneralSettingsView: View {
    @StateObject private var viewModel: GeneralSettingsViewModel
    private let openFirstLaunchAssistant: () -> Void

    init(
        viewModel: GeneralSettingsViewModel,
        openFirstLaunchAssistant: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.openFirstLaunchAssistant = openFirstLaunchAssistant
    }

    var body: some View {
        SettingsSectionContainer(title: "Général") {
            SettingsCard(
                title: "Comportement",
                footer: "Les appuis sur fn de moins de 300 ms et ceux reçus pendant une transcription sont ignorés."
            ) {
                SettingsRow(title: "Sons", description: "Confirme le début et la fin de l’enregistrement.") {
                    Toggle("", isOn: $viewModel.feedbackSoundsEnabled).labelsHidden()
                }
                Divider()
                SettingsRow(title: "Durée maximale", description: "Arrête automatiquement une dictée trop longue.") {
                    HStack(spacing: Theme.Spacing.small) {
                        Slider(
                            value: $viewModel.maximumRecordingDuration,
                            in: viewModel.recordingDurationRange,
                            step: Theme.Settings.durationStep
                        )
                        (Text(viewModel.maximumRecordingDuration, format: .number.precision(
                            .fractionLength(Theme.Settings.durationFractionDigits)
                        )) + Text(" s"))
                            .monospacedDigit()
                            .frame(width: Theme.Settings.valueWidth, alignment: .trailing)
                    }
                    .frame(width: Theme.Settings.controlWidth)
                }
                Divider()
                SettingsRow(title: "Lancer à l’ouverture de session", description: viewModel.launchAtLoginStatus) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { enabled in viewModel.setLaunchAtLoginEnabled(enabled) }
                    ))
                    .labelsHidden()
                }
            }

            SettingsCard(
                title: "Historique",
                footer: "Jusqu’à 20 dictées, stockées localement avec des permissions 0600 ; aucun texte n’est journalisé."
            ) {
                SettingsRow(title: "Conserver l’historique", description: "Affiche les dernières dictées dans le menu.") {
                    Toggle("", isOn: $viewModel.historyEnabled).labelsHidden()
                }
                Divider()
                SettingsRow(title: "Données enregistrées", description: viewModel.historyError) {
                    Button("Effacer", role: .destructive, action: viewModel.clearHistory)
                        .disabled(viewModel.historyIsEmpty)
                }
            }

            SettingsCard(
                title: "Arrêt d’urgence",
                footer: "Maintenez les modificateurs choisis. Sans sélection, ⌃⌥⌘ reste le raccourci de secours."
            ) {
                HStack(spacing: Theme.Spacing.xLarge) {
                    Toggle("⌃ Contrôle", isOn: $viewModel.emergencyUsesControl)
                    Toggle("⌥ Option", isOn: $viewModel.emergencyUsesOption)
                    Toggle("⌘ Commande", isOn: $viewModel.emergencyUsesCommand)
                }
            }

            SettingsCard(
                title: "Assistant de configuration",
                footer: "Revérifie les autorisations, la touche fn et le modèle Whisper."
            ) {
                SettingsRow(
                    title: "Premier lancement",
                    description: "Rouvrir le guide de mise en route."
                ) {
                    Button("Ouvrir l’assistant", action: openFirstLaunchAssistant)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            SettingsCard(title: "À propos") {
                SettingsRow(
                    title: "DictaMac",
                    description: viewModel.versionDescription
                ) {
                    Image(systemName: "mic.and.signal.meter")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .onAppear(perform: viewModel.appear)
    }
}

#Preview {
    GeneralSettingsView(viewModel: GeneralSettingsViewModel(
        store: InMemorySettingsStore(),
        launchAtLogin: PreviewLaunchAtLoginManager(),
        history: PreviewHistoryManager()
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
}
