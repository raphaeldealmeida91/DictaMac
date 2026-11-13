import Combine
import Foundation

@MainActor
final class LocalCleanupModelState: ObservableObject {
    @Published private(set) var status = "Modèle non téléchargé"
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false
    @Published private(set) var hasError = false

    init() {}

    func downloading(progress: Double) {
        status = "Téléchargement du modèle local…"
        downloadProgress = min(max(progress, 0), 1)
        isBusy = true
        isReady = false
        hasError = false
    }

    func loading() {
        status = "Chargement du modèle local…"
        downloadProgress = nil
        isBusy = true
        isReady = false
        hasError = false
    }

    func waitingForTranscriptionModel() {
        status = "En attente du chargement du modèle de transcription…"
        downloadProgress = nil
        isBusy = true
        isReady = false
        hasError = false
    }

    func loaded(model: String) {
        status = "Modèle chargé : \(model) — pré-chauffage…"
        downloadProgress = nil
        isBusy = true
        isReady = false
        hasError = false
    }

    func ready(model: String) {
        status = "Modèle prêt : \(model)"
        downloadProgress = nil
        isBusy = false
        isReady = true
        hasError = false
    }

    func unloaded(_ message: String = "Modèle déchargé") {
        status = message
        downloadProgress = nil
        isBusy = false
        isReady = false
        hasError = false
    }

    func failed(_ error: Error) {
        status = "Modèle indisponible : \(error.localizedDescription)"
        downloadProgress = nil
        isBusy = false
        isReady = false
        hasError = true
    }
}
