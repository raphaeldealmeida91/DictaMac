@preconcurrency import ApplicationServices
import XCTest
@testable import DictaMac

@MainActor
final class HotkeyServiceTests: XCTestCase {
    func testShortFnPressIsIgnored() async {
        let fixture = HotkeyFixture(triggerDelay: 0.05)
        let press = expectation(description: "no press")
        press.isInverted = true
        fixture.service.onPress = { press.fulfill() }
        fixture.start()

        fixture.sendFn(down: true)
        fixture.sendFn(down: false)

        await fulfillment(of: [press], timeout: 0.08)
    }

    func testValidFnPressThenReleasePublishesPair() async {
        let fixture = HotkeyFixture(triggerDelay: 0.01)
        let pressed = expectation(description: "press")
        let released = expectation(description: "release")
        fixture.service.onPress = { pressed.fulfill() }
        fixture.service.onRelease = { released.fulfill() }
        fixture.start()

        fixture.sendFn(down: true)
        await fulfillment(of: [pressed], timeout: 1)
        fixture.sendFn(down: false)

        await fulfillment(of: [released], timeout: 1)
    }

    func testFnWithAnotherKeyCancelsPendingGesture() async {
        let fixture = HotkeyFixture(triggerDelay: 0.05)
        let press = expectation(description: "no press")
        press.isInverted = true
        fixture.service.onPress = { press.fulfill() }
        fixture.start()

        fixture.sendFn(down: true)
        fixture.controller.send(.init(kind: .keyDown, keyCode: 0))
        fixture.sendFn(down: false)

        await fulfillment(of: [press], timeout: 0.08)
    }

    func testRepeatedFlagsChangedDoesNotPublishTwice() async {
        let fixture = HotkeyFixture(triggerDelay: 0)
        let pressed = expectation(description: "single press")
        pressed.expectedFulfillmentCount = 1
        fixture.service.onPress = { pressed.fulfill() }
        fixture.start()

        fixture.sendFn(down: true)
        fixture.sendFn(down: true)

        await fulfillment(of: [pressed], timeout: 1)
    }

    func testEscapeDuringSessionPublishesCancel() async {
        let fixture = HotkeyFixture(triggerDelay: 0)
        let cancelled = expectation(description: "cancel")
        fixture.service.onCancel = { cancelled.fulfill() }
        fixture.start()

        fixture.controller.send(.init(kind: .keyDown, keyCode: 53))

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testPermissionLossDuringPublishedGesturePublishesRelease() async {
        let fixture = HotkeyFixture(triggerDelay: 0)
        let pressed = expectation(description: "press")
        let released = expectation(description: "release")
        fixture.service.onPress = { pressed.fulfill() }
        fixture.service.onRelease = { released.fulfill() }
        fixture.start()
        fixture.sendFn(down: true)
        await fulfillment(of: [pressed], timeout: 1)

        fixture.permissionObserver.send(isAuthorized: false)

        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(fixture.controller.permissionChanges, [false])
    }

    func testDisabledTapIsReactivated() async {
        let fixture = HotkeyFixture(triggerDelay: 0)
        let reactivated = expectation(description: "reactivated")
        fixture.controller.onReenable = { reactivated.fulfill() }
        fixture.start()

        fixture.controller.send(.init(kind: .tapDisabledByTimeout))

        await fulfillment(of: [reactivated], timeout: 1)
        XCTAssertEqual(fixture.diagnosticLog.disabledReasons, ["timeout"])
    }

    func testEmergencyShortcutTriggersOnlyOnceWhileHeld() async {
        let fixture = HotkeyFixture(triggerDelay: 0)
        let triggered = expectation(description: "emergency")
        fixture.recovery.onBegin = { triggered.fulfill() }
        fixture.start()
        let flags = fixture.emergencyFlags

        fixture.controller.send(.init(kind: .flagsChanged, flags: flags))
        fixture.controller.send(.init(kind: .keyDown, flags: flags, keyCode: 1))
        await fulfillment(of: [triggered], timeout: 1)

        XCTAssertEqual(fixture.recovery.beginCount, 1)
    }

    func testRepeatedStartIsIdempotent() {
        let fixture = HotkeyFixture(triggerDelay: 0)

        fixture.service.start()
        fixture.service.start()

        XCTAssertEqual(fixture.controller.startCount, 1)
        XCTAssertEqual(fixture.permissionObserver.startCount, 1)
    }

    func testThirdEmergencyPressRequestsExit() async {
        let fixture = HotkeyFixture(triggerDelay: 0)
        fixture.start()

        for _ in 0..<3 {
            fixture.sendEmergency(down: true)
            fixture.sendEmergency(down: false)
        }
        await fulfillment(of: [fixture.recovery.exitExpectation], timeout: 1)

        XCTAssertEqual(fixture.recovery.exitCount, 1)
    }
}

@MainActor
private final class HotkeyFixture {
    let controller = FakeHotkeyEventTapController()
    let permissionObserver = FakeHotkeyPermissionObserver()
    let callbackDelivery = HotkeyCallbackDelivery()
    let recovery = FakeEmergencyRecovery()
    let diagnosticLog = HotkeyDiagnosticLogSpy()
    let emergencyFlags = (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
    let service: HotkeyService

    init(triggerDelay: TimeInterval) {
        let settings = FakeEmergencyHotkeySettings(flags: CGEventFlags(rawValue: emergencyFlags))
        let detector = EmergencyHotkeyDetector(
            settings: settings,
            runtime: EmergencyRuntime(),
            recovery: recovery
        )
        let processor = HotkeyEventProcessor(
            triggerDelay: triggerDelay,
            emergencyDetector: detector,
            callbackDelivery: callbackDelivery,
            diagnosticLog: diagnosticLog
        )
        processor.setTapReactivation { [weak controller] in controller?.reenable() }
        service = HotkeyService(
            eventTapController: controller,
            eventProcessor: processor,
            permissionObserver: permissionObserver,
            callbackDelivery: callbackDelivery
        )
    }

    func start() { service.start() }

    func sendFn(down: Bool) {
        controller.send(.init(
            kind: .flagsChanged,
            flags: down ? CGEventFlags.maskSecondaryFn.rawValue : 0
        ))
    }

    func sendEmergency(down: Bool) {
        controller.send(.init(kind: .flagsChanged, flags: down ? emergencyFlags : 0))
    }

}

private final class FakeHotkeyEventTapController: HotkeyEventTapControlling, @unchecked Sendable {
    private var handler: (@Sendable (HotkeyEventSnapshot) -> Void)?
    private(set) var startCount = 0
    private(set) var permissionChanges: [Bool] = []
    var onReenable: (@Sendable () -> Void)?

    func setEventHandler(_ handler: @escaping @Sendable (HotkeyEventSnapshot) -> Void) {
        self.handler = handler
    }

    func start() { startCount += 1 }
    func stop() {}
    func permissionDidChange(isAuthorized: Bool) { permissionChanges.append(isAuthorized) }
    func reenable() { onReenable?() }
    func send(_ snapshot: HotkeyEventSnapshot) { handler?(snapshot) }
}

private final class FakeHotkeyPermissionObserver: HotkeyPermissionObserving, @unchecked Sendable {
    private var handler: (@Sendable (Bool) -> Void)?
    private(set) var startCount = 0

    func start(_ handler: @escaping @Sendable (Bool) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() { handler = nil }
    func send(isAuthorized: Bool) { handler?(isAuthorized) }
}

private struct FakeEmergencyHotkeySettings: EmergencyHotkeySettings {
    let flags: CGEventFlags
    var configuredModifiers: CGEventFlags { flags }
}

private final class FakeEmergencyRecovery: EmergencyRecovering, @unchecked Sendable {
    private(set) var beginCount = 0
    private(set) var exitCount = 0
    let exitExpectation = XCTestExpectation(description: "emergency exit")
    var onBegin: (@Sendable () -> Void)?

    func begin(reason _: String, hotkey _: Bool) {
        beginCount += 1
        onBegin?()
    }
    func exit(reason _: String) {
        exitCount += 1
        exitExpectation.fulfill()
    }
}

private final class HotkeyDiagnosticLogSpy: DiagnosticLogging, @unchecked Sendable {
    private(set) var disabledReasons: [String] = []

    func stage(
        _: DiagnosticStage,
        phase _: String,
        duration _: TimeInterval?,
        audioDuration _: TimeInterval?,
        segmentCount _: Int?
    ) {}

    func inputLost() {}
    func emergencyRecovery(reason _: String) {}
    func emergencyExitAndFlush(reason _: String) {}
    func modelLoadCompleted(duration _: TimeInterval, reusedCompiledCache _: Bool) {}
    func memory(context _: DiagnosticMemoryContext, bytes _: UInt64?) {}
    func memoryPressure(critical _: Bool) {}
    func mainThreadStall(duration _: TimeInterval) {}
    func eventTapDisabled(reason: String) { disabledReasons.append(reason) }
}
