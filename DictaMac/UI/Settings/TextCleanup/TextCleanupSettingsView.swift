import SwiftUI

struct TextCleanupSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: TextCleanupSettingsViewModel

    init(viewModel: TextCleanupSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SettingsSectionContainer(title: "Nettoyage du texte") {
            SettingsCard(
                title: "Moteur",
                footer: "Choisissez le compromis entre rapidité, confidentialité et qualité."
            ) {
                Picker("Moteur", selection: $viewModel.engine) {
                    ForEach(TextCleanupEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                engineOptions
                    .transition(.opacity.combined(with: .scale(scale: Theme.Settings.sectionTransitionScale)))
                    .animation(reduceMotion ? nil : Theme.Motion.stateTransition, value: viewModel.engine)
            }
            if viewModel.engine == .local || viewModel.engine == .cloud {
                styleOptions
            }
        }
    }

    private var styleOptions: some View {
        SettingsCard(
            title: "Style",
            footer: "La correction préserve la formulation ; la rédaction soignée améliore aussi la structure."
        ) {
            Picker("Style", selection: $viewModel.cleanupStyle) {
                ForEach(CleanupStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            Text(viewModel.cleanupStyle.explanation)
                .font(Theme.Typography.description)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var engineOptions: some View {
        switch viewModel.engine {
        case .disabled:
            InfoCallout(kind: .information, message: "Le texte transcrit est inséré tel quel.")
        case .fast:
            fastOptions
        case .local:
            localOptions
        case .cloud:
            cloudOptions
        }
    }

    private var fastOptions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            InfoCallout(
                kind: .information,
                message: "Traitement local instantané : hésitations, répétitions, espaces, majuscule et ponctuation finale."
            )
            SettingsRow(title: "Mot isolé « genre »", description: "Le retire lorsqu’il constitue une hésitation seule.") {
                Toggle("", isOn: $viewModel.removeIsolatedGenre).labelsHidden()
            }
        }
    }

    private var localOptions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            InfoCallout(kind: .information, message: "Le modèle s’exécute localement ; aucune donnée ne quitte ce Mac.")
            SettingsRow(title: "Modèle local", description: "Le modèle léger convient mieux aux Mac avec peu de mémoire.") {
                Picker("Modèle local", selection: $viewModel.localModel) {
                    Text("Qwen 2.5 7B — qualité (~4,5 Go)")
                        .tag(StoredTextCleanupSettings.qualityLocalModel)
                    Text("Qwen 2.5 3B — recommandé (~1,74 Go)")
                        .tag(StoredTextCleanupSettings.defaultLocalModel)
                    Text("Qwen 2.5 1,5B — léger (~869 Mo)")
                        .tag(StoredTextCleanupSettings.lightLocalModel)
                }
                .labelsHidden()
                .frame(width: Theme.Settings.controlWidth)
            }
            SettingsRow(title: "Identifiant personnalisé", description: "Modèle Hugging Face compatible MLX.") {
                TextField(StoredTextCleanupSettings.defaultLocalModel, text: $viewModel.localModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Theme.Settings.controlWidth)
            }
            SettingsRow(title: "Délai maximal", description: "Au-delà, DictaMac applique les règles locales.") {
                HStack(spacing: Theme.Spacing.small) {
                    Slider(
                        value: $viewModel.localTimeout,
                        in: Theme.Settings.localTimeoutRange,
                        step: Theme.Settings.localTimeoutStep
                    )
                    (Text(viewModel.localTimeout, format: .number.precision(
                        .fractionLength(Theme.Settings.localTimeoutFractionDigits)
                    )) + Text(" s"))
                        .monospacedDigit()
                        .frame(width: Theme.Settings.valueWidth, alignment: .trailing)
                }
                .frame(width: Theme.Settings.controlWidth)
            }
            if viewModel.isLowMemoryMac {
                InfoCallout(
                    kind: .warning,
                    message: "Avec moins de 16 Go de mémoire, utilisez le modèle 1,5B pour limiter la pression mémoire."
                )
            }
            localModelStatus
        }
    }

    private var localModelStatus: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                StatusBadge(status: viewModel.modelBadge)
                Text(viewModel.modelStatus)
                    .font(Theme.Typography.description)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.modelIsBusy {
                    Button("Annuler", action: viewModel.cancelLocalModelDownload)
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Télécharger / charger", action: viewModel.loadLocalModel)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            if let progress = viewModel.downloadProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(height: Theme.Settings.progressHeight)
            }
            Text("Stockage local dans Application Support ; un téléchargement interrompu reprend les fichiers présents.")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cloudOptions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            InfoCallout(
                kind: .warning,
                message: "Le texte transcrit, jamais l’audio, est envoyé à OpenAI. En cas d’échec, les règles locales prennent le relais."
            )
            SettingsRow(title: "Modèle OpenAI", description: "Modèle utilisé pour reformuler la transcription.") {
                TextField(StoredTextCleanupSettings.defaultModel, text: $viewModel.cloudModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Theme.Settings.controlWidth)
            }
            SettingsRow(title: "Clé API", description: "Stockée uniquement dans le Keychain.") {
                SecureField("sk-…", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Theme.Settings.controlWidth)
            }
            SettingsRow(title: "Délai maximal", description: "Au-delà, DictaMac applique les règles locales.") {
                HStack(spacing: Theme.Spacing.small) {
                    Slider(
                        value: $viewModel.cloudTimeout,
                        in: Theme.Settings.localTimeoutRange,
                        step: Theme.Settings.localTimeoutStep
                    )
                    (Text(viewModel.cloudTimeout, format: .number.precision(
                        .fractionLength(Theme.Settings.localTimeoutFractionDigits)
                    )) + Text(" s"))
                        .monospacedDigit()
                        .frame(width: Theme.Settings.valueWidth, alignment: .trailing)
                }
                .frame(width: Theme.Settings.controlWidth)
            }
            HStack(spacing: Theme.Spacing.medium) {
                Spacer()
                Text(viewModel.apiKeyStatus)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                Button("Enregistrer", action: viewModel.saveAPIKey)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

#Preview {
    TextCleanupSettingsView(viewModel: TextCleanupSettingsViewModel(
        store: InMemorySettingsStore(values: [.textCleanupEngine: .string(TextCleanupEngine.local.rawValue)]),
        state: PreviewCleanupModelState(),
        manager: PreviewCleanupModelManager(),
        keyStore: PreviewAPIKeyStore(),
        recommendedLocalModel: StoredTextCleanupSettings.defaultLocalModel,
        isLowMemoryMac: false
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
}
