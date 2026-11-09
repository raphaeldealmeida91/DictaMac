@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import Combine

extension Notification.Name {
    static let microphonePermissionDidChange = Notification.Name(
        "com.raphaeldealmeida.DictaMac.microphonePermissionDidChange"
    )
    static let inputMonitoringPermissionDidChange = Notification.Name(
        "com.raphaeldealmeida.DictaMac.inputMonitoringPermissionDidChange"
    )
}

enum AppPermission: CaseIterable, Identifiable, Sendable {
    case microphone
    case inputMonitoring
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Surveillance de l’entrée"
        case .accessibility: "Accessibilité"
        }
    }

    var systemSettingsURL: URL? {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }

        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        )
    }
}

enum PermissionStatus: Sendable {
    case notDetermined
    case denied
    case authorized

    var isAuthorized: Bool { self == .authorized }
}

final class PermissionStateCache: @unchecked Sendable {
    static let shared = PermissionStateCache()
    private let lock = NSLock()
    private var accessibilityAuthorized = false

    var isAccessibilityAuthorized: Bool {
        lock.withLock { accessibilityAuthorized }
    }

    func updateAccessibility(_ authorized: Bool) {
        lock.withLock { accessibilityAuthorized = authorized }
    }
}

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var inputMonitoringStatus: PermissionStatus = .denied
    @Published private(set) var accessibilityStatus: PermissionStatus = .denied

    private var activeObserver: NSObjectProtocol?
    // The timer and all TCC reads run away from the main thread.
    nonisolated(unsafe) private var refreshTimer: DispatchSourceTimer?
    private let refreshQueue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.permission-refresh",
        qos: .utility
    )
    private var refreshTask: Task<Void, Never>?

    private struct Snapshot: Sendable {
        let microphone: PermissionStatus
        let inputMonitoring: PermissionStatus
        let accessibility: PermissionStatus
    }

    init() {
        refresh()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        refreshTimer?.cancel()
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .microphone: microphoneStatus
        case .inputMonitoring: inputMonitoringStatus
        case .accessibility: accessibilityStatus
        }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await Self.readSnapshot()
            self.apply(snapshot)
            self.refreshTask = nil
        }
    }

    @discardableResult
    func request(_ permission: AppPermission) async -> PermissionStatus {
        await Task.detached(priority: .userInitiated) {
            switch permission {
            case .microphone:
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            case .inputMonitoring:
                _ = CGRequestListenEventAccess()
            case .accessibility:
                _ = Self.accessibilityIsTrusted(prompt: true)
            }
        }.value
        let snapshot = await Self.readSnapshot()
        apply(snapshot)
        return status(for: permission)
    }

    func startPeriodicRefresh() {
        guard refreshTimer == nil else { return }

        refresh()
        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refreshTimer = timer
        timer.resume()
    }

    func stopPeriodicRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    func openSystemSettings(for permission: AppPermission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    static func primeSharedCache() async {
        let snapshot = await readSnapshot()
        PermissionStateCache.shared.updateAccessibility(snapshot.accessibility.isAuthorized)
    }

    private static func readSnapshot() async -> Snapshot {
        await Task.detached(priority: .utility) {
            let microphone: PermissionStatus = switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: .notDetermined
            case .authorized: .authorized
            case .denied, .restricted: .denied
            @unknown default: .denied
            }
            return Snapshot(
                microphone: microphone,
                inputMonitoring: CGPreflightListenEventAccess() ? .authorized : .denied,
                accessibility: accessibilityIsTrusted(prompt: false) ? .authorized : .denied
            )
        }.value
    }

    private func apply(_ snapshot: Snapshot) {
        let microphoneChanged = microphoneStatus != snapshot.microphone
        let inputMonitoringChanged = inputMonitoringStatus != snapshot.inputMonitoring
        microphoneStatus = snapshot.microphone
        inputMonitoringStatus = snapshot.inputMonitoring
        accessibilityStatus = snapshot.accessibility
        PermissionStateCache.shared.updateAccessibility(snapshot.accessibility.isAuthorized)

        if microphoneChanged {
            NotificationCenter.default.post(name: .microphonePermissionDidChange, object: nil)
        }
        if inputMonitoringChanged {
            NotificationCenter.default.post(
                name: .inputMonitoringPermissionDidChange,
                object: nil,
                userInfo: ["authorized": snapshot.inputMonitoring.isAuthorized]
            )
        }
    }

    private nonisolated static func accessibilityIsTrusted(prompt: Bool) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
