import SwiftUI

extension Notification.Name {
    static let openSettingsSection = Notification.Name("DictaMac.openSettingsSection")
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case transcription
    case textCleanup
    case selectionCorrection
    case dictionary
    case permissions
    case diagnostic

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Général"
        case .transcription: "Transcription"
        case .textCleanup: "Nettoyage du texte"
        case .selectionCorrection: "Correction de sélection"
        case .dictionary: "Dictionnaire"
        case .permissions: "Autorisations"
        case .diagnostic: "Diagnostic"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .transcription: "waveform"
        case .textCleanup: "text.badge.checkmark"
        case .selectionCorrection: "selection.pin.in.out"
        case .dictionary: "character.book.closed"
        case .permissions: "hand.raised"
        case .diagnostic: "gauge.with.dots.needle.67percent"
        }
    }
}
