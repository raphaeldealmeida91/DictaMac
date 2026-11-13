import SwiftUI

struct FirstLaunchAssistantView: View {
    @StateObject private var viewModel: FirstLaunchAssistantViewModel
    private let close: () -> Void

    init(viewModel: FirstLaunchAssistantViewModel, close: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 4)
            }
            Divider()
            completionHint
            navigation
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 420)
        .onAppear(perform: viewModel.appear)
        .onDisappear(perform: viewModel.disappear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bienvenue dans DictaMac")
                .font(.title.bold())
            Text("Étape \(viewModel.step.number) sur \(FirstLaunchStep.allCases.count) · \(viewModel.step.title)")
                .foregroundStyle(.secondary)
            ProgressView(value: Double(viewModel.step.number), total: Double(FirstLaunchStep.allCases.count))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let permission = viewModel.step.permission {
            permissionContent(permission)
        } else {
            readyToDictateContent
        }
    }

    private func permissionContent(_ permission: AppPermission) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(permission.title, systemImage: permissionSymbol(permission))
                .font(.title2.bold())
            Text(permissionExplanation(permission))
                .foregroundStyle(.secondary)
            permissionStatus(permission)
            HStack {
                Button("Autoriser") { viewModel.requestCurrentPermission() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.status(for: permission).isAuthorized)
                Button("Ouvrir Réglages Système") { viewModel.openCurrentPermissionSettings() }
                    .buttonStyle(.bordered)
            }
            Button("Ignorer pour l’instant") { viewModel.skipCurrentPermission() }
                .buttonStyle(.link)
        }
    }

    private func permissionStatus(_ permission: AppPermission) -> some View {
        let authorized = viewModel.status(for: permission).isAuthorized
        return Label(
            authorized ? "Autorisation accordée" : "Autorisation requise",
            systemImage: authorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(authorized ? Color.green : Color.orange)
    }

    private var readyToDictateContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            configurationRow
            modelRow
            cleanupModelRow
            dictationTrialRow
        }
    }

    private var configurationRow: some View {
        GroupBox("Touche 🌐/fn") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Dans Réglages Système → Clavier, choisissez « Ne rien faire » pour « Appuyer sur 🌐 pour ».")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ouvrir les réglages Clavier", action: viewModel.openKeyboardSettings)
                Toggle("Réglage effectué ou ignoré", isOn: $viewModel.fnConfigurationConfirmed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var modelRow: some View {
        GroupBox("Modèle Whisper") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Premier lancement : le téléchargement et la compilation peuvent prendre quelques minutes.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(viewModel.modelStatus)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = viewModel.modelProgress {
                    ProgressView(value: progress)
                } else if !viewModel.modelIsReady && !viewModel.modelSkipped {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("Continuer sans attendre le modèle", isOn: $viewModel.modelSkipped)
                    .disabled(viewModel.modelIsReady)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var dictationTrialRow: some View {
        GroupBox("Essai de dictée") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Maintenez fn, dites une courte phrase, puis relâchez fn.")
                Label(trialStatus, systemImage: viewModel.didObserveDictation ? "checkmark.circle.fill" : "waveform")
                    .foregroundStyle(viewModel.didObserveDictation ? Color.green : Color.secondary)
                Toggle("Terminer sans essai", isOn: $viewModel.dictationTrialSkipped)
                    .disabled(viewModel.didObserveDictation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var cleanupModelRow: some View {
        GroupBox("Nettoyage IA local") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pour corriger et reformuler vos dictées sans envoyer de texte dans le cloud, téléchargez le modèle local recommandé.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(viewModel.cleanupModelStatus)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = viewModel.cleanupModelProgress {
                    ProgressView(value: progress)
                }
                if !viewModel.cleanupModelIsReady && !viewModel.cleanupModelIsBusy {
                    Button("Télécharger le modèle de nettoyage", action: viewModel.downloadCleanupModel)
                        .buttonStyle(.borderedProminent)
                }
                Toggle("Continuer sans nettoyage IA", isOn: $viewModel.cleanupModelSkipped)
                    .disabled(viewModel.cleanupModelIsReady)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var trialStatus: String {
        switch viewModel.dictationState {
        case .idle: viewModel.didObserveDictation ? "Essai détecté" : "En attente d’un appui sur fn"
        case .recording: "Enregistrement détecté"
        case .transcribing: "Transcription en cours"
        case .injecting: "Insertion du texte en cours"
        }
    }

    private var navigation: some View {
        HStack {
            Button("Précédent", action: viewModel.goBack)
                .disabled(viewModel.step == .microphone)
            Spacer()
            if viewModel.step == .readyToDictate {
                Button("Terminer") {
                    if viewModel.finish() { close() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canFinish)
            } else {
                Button("Continuer", action: viewModel.continueForward)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canContinue)
            }
        }
    }

    @ViewBuilder
    private var completionHint: some View {
        if viewModel.step == .readyToDictate && !viewModel.canFinish {
            Text("Pour terminer, confirmez le réglage fn, choisissez si vous téléchargez le modèle de nettoyage, puis effectuez l’essai de dictée ou ignorez-le.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionSymbol(_ permission: AppPermission) -> String {
        switch permission {
        case .microphone: "mic.fill"
        case .inputMonitoring: "keyboard"
        case .accessibility: "hand.raised.fill"
        }
    }

    private func permissionExplanation(_ permission: AppPermission) -> String {
        switch permission {
        case .microphone: "DictaMac utilise le microphone uniquement pendant que vous maintenez fn."
        case .inputMonitoring: "Cet accès permet de détecter l’appui et le relâchement de fn."
        case .accessibility: "Cet accès permet de coller la transcription dans l’application active."
        }
    }
}
