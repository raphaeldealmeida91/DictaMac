import Foundation
import SwiftUI

@MainActor
final class SelectionCorrectionViewModel: ObservableObject {
    enum State: Equatable {
        case hidden
        case suggestion
        case copied
        case engineUnavailable
    }

    static let dismissalDuration = Duration.seconds(8)
    static let copiedFeedbackDuration = Duration.seconds(1.2)

    @Published private(set) var state: State = .hidden
    @Published private(set) var correction = SelectionCorrection.unchanged("")
    @Published private(set) var engineUnavailableMessage = "Aucun moteur de correction complet disponible"

    private let replacer: any SelectionReplacing
    private let clipboard: any SelectionClipboardCopying
    private let dismissalDuration: Duration
    private let copiedFeedbackDuration: Duration
    private var snapshot: SelectionSnapshot?
    private var dismissalTask: Task<Void, Never>?
    private var onDismiss: (@MainActor () -> Void)?
    private var onActivateCloud: (@MainActor () -> Void)?
    private var onLoadLocal: (@MainActor () -> Void)?

    init(
        replacer: any SelectionReplacing,
        clipboard: any SelectionClipboardCopying,
        dismissalDuration: Duration = SelectionCorrectionViewModel.dismissalDuration,
        copiedFeedbackDuration: Duration = SelectionCorrectionViewModel.copiedFeedbackDuration
    ) {
        self.replacer = replacer
        self.clipboard = clipboard
        self.dismissalDuration = dismissalDuration
        self.copiedFeedbackDuration = copiedFeedbackDuration
    }

    var highlightedText: AttributedString {
        SelectionCorrectionHighlighting.attributedText(for: correction)
    }

    func present(
        _ correction: SelectionCorrection,
        snapshot: SelectionSnapshot,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        dismissalTask?.cancel()
        self.correction = correction
        self.snapshot = snapshot
        self.onDismiss = onDismiss
        state = .suggestion
        scheduleDismissal(after: dismissalDuration)
    }

    func replace() {
        guard state == .suggestion, let snapshot else { return }
        switch replacer.replace(correction, for: snapshot) {
        case .replaced: dismiss()
        case .copied: showCopiedFeedback()
        }
    }

    func presentEngineUnavailable(
        message: String? = nil,
        onActivateCloud: @escaping @MainActor () -> Void,
        onLoadLocal: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        dismissalTask?.cancel()
        self.onActivateCloud = onActivateCloud
        self.onLoadLocal = onLoadLocal
        self.onDismiss = onDismiss
        engineUnavailableMessage = message ?? "Aucun moteur de correction complet disponible"
        state = .engineUnavailable
        scheduleDismissal(after: dismissalDuration)
    }

    func activateCloud() {
        guard state == .engineUnavailable else { return }
        onActivateCloud?()
        dismiss()
    }

    func loadLocalModel() {
        guard state == .engineUnavailable else { return }
        onLoadLocal?()
        dismiss()
    }

    func copy() {
        guard state == .suggestion else { return }
        clipboard.copy(correction.corrected)
        showCopiedFeedback()
    }

    func dismiss() {
        guard state != .hidden else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        snapshot = nil
        onActivateCloud = nil
        onLoadLocal = nil
        state = .hidden
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    private func showCopiedFeedback() {
        state = .copied
        scheduleDismissal(after: copiedFeedbackDuration)
    }

    private func scheduleDismissal(after duration: Duration) {
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
