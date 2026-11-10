import XCTest
@testable import DictaMac

@MainActor
final class MemoryPressureMonitorTests: XCTestCase {
    func testWarningUnloadsOnlyLocalModelAndSelectsFastCleanup() async {
        let local = ModelUnloaderSpy()
        let transcription = ModelUnloaderSpy()
        let settings = TextCleanupSettingsSpy()
        let alerts = UserAlertPresenterSpy()
        let monitor = makeMonitor(
            local: local,
            transcription: transcription,
            settings: settings,
            alerts: alerts
        )

        monitor.start()
        await monitor.handle(.warning)
        monitor.stop()

        let localUnloadCount = await local.count()
        let transcriptionUnloadCount = await transcription.count()
        XCTAssertEqual(localUnloadCount, 1)
        XCTAssertEqual(transcriptionUnloadCount, 0)
        XCTAssertEqual(settings.selectedEngine, .fast)
        XCTAssertEqual(alerts.presentedStyles, [.warning])
    }

    func testCriticalUnloadsBothModelsAndSelectsFastCleanup() async {
        let local = ModelUnloaderSpy()
        let transcription = ModelUnloaderSpy()
        let settings = TextCleanupSettingsSpy()
        let alerts = UserAlertPresenterSpy()
        let monitor = makeMonitor(
            local: local,
            transcription: transcription,
            settings: settings,
            alerts: alerts
        )

        monitor.start()
        await monitor.handle(.critical)
        monitor.stop()

        let localUnloadCount = await local.count()
        let transcriptionUnloadCount = await transcription.count()
        XCTAssertEqual(localUnloadCount, 1)
        XCTAssertEqual(transcriptionUnloadCount, 1)
        XCTAssertEqual(settings.selectedEngine, .fast)
        XCTAssertEqual(alerts.presentedStyles, [.critical])
    }

    private func makeMonitor(
        local: ModelUnloaderSpy,
        transcription: ModelUnloaderSpy,
        settings: TextCleanupSettingsSpy,
        alerts: UserAlertPresenterSpy
    ) -> MemoryPressureMonitor {
        MemoryPressureMonitor(
            localModelUnloader: local,
            transcriptionModelUnloader: transcription,
            textCleanupSettings: settings,
            alertPresenter: alerts,
            diagnosticLog: PersistentDiagnosticLog()
        )
    }
}

private actor ModelUnloaderSpy: ModelUnloading {
    private(set) var unloadCount = 0

    func unload(reason: String) {
        unloadCount += 1
    }

    func count() -> Int { unloadCount }
}

// Tests access the spy serially on the main actor; the protocol requires Sendable conformance.
private final class TextCleanupSettingsSpy: TextCleanupSettingsWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: TextCleanupEngine?

    var selectedEngine: TextCleanupEngine? { lock.withLock { engine } }

    func migrate() {}
    func approveLocalDownload() {}
    func setEngine(_ engine: TextCleanupEngine) {
        lock.withLock { self.engine = engine }
    }
}

@MainActor
private final class UserAlertPresenterSpy: UserAlertPresenting {
    private(set) var presentedStyles: [UserAlertStyle] = []

    func present(_ alert: UserAlert) -> UserAlertResponse {
        presentedStyles.append(alert.style)
        return .primary
    }
}
