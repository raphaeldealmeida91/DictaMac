import Foundation
import OSLog

@MainActor
final class SelectionWatcher {
    static let debounceDuration = Duration.milliseconds(350)

    private let eventMonitor: any SelectionEventMonitoring
    private let accessibilityReader: any SelectedTextReading
    private let clipboardReader: any SelectedTextReading
    private let settings: any SelectionCorrectionSettings
    private let ownBundleID: String?
    private let debounceDuration: Duration
    private let permissionReader: (any AccessibilityPermissionReading)?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "selection"
    )
    private var monitoringTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<SelectionEvent>.Continuation] = [:]
    private var hasSelection = false
    private(set) var latestDetectionInstant: ContinuousClock.Instant?

    init(
        eventMonitor: any SelectionEventMonitoring,
        accessibilityReader: any SelectedTextReading,
        clipboardReader: any SelectedTextReading,
        settings: any SelectionCorrectionSettings,
        ownBundleID: String?,
        permissionReader: (any AccessibilityPermissionReading)? = nil,
        debounceDuration: Duration = SelectionWatcher.debounceDuration
    ) {
        self.eventMonitor = eventMonitor
        self.accessibilityReader = accessibilityReader
        self.clipboardReader = clipboardReader
        self.settings = settings
        self.ownBundleID = ownBundleID
        self.permissionReader = permissionReader
        self.debounceDuration = debounceDuration
    }

    func events() -> AsyncStream<SelectionEvent> {
        AsyncStream { continuation in
            let identifier = UUID()
            continuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: identifier) }
            }
        }
    }

    func start() {
        guard monitoringTask == nil else { return }
        logger.info("accessibility authorized=\(self.permissionReader?.isAccessibilityAuthorized ?? false)")
        let monitoredEvents = eventMonitor.events()
        monitoringTask = Task { [weak self] in
            for await event in monitoredEvents {
                guard !Task.isCancelled else { return }
                self?.scheduleRead(event, detectedAt: .now)
            }
        }
    }

    func stop() {
        debounceTask?.cancel()
        monitoringTask?.cancel()
        debounceTask = nil
        monitoringTask = nil
        latestDetectionInstant = nil
        eventMonitor.stop()
        clearSelectionIfNeeded()
    }

    private func scheduleRead(_ event: SelectionMonitorEvent, detectedAt: ContinuousClock.Instant) {
        debounceTask?.cancel()
        latestDetectionInstant = detectedAt
        let delay = debounceDuration
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.read(event)
        }
    }

    private func read(_ event: SelectionMonitorEvent) {
        switch event {
        case .selectionChanged:
            readSelection()
            readFocusedText()
        case .textChanged: readFocusedText()
        }
    }

    private func readFocusedText() {
        guard let reader = accessibilityReader as? any FocusedTextReading,
              let snapshot = reader.readFocusedText(),
              !snapshot.isSecure else { return }
        yield(.focusedText(snapshot))
    }

    private func readSelection() {
        let accessibilitySnapshot = accessibilityReader.readSelection()
        if let accessibilitySnapshot {
            logger.info("AX read succeeded length=\(accessibilitySnapshot.text.count)")
        } else {
            logger.info("AX read returned nil")
        }
        let snapshot = accessibilitySnapshot ?? safeClipboardFallback()
        guard let snapshot, policy.accepts(snapshot) else {
            clearSelectionIfNeeded()
            return
        }
        hasSelection = true
        yield(.selected(snapshot))
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
        guard hasSelection else { return }
        hasSelection = false
        yield(.cleared)
    }

    private func yield(_ event: SelectionEvent) {
        continuations.values.forEach { $0.yield(event) }
    }
}
