import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusMessage = error.localizedDescription
        }
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Autorisation requise dans Réglages Système → Général → Ouverture."
        case .notFound:
            isEnabled = false
            statusMessage = "L’application doit être installée dans le dossier Applications."
        case .notRegistered:
            isEnabled = false
            statusMessage = nil
        @unknown default:
            isEnabled = false
            statusMessage = nil
        }
    }
}

enum FeedbackSoundPreferences {
    static let enabledKey = "feedbackSounds.enabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }
}
