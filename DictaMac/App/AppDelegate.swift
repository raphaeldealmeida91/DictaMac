import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var terminationSignalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let showsInDock = UserDefaultsSettingsStore().bool(for: .appShowsInDock)
            ?? ApplicationPresence.defaultShowsInDock
        ApplicationPresence.apply(showsInDock: showsInDock)
        observeTerminationSignal()
        environment.start()
        environment.presentFirstLaunchAssistantIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        environment.stop()
    }

    /// Un SIGTERM (script d'installation, kill) doit quitter proprement, sinon le marqueur
    /// d'exécution reste en place et le prochain lancement démarre en mode sûr.
    private func observeTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignalSource = source
    }
}
