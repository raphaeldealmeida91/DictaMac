import Foundation

@MainActor
final class SelectionWatcher {
    static let debounceDuration = Duration.milliseconds(350)

    private let eventMonitor: any SelectionEventMonitoring
    private let accessibilityReader: any SelectedTextReading
    private let clipboardReader: any SelectedTextReading
    private let settings: any SelectionCorrectionSettings
    private let ownBundleID: String?
    private let debounceDuration: Duration
    private var monitoringTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var continuation: AsyncStream<SelectionEvent>.Continuation?
    private var lastText: String?

    init(
        eventMonitor: any SelectionEventMonitoring,
        accessibilityReader: any SelectedTextReading,
        clipboardReader: any SelectedTextReading,
        settings: any SelectionCorrectionSettings,
        ownBundleID: String?,
        debounceDuration: Duration = SelectionWatcher.debounceDuration
    ) {
        self.eventMonitor = eventMonitor
        self.accessibilityReader = accessibilityReader
        self.clipboardReader = clipboardReader
        self.settings = settings
        self.ownBundleID = ownBundleID
        self.debounceDuration = debounceDuration
    }

    func events() -> AsyncStream<SelectionEvent> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
        }
    }

    func start() {
        guard monitoringTask == nil else { return }
        let monitoredEvents = eventMonitor.events()
        monitoringTask = Task { [weak self] in
            for await _ in monitoredEvents {
                guard !Task.isCancelled else { return }
                self?.scheduleRead()
            }
        }
    }

    func stop() {
        debounceTask?.cancel()
        monitoringTask?.cancel()
        debounceTask = nil
        monitoringTask = nil
        eventMonitor.stop()
        clearSelectionIfNeeded()
    }

    private func scheduleRead() {
        debounceTask?.cancel()
        let delay = debounceDuration
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.readSelection()
        }
    }

    private func readSelection() {
        let accessibilitySnapshot = accessibilityReader.readSelection()
        let snapshot = accessibilitySnapshot ?? safeClipboardFallback()
        guard let snapshot, policy.accepts(snapshot) else {
            clearSelectionIfNeeded()
            return
        }
        guard snapshot.text != lastText else { return }
        lastText = snapshot.text
        continuation?.yield(.selected(snapshot))
    }

    private func safeClipboardFallback() -> SelectionSnapshot? {
        guard settings.isClipboardFallbackEnabled,
              !didEncounterSecureField else { return nil }
        return clipboardReader.readSelection()
    }

    private var didEncounterSecureField: Bool {
        (accessibilityReader as? any SecureSelectionDetecting)?.didEncounterSecureField ?? false
    }

    private var policy: SelectionPolicy {
        SelectionPolicy(
            excludedBundleIDs: settings.excludedBundleIDs,
            ownBundleID: ownBundleID
        )
    }

    private func clearSelectionIfNeeded() {
        guard lastText != nil else { return }
        lastText = nil
        continuation?.yield(.cleared)
    }
}
