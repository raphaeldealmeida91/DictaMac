import AppKit
import SwiftUI

struct SettingsView: View {
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var launchAtLogin = LaunchAtLoginService()
    @ObservedObject private var modelState = TranscriptionModelState.shared
    @ObservedObject private var cleanupModelState = LocalCleanupModelState.shared
    @ObservedObject private var diagnostics = DictationDiagnostics.shared
    @ObservedObject private var history = TranscriptionHistoryStore.shared
    #if DEBUG
    @ObservedObject private var benchmark = WhisperBenchmarkState.shared
    #endif

    @AppStorage(TranscriptionPreferences.modelKey)
    private var model = TranscriptionPreferences.recommendedModel
    @AppStorage(TranscriptionPreferences.automaticLanguageKey)
    private var automaticLanguage = false
    @AppStorage(TranscriptionPreferences.languageKey)
    private var language = "fr"
    @AppStorage(TranscriptionPreferences.vocabularyKey)
    private var vocabulary = ""
    @AppStorage(FeedbackSoundPreferences.enabledKey)
    private var feedbackSoundsEnabled = true
    @AppStorage(HistoryPreferences.enabledKey)
    private var historyEnabled = HistoryPreferences.defaultEnabled
    @AppStorage(RecordingDurationPreferences.maximumDurationKey)
    private var maximumRecordingDuration = RecordingDurationPreferences.defaultMaximumDuration
    @AppStorage(TextCleanupPreferences.engineKey)
    private var textCleanupEngine = TextCleanupEngine.fast.rawValue
    @AppStorage(TextCleanupPreferences.modelKey)
    private var textCleanupModel = TextCleanupPreferences.defaultModel
    @AppStorage(TextCleanupPreferences.localModelKey)
    private var localCleanupModel = TextCleanupPreferences.recommendedLocalModel
    @AppStorage(TextCleanupPreferences.removeIsolatedGenreKey)
    private var removeIsolatedGenre = true
    @AppStorage(TextCleanupPreferences.localTimeoutKey)
    private var localTimeout = TextCleanupPreferences.defaultLocalTimeout
    @State private var apiKey = ""
    @State private var apiKeyStatus: String?
    @AppStorage(EmergencyHotkeyPreferences.controlKey)
    private var emergencyUsesControl = true
    @AppStorage(EmergencyHotkeyPreferences.optionKey)
    private var emergencyUsesOption = true
    @AppStorage(EmergencyHotkeyPreferences.commandKey)
    private var emergencyUsesCommand = true

    init() {
        TextCleanupPreferences.migrate()
    }

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    transcriptionSettings
                    textCleanupSettings
                    generalSettings
                    permissionSettings
                }
                .padding(24)
            }
            .tabItem { Label("Réglages", systemImage: "gearshape") }

            diagnosticSettings
                .tabItem { Label("Diagnostic", systemImage: "gauge.with.dots.needle.67percent") }
        }
        .frame(width: 640, height: 720)
        .onAppear {
            permissions.startPeriodicRefresh()
            launchAtLogin.refresh()
            loadAPIKey()
        }
        .onDisappear {
            permissions.stopPeriodicRefresh()
        }
        .onChange(of: textCleanupEngine) { _, newValue in
            Task {
                if newValue == TextCleanupEngine.local.rawValue {
                    await LocalCleanupModelManager.shared.approveDownloadAndActivate()
                } else {
                    await LocalCleanupModelManager.shared.unload(reason: "Moteur local désactivé")
                }
            }
        }
    }

    private var textCleanupSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nettoyage du texte")
                .font(.title2.bold())

            Picker("Nettoyage du texte", selection: $textCleanupEngine) {
                ForEach(TextCleanupEngine.allCases) { engine in
                    Text(engine.title).tag(engine.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if textCleanupEngine == TextCleanupEngine.local.rawValue {
                Text("Aucune donnée ne quitte ton Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Modèle local", selection: $localCleanupModel) {
                    Text("Qwen 2.5 3B — recommandé (~1,74 Go)")
                        .tag(TextCleanupPreferences.defaultLocalModel)
                    Text("Qwen 2.5 1,5B — Mac moins puissants (~869 Mo)")
                        .tag(TextCleanupPreferences.lightLocalModel)
                }

                TextField("Identifiant Hugging Face configurable", text: $localCleanupModel)
                    .textFieldStyle(.roundedBorder)

                if TranscriptionPreferences.isLowMemoryMac {
                    Label(
                        "Ce Mac a moins de 16 Go de RAM : le modèle 1,5B est recommandé. Le 3B peut provoquer une forte pression mémoire.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack {
                    Text("Timeout")
                    Slider(value: $localTimeout, in: 0.5...10, step: 0.1)
                    Text("\(localTimeout, specifier: "%.1f") s")
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }

                if let progress = cleanupModelState.downloadProgress {
                    ProgressView(value: progress) {
                        Text(cleanupModelState.status)
                    } currentValueLabel: {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                    }
                } else {
                    Text(cleanupModelState.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(cleanupModelState.isBusy ? "Chargement…" : "Télécharger / charger") {
                        Task { await LocalCleanupModelManager.shared.approveDownloadAndActivate() }
                    }
                    .disabled(cleanupModelState.isBusy)
                    if cleanupModelState.isBusy {
                        Button("Annuler") {
                            Task { await LocalCleanupModelManager.shared.cancelDownload() }
                        }
                    }
                }
                Text("Stockage : ~/Library/Application Support/DictaMac/Models/Cleanup. Un téléchargement annulé reprend les fichiers déjà présents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if textCleanupEngine == TextCleanupEngine.fast.rawValue {
                Text("100 % local et instantané : hésitations, répétitions, espaces, majuscule et ponctuation finale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Supprimer « genre » lorsqu’il est isolé", isOn: $removeIsolatedGenre)
            } else if textCleanupEngine == TextCleanupEngine.cloud.rawValue {
                Text("Le texte transcrit (pas l’audio) est envoyé à OpenAI pour être nettoyé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Modèle")
                        TextField(TextCleanupPreferences.defaultModel, text: $textCleanupModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Clé API OpenAI")
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Button("Enregistrer la clé") { saveAPIKey() }
                    if let apiKeyStatus {
                        Text(apiKeyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("La clé est stockée dans le Keychain. En cas d’erreur ou après 3 secondes, DictaMac insère automatiquement le texte brut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("La dictée transcrite est insérée sans nettoyage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dernière dictée")
                    .font(.title2.bold())
                if let timings = diagnostics.lastTimings {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        diagnosticRow("Arrêt audio", timings.stopAudio)
                        diagnosticRow("Transcription", timings.transcription)
                        diagnosticRow("Nettoyage (\(timings.cleanupEngine.title))", timings.cleanup)
                        diagnosticRow("Injection", timings.injection)
                        Divider()
                        diagnosticRow("Total relâchement → collage", timings.total, emphasized: true)
                    }
                    Text(timings.date, format: .dateTime.day().month().hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Aucune mesure disponible.")
                        .foregroundStyle(.secondary)
                }

                Button("Ouvrir le dossier des journaux") {
                    if let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
                        NSWorkspace.shared.open(directory)
                    }
                }

                #if DEBUG
                Divider()
                HStack {
                    Text("Benchmark Whisper")
                        .font(.title2.bold())
                    Spacer()
                    Button("Choisir un WAV et lancer…") { benchmark.chooseWAVAndRun() }
                        .disabled(benchmark.isRunning)
                }
                Text(benchmark.status)
                    .foregroundStyle(.secondary)
                ForEach(benchmark.results) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(result.model).fontWeight(.semibold)
                            Spacer()
                            Text(result.duration, format: .number.precision(.fractionLength(3))) + Text(" s")
                        }
                        if let error = result.error {
                            Text(error).foregroundStyle(.red)
                        } else {
                            Text(result.text).textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                #endif
                Spacer()
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ title: String, _ seconds: TimeInterval, emphasized: Bool = false) -> some View {
        GridRow {
            Text(title).fontWeight(emphasized ? .bold : .regular)
            Text(seconds, format: .number.precision(.fractionLength(3))) + Text(" s")
                .fontWeight(emphasized ? .bold : .regular)
                .monospacedDigit()
        }
    }

    private func loadAPIKey() {
        do {
            apiKey = try TextCleanupAPIKeyStore.load() ?? ""
            apiKeyStatus = apiKey.isEmpty ? "Clé non configurée" : "Clé chargée depuis le Keychain"
        } catch {
            apiKeyStatus = error.localizedDescription
        }
    }

    private func saveAPIKey() {
        do {
            try TextCleanupAPIKeyStore.save(apiKey)
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            apiKeyStatus = apiKey.isEmpty ? "Clé supprimée" : "Clé enregistrée"
        } catch {
            apiKeyStatus = error.localizedDescription
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Général")
                .font(.title2.bold())

            Toggle("Jouer un son au début et à la fin de l’enregistrement", isOn: $feedbackSoundsEnabled)

            HStack {
                Text("Durée maximale d’enregistrement")
                Slider(
                    value: $maximumRecordingDuration,
                    in: RecordingDurationPreferences.allowedRange,
                    step: 10
                )
                Text("\(Int(maximumRecordingDuration)) s")
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Arrêt d’urgence global")
                HStack {
                    Toggle("⌃ Contrôle", isOn: $emergencyUsesControl)
                    Toggle("⌥ Option", isOn: $emergencyUsesOption)
                    Toggle("⌘ Commande", isOn: $emergencyUsesCommand)
                }
                Text("Maintenez simultanément les modificateurs sélectionnés. Si aucun n’est sélectionné, ⌃⌥⌘ reste utilisé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Conserver les 20 dernières dictées", isOn: $historyEnabled)

            HStack {
                Button("Effacer l’historique", role: .destructive) {
                    try? history.clear()
                }
                .disabled(history.entries.isEmpty)
                Text("Stocké localement avec des permissions 0600. Aucun texte n’est écrit dans les logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Les appuis sur fn de moins de 300 ms et les nouveaux appuis pendant une transcription sont ignorés.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Lancer au démarrage",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            if let statusMessage = launchAtLogin.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptionSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transcription")
                .font(.title2.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Modèle")
                    TextField(TranscriptionPreferences.defaultModel, text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Langue")
                    HStack {
                        TextField("fr", text: $language)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .disabled(automaticLanguage)
                        Toggle("Détection automatique", isOn: $automaticLanguage)
                    }
                }
            }

            if TranscriptionPreferences.isLowMemoryMac {
                Label(
                    "Ce Mac a moins de 16 Go de RAM : Whisper small est utilisé par défaut. Évite large-v3-turbo non quantifié.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Vocabulaire personnalisé (optionnel)")
                    .fontWeight(.medium)
                TextEditor(text: $vocabulary)
                    .font(.body)
                    .frame(height: 72)
                    .padding(5)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                Text("Séparez les mots ou expressions par une virgule ou un retour à la ligne.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let progress = modelState.downloadProgress {
                ProgressView(value: progress) {
                    Text(modelState.status)
                } currentValueLabel: {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                }
            } else {
                Text(modelState.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Appliquer et charger") {
                    Task {
                        try? await WhisperKitTranscriptionService.shared.reloadConfiguredModel()
                    }
                }
                .disabled(modelState.isBusy)

                Spacer()

                Text("Repli automatique : \(TranscriptionPreferences.fallbackModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Autorisations")
                .font(.title2.bold())

            Text("DictaMac a besoin de ces autorisations pour écouter le raccourci, enregistrer votre voix et insérer le texte transcrit.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(AppPermission.allCases.enumerated()), id: \.element.id) {
                    index, permission in
                    PermissionRow(
                        permission: permission,
                        status: permissions.status(for: permission),
                        onRequest: {
                            Task {
                                await permissions.request(permission)
                            }
                        },
                        onOpenSettings: {
                            permissions.openSystemSettings(for: permission)
                        }
                    )

                    if index < AppPermission.allCases.count - 1 {
                        Divider()
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

            Label {
                Text("Dans Réglages Système → Clavier, réglez « Appuyer sur 🌐 pour » sur « Ne rien faire » afin que la touche fn soit réservée à DictaMac.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
    let permission: AppPermission
    let status: PermissionStatus
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.isAuthorized ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .accessibilityLabel(status.isAuthorized ? "Autorisée" : "Non autorisée")

            Text(permission.title)
                .fontWeight(.medium)

            Spacer(minLength: 16)

            Button("Autoriser", action: onRequest)
                .disabled(status.isAuthorized)

            Button("Ouvrir les Réglages Système", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}
