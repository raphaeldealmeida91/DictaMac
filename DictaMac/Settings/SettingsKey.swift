import Foundation

enum SettingsKey: String, Sendable {
    case transcriptionModel = "transcription.model"
    case transcriptionAutomaticLanguage = "transcription.automaticLanguage"
    case transcriptionLanguage = "transcription.language"
    case transcriptionStoredModelPaths = "transcription.storedModelPaths"

    case personalDictionaryPath = "dictionary.path"

    case legacyTextCleanupEnabled = "textCleanup.enabled"
    case textCleanupEngine = "textCleanup.engine"
    case textCleanupModel = "textCleanup.model"
    case textCleanupLocalModel = "textCleanup.localModel"
    case textCleanupStyle = "textCleanup.style"
    case textCleanupLocalDownloadApproved = "textCleanup.localDownloadApproved"
    case textCleanupRemoveIsolatedGenre = "textCleanup.fast.removeIsolatedGenre"
    case textCleanupLocalTimeout = "textCleanup.localTimeout"
    case textCleanupCloudTimeout = "textCleanup.cloudTimeout"
    case textCleanupLocalModelInactivityDelay = "textCleanup.localModelInactivityDelay"

    case historyEnabled = "history.enabled"
    case feedbackSoundsEnabled = "feedbackSounds.enabled"
    case recordingMaximumDuration = "recording.maximumDuration"
    case emergencyHotkeyControl = "emergencyHotkey.control"
    case emergencyHotkeyOption = "emergencyHotkey.option"
    case emergencyHotkeyCommand = "emergencyHotkey.command"
    case selectionCorrectionEnabled = "selectionCorrection.enabled"
    case selectionCorrectionClipboardFallback = "selectionCorrection.clipboardFallback"
    case selectionCorrectionExcludedApps = "selectionCorrection.excludedApps"
    case selectionCorrectionAllowsCloud = "selectionCorrection.allowsCloud"
    case firstLaunchAssistantCompleted = "onboarding.completed"
}
