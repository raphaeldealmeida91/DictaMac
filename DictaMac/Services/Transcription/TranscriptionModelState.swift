import Combine
import Foundation

@MainActor
final class TranscriptionModelState: ObservableObject {
    @Published private(set) var status = "Modèle non chargé"
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var loadedModel: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false

    init() {}

    func downloading(_ model: String, progress: Double) {
        status = "Téléchargement de \(model)…"
        downloadProgress = min(max(progress, 0), 1)
        isBusy = true
        isReady = false
    }

    func loading(_ model: String) {
        status = "Chargement de \(model)…"
        downloadProgress = nil
        isBusy = true
        isReady = false
    }

    func usingFallback(after model: String) {
        status = "Échec de \(model), tentative avec \(StoredTranscriptionSettings.fallbackModel)…"
        downloadProgress = nil
        isBusy = true
        isReady = false
    }

    func loaded(_ model: String) {
        status = "Modèle chargé : \(model)"
        downloadProgress = nil
        loadedModel = model
        isBusy = true
        isReady = false
    }

    func warmingUp(_ model: String) {
        status = "Modèle chargé : \(model) — pré-chauffage…"
        downloadProgress = nil
        loadedModel = model
        isBusy = true
        isReady = false
    }

    func ready(_ model: String) {
        status = "Modèle prêt : \(model)"
        downloadProgress = nil
        loadedModel = model
        isBusy = false
        isReady = true
    }

    func unloaded(_ message: String) {
        status = message
        downloadProgress = nil
        loadedModel = nil
        isBusy = false
        isReady = false
    }

    func failed(_ error: Error) {
        status = "Modèle indisponible : \(error.localizedDescription)"
        downloadProgress = nil
        loadedModel = nil
        isBusy = false
        isReady = false
    }
}
