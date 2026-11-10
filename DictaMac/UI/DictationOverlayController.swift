import AppKit
import SwiftUI

@MainActor
final class DictationOverlayController: OverlayPresenting {
    private enum Constants {
        static let messageDisplayDuration = Duration.seconds(2)
    }

    private let model = DictationOverlayModel()
    private var panel: NonActivatingOverlayPanel?
    private var errorDismissalTask: Task<Void, Never>?

    func showRecording() {
        errorDismissalTask?.cancel()
        model.presentation = .recording
        model.levels = Array(repeating: 0.08, count: 12)
        show()
    }

    func updateLevel(_ rms: Float) {
        guard model.presentation == .recording else { return }

        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = min(max((decibels + 55) / 55, 0.08), 1)
        model.levels.removeFirst()
        model.levels.append(normalized)
    }

    func showTranscribing(message: String = "Transcription…") {
        errorDismissalTask?.cancel()
        model.presentation = .transcribing(message)
        show()
    }

    func showMessage(_ message: String) {
        errorDismissalTask?.cancel()
        model.presentation = .message(message)
        show()

        errorDismissalTask = Task { [weak self] in
            try? await Task.sleep(for: Constants.messageDisplayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showError(_ message: String) {
        errorDismissalTask?.cancel()
        model.presentation = .error(message)
        show()

        errorDismissalTask = Task { [weak self] in
            try? await Task.sleep(for: Constants.messageDisplayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        errorDismissalTask?.cancel()
        errorDismissalTask = nil
        panel?.orderOut(nil)
    }

    private func show() {
        let panel = panel ?? makePanel()
        position(panel, on: screenContainingCursor())

        // `orderFrontRegardless` displays the panel without making it key and
        // without activating this LSUIElement application.
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NonActivatingOverlayPanel {
        let panel = NonActivatingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 232, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DictationOverlayView(model: model))
        self.panel = panel
        return panel
    }

    private func screenContainingCursor() -> NSScreen {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
    }
}

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum OverlayPresentation: Equatable {
    case recording
    case transcribing(String)
    case message(String)
    case error(String)
}

@MainActor
private final class DictationOverlayModel: ObservableObject {
    @Published var presentation: OverlayPresentation = .recording
    @Published var levels = Array(repeating: Float(0.08), count: 12)
}

private struct DictationOverlayView: View {
    @ObservedObject var model: DictationOverlayModel

    var body: some View {
        Group {
            switch model.presentation {
            case .recording:
                HStack(spacing: 12) {
                    Circle()
                        .fill(.red)
                        .frame(width: 9, height: 9)
                    WaveformView(levels: model.levels)
                    Text("Enregistrement")
                }
            case .transcribing(let message):
                HStack(spacing: 11) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .lineLimit(1)
                }
            case .message(let message):
                HStack(spacing: 9) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .foregroundStyle(.blue)
                    Text(message)
                        .lineLimit(1)
                }
            case .error(let message):
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(width: 232, height: 54)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

private struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.primary.opacity(0.82))
                    .frame(width: 2, height: max(3, CGFloat(level) * 23))
            }
        }
        .frame(width: 46, height: 24)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
