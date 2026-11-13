import AppKit
import XCTest
@testable import DictaMac

final class SelectionPolicyTests: XCTestCase {
    func testAcceptsTwoWordsFromAllowedApplication() {
        let policy = SelectionPolicy(excludedBundleIDs: [], ownBundleID: "com.example.DictaMac")

        XCTAssertTrue(policy.accepts(snapshot(text: "deux mots", bundleID: "com.example.Editor")))
    }

    func testRejectsShortLongSecureAndExcludedSelections() {
        let policy = SelectionPolicy(
            excludedBundleIDs: ["com.example.Secret"],
            ownBundleID: "com.example.DictaMac"
        )
        let longText = String(repeating: "a", count: SelectionPolicy.maximumCharacterCount + 1) + " mot"

        XCTAssertFalse(policy.accepts(snapshot(text: "unique", bundleID: nil)))
        XCTAssertFalse(policy.accepts(snapshot(text: longText, bundleID: nil)))
        XCTAssertFalse(policy.accepts(snapshot(text: "champ secret", bundleID: nil, isSecure: true)))
        XCTAssertFalse(policy.accepts(snapshot(text: "texte valide", bundleID: "com.example.Secret")))
        XCTAssertFalse(policy.accepts(snapshot(text: "texte valide", bundleID: "com.example.DictaMac")))
    }

    private func snapshot(
        text: String,
        bundleID: String?,
        isSecure: Bool = false
    ) -> SelectionSnapshot {
        SelectionSnapshot(text: text, screenRect: nil, sourceBundleID: bundleID, isSecure: isSecure)
    }
}

@MainActor
final class AccessibilitySelectedTextReaderTests: XCTestCase {
    func testSecureFieldIsIgnored() {
        let reader = AccessibilitySelectedTextReader(
            permissionReader: FakeAccessibilityPermissionReader(isAuthorized: true),
            selectionQuery: {
                ("mot de passe", nil, "com.example.Secret", true)
            }
        )

        XCTAssertNil(reader.readSelection())
        XCTAssertTrue(reader.didEncounterSecureField)
    }

    func testDeniedAccessibilitySkipsQuery() {
        var queryCount = 0
        let reader = AccessibilitySelectedTextReader(
            permissionReader: FakeAccessibilityPermissionReader(isAuthorized: false),
            selectionQuery: {
                queryCount += 1
                return nil
            }
        )

        XCTAssertNil(reader.readSelection())
        XCTAssertEqual(queryCount, 0)
    }
}

@MainActor
final class ClipboardSelectedTextReaderTests: XCTestCase {
    func testCopiedSelectionRestoresEveryOriginalPasteboardRepresentation() {
        let originalItems = [PasteboardItemContents(representations: [
            .string: Data("original".utf8),
            .html: Data("<b>original</b>".utf8),
            NSPasteboard.PasteboardType("com.example.custom"): Data([1, 2, 3])
        ])]
        let pasteboard = SelectionFakePasteboard(items: originalItems)
        let reader = ClipboardSelectedTextReader(
            pasteboard: pasteboard,
            copyCommand: {
                pasteboard.writeText("texte sélectionné")
                return true
            },
            changeWaiter: { initialCount, pasteboard in
                pasteboard.changeCount != initialCount
            },
            sourceBundleIDProvider: { "com.example.Editor" },
            secureInputCheck: { false }
        )

        let result = reader.readSelection()

        XCTAssertEqual(result?.text, "texte sélectionné")
        XCTAssertEqual(result?.sourceBundleID, "com.example.Editor")
        XCTAssertEqual(pasteboard.items, originalItems)
    }
}

@MainActor
final class SelectionWatcherTests: XCTestCase {
    func testDebouncesRapidPotentialSelectionEvents() async throws {
        let monitor = SelectionFakeEventMonitor()
        let reader = SelectionFakeReader(results: [validSnapshot("dernière sélection")])
        let watcher = makeWatcher(monitor: monitor, accessibilityReader: reader)
        let recorder = SelectionEventRecorder(stream: watcher.events())
        watcher.start()

        monitor.sendEvent()
        monitor.sendEvent()
        monitor.sendEvent()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(recorder.events, [.selected(validSnapshot("dernière sélection"))])
        watcher.stop()
    }

    func testDeduplicatesSameTextAndPublishesClearedEvent() async throws {
        let snapshot = validSnapshot("même sélection")
        let monitor = SelectionFakeEventMonitor()
        let reader = SelectionFakeReader(results: [snapshot, snapshot, nil])
        let watcher = makeWatcher(monitor: monitor, accessibilityReader: reader)
        let recorder = SelectionEventRecorder(stream: watcher.events())
        watcher.start()

        monitor.sendEvent()
        try await Task.sleep(for: .milliseconds(50))
        monitor.sendEvent()
        try await Task.sleep(for: .milliseconds(50))
        monitor.sendEvent()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.events, [.selected(snapshot), .cleared])
        watcher.stop()
    }

    func testSecureAccessibilityResultDoesNotUseClipboardFallback() async throws {
        let monitor = SelectionFakeEventMonitor()
        let permission = FakeAccessibilityPermissionReader(isAuthorized: true)
        let accessibilityReader = AccessibilitySelectedTextReader(permissionReader: permission) {
            ("texte secret", nil, "com.example.Secret", true)
        }
        let clipboardReader = SelectionFakeReader(results: [validSnapshot("copie interdite")])
        let watcher = makeWatcher(
            monitor: monitor,
            accessibilityReader: accessibilityReader,
            clipboardReader: clipboardReader,
            settings: SelectionFakeSettings(isClipboardFallbackEnabled: true)
        )
        watcher.start()

        monitor.sendEvent()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(clipboardReader.readCount, 0)
        watcher.stop()
    }

    private func makeWatcher(
        monitor: SelectionFakeEventMonitor,
        accessibilityReader: any SelectedTextReading,
        clipboardReader: any SelectedTextReading = SelectionFakeReader(results: []),
        settings: SelectionFakeSettings = SelectionFakeSettings()
    ) -> SelectionWatcher {
        SelectionWatcher(
            eventMonitor: monitor,
            accessibilityReader: accessibilityReader,
            clipboardReader: clipboardReader,
            settings: settings,
            ownBundleID: "com.example.DictaMac",
            debounceDuration: .milliseconds(20)
        )
    }
}

private func validSnapshot(_ text: String) -> SelectionSnapshot {
    SelectionSnapshot(
        text: text,
        screenRect: CGRect(x: 10, y: 20, width: 30, height: 40),
        sourceBundleID: "com.example.Editor",
        isSecure: false
    )
}

private struct FakeAccessibilityPermissionReader: AccessibilityPermissionReading {
    let isAccessibilityAuthorized: Bool

    init(isAuthorized: Bool) {
        isAccessibilityAuthorized = isAuthorized
    }
}

@MainActor
private final class SelectionFakePasteboard: PasteboardProviding {
    private(set) var changeCount = 0
    private(set) var items: [PasteboardItemContents]

    init(items: [PasteboardItemContents]) {
        self.items = items
    }

    func readItems() -> [PasteboardItemContents] { items }

    @discardableResult
    func replaceItems(with items: [PasteboardItemContents]) -> Int {
        self.items = items
        changeCount += 1
        return changeCount
    }

    @discardableResult
    func writeTransientText(_ text: String) -> Int { writeText(text) }

    @discardableResult
    func writeText(_ text: String) -> Int {
        items = [PasteboardItemContents(representations: [.string: Data(text.utf8)])]
        changeCount += 1
        return changeCount
    }
}

@MainActor
private final class SelectionFakeEventMonitor: SelectionEventMonitoring {
    private var continuation: AsyncStream<Void>.Continuation?

    func events() -> AsyncStream<Void> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }

    func sendEvent() {
        continuation?.yield()
    }
}

@MainActor
private final class SelectionFakeReader: SelectedTextReading {
    private var results: [SelectionSnapshot?]
    private(set) var readCount = 0

    init(results: [SelectionSnapshot?]) {
        self.results = results
    }

    func readSelection() -> SelectionSnapshot? {
        readCount += 1
        guard !results.isEmpty else { return nil }
        return results.removeFirst()
    }
}

private struct SelectionFakeSettings: SelectionCorrectionSettings {
    let isEnabled: Bool
    let isClipboardFallbackEnabled: Bool
    let allowsCloud: Bool
    let excludedBundleIDs: Set<String>

    init(
        isEnabled: Bool = true,
        isClipboardFallbackEnabled: Bool = false,
        allowsCloud: Bool = false,
        excludedBundleIDs: Set<String> = []
    ) {
        self.isEnabled = isEnabled
        self.isClipboardFallbackEnabled = isClipboardFallbackEnabled
        self.allowsCloud = allowsCloud
        self.excludedBundleIDs = excludedBundleIDs
    }
}

@MainActor
private final class SelectionEventRecorder {
    private(set) var events: [SelectionEvent] = []
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<SelectionEvent>) {
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
