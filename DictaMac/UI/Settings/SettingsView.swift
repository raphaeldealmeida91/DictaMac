import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsSection? = .general
    private let generalViewModel: GeneralSettingsViewModel
    private let transcriptionViewModel: TranscriptionSettingsViewModel
    private let textCleanupViewModel: TextCleanupSettingsViewModel
    private let dictionaryViewModel: DictionarySettingsViewModel
    private let permissionsViewModel: PermissionsSettingsViewModel
    private let diagnosticViewModel: DiagnosticSettingsViewModel
    private let firstLaunchAssistant: FirstLaunchAssistantController

    init(environment: AppEnvironment) {
        firstLaunchAssistant = environment.firstLaunchAssistant
        generalViewModel = GeneralSettingsViewModel(
            store: environment.settingsStore,
            launchAtLogin: environment.launchAtLogin,
            history: environment.history
        )
        transcriptionViewModel = TranscriptionSettingsViewModel(
            store: environment.settingsStore,
            state: environment.transcriptionState,
            loader: environment.transcriptionService,
            recommendedModel: environment.transcriptionSettings.recommendedModel,
            isLowMemoryMac: environment.transcriptionSettings.isLowMemoryMac
        )
        textCleanupViewModel = TextCleanupSettingsViewModel(
            store: environment.settingsStore,
            state: environment.cleanupModelState,
            manager: environment.localModelManager,
            keyStore: environment.apiKeyStore,
            recommendedLocalModel: environment.textCleanupSettings.recommendedLocalModel,
            isLowMemoryMac: environment.transcriptionSettings.isLowMemoryMac
        )
        dictionaryViewModel = DictionarySettingsViewModel(dictionary: environment.personalDictionary)
        permissionsViewModel = PermissionsSettingsViewModel(manager: environment.permissions)
        #if DEBUG
        diagnosticViewModel = DiagnosticSettingsViewModel(
            diagnostics: environment.diagnostics,
            logOpener: environment.diagnosticLogOpener,
            benchmark: environment.benchmarkState
        )
        #else
        diagnosticViewModel = DiagnosticSettingsViewModel(
            diagnostics: environment.diagnostics,
            logOpener: environment.diagnosticLogOpener
        )
        #endif
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(Theme.Settings.sidebarWidth)
        } detail: {
            selectedSection
        }
        .frame(
            minWidth: Theme.Settings.windowWidth,
            idealWidth: Theme.Settings.windowWidth,
            minHeight: Theme.Settings.windowHeight,
            idealHeight: Theme.Settings.windowHeight
        )
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsView(
                viewModel: generalViewModel,
                openFirstLaunchAssistant: environmentAction
            )
        case .transcription:
            TranscriptionSettingsView(viewModel: transcriptionViewModel)
        case .textCleanup:
            TextCleanupSettingsView(viewModel: textCleanupViewModel)
        case .dictionary:
            DictionarySettingsView(viewModel: dictionaryViewModel)
        case .permissions:
            PermissionsSettingsView(viewModel: permissionsViewModel)
        case .diagnostic:
            DiagnosticSettingsView(viewModel: diagnosticViewModel)
        }
    }

    private var environmentAction: () -> Void {
        { firstLaunchAssistant.present() }
    }

}
