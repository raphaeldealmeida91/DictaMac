import AppKit

extension AppEnvironment {
    struct SelectionBundle {
        let watcher: SelectionWatcher
        let correctionService: any SelectionCorrectionService
        let coordinator: SelectionCorrectionCoordinator
    }

    static func makeSelectionBundle(
        settings: SettingsBundle,
        permissionReader: any AccessibilityPermissionReading,
        localGenerator: LocalCleanupModelManager
    ) -> SelectionBundle {
        let pasteboard = GeneralPasteboardProvider()
        let accessibilityReader = AccessibilitySelectedTextReader(permissionReader: permissionReader)
        let watcher = makeSelectionWatcher(
            settings: settings.selectionCorrection,
            accessibilityReader: accessibilityReader,
            pasteboard: pasteboard,
            permissionReader: permissionReader
        )
        let service = makeSelectionCorrectionService(
            selectionSettings: settings.selectionCorrection,
            cleanupSettings: settings.cleanup,
            localGenerator: localGenerator
        )
        let presenter = makeSelectionPresenter(
            accessibilityReader: accessibilityReader,
            permissionReader: permissionReader,
            pasteboard: pasteboard
        )
        let coordinator = SelectionCorrectionCoordinator(
            watcher: watcher,
            service: service,
            presenter: presenter,
            dictionary: settings.dictionary,
            activateCloud: {
                settings.selectionCorrection.setAllowsCloud(true)
                openSettings(section: .selectionCorrection)
            },
            loadLocalModel: {
                SafeModeState.setEnabled(false)
                Task { await localGenerator.approveDownloadAndActivate() }
                openSettings(section: .textCleanup)
            }
        )
        return SelectionBundle(watcher: watcher, correctionService: service, coordinator: coordinator)
    }

    private static func makeSelectionWatcher(
        settings: StoredSelectionCorrectionSettings,
        accessibilityReader: any SelectedTextReading,
        pasteboard: any PasteboardProviding,
        permissionReader: any AccessibilityPermissionReading
    ) -> SelectionWatcher {
        SelectionWatcher(
            eventMonitor: GlobalSelectionEventMonitor(),
            accessibilityReader: accessibilityReader,
            clipboardReader: ClipboardSelectedTextReader(
                pasteboard: pasteboard,
                sourceBundleIDProvider: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            ),
            settings: settings,
            ownBundleID: Bundle.main.bundleIdentifier,
            permissionReader: permissionReader
        )
    }

    static func makeSelectionCorrectionService(
        selectionSettings: StoredSelectionCorrectionSettings,
        cleanupSettings: StoredTextCleanupSettings,
        localGenerator: LocalCleanupModelManager
    ) -> ConfiguredSelectionCorrectionService {
        let endpoint = URL(string: "https://api.openai.com/v1/responses")
            ?? URL(fileURLWithPath: "/v1/responses")
        let cloudGenerator = OpenAIResponsesTextGenerator(
            endpoint: endpoint,
            apiKeyProvider: { try TextCleanupAPIKeyStore.load() },
            modelProvider: { cleanupSettings.configuredModel },
            requestTimeout: { cleanupSettings.cloudTimeout }
        )
        return ConfiguredSelectionCorrectionService(
            selectionSettings: selectionSettings,
            cleanupSettings: cleanupSettings,
            localGenerator: localGenerator,
            cloudGenerator: cloudGenerator,
            apiKeyProvider: { try TextCleanupAPIKeyStore.load() },
            activateLocalModel: { await localGenerator.activateConfiguredModel() }
        )
    }

    @MainActor
    private static func openSettings(section: SettingsSection) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openSettingsSection, object: section)
        }
    }

    private static func makeSelectionPresenter(
        accessibilityReader: any SelectedTextReading,
        permissionReader: any AccessibilityPermissionReading,
        pasteboard: any PasteboardProviding
    ) -> SelectionCorrectionPanelController {
        let injector = ClipboardTextInjector(permissionCache: permissionReader, pasteboard: pasteboard)
        let replacer = SelectionReplacer(
            selectionReader: accessibilityReader,
            injector: injector,
            pasteboard: pasteboard,
            frontmostBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        )
        let viewModel = SelectionCorrectionViewModel(
            replacer: replacer,
            clipboard: SelectionClipboardCopier(pasteboard: pasteboard)
        )
        return SelectionCorrectionPanelController(viewModel: viewModel)
    }
}
