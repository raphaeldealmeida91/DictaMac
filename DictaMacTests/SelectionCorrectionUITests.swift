import XCTest
@testable import DictaMac

@MainActor
final class SelectionCorrectionViewModelTests: XCTestCase {
    func testReplacementDismissesAfterSuccessfulPaste() {
        let replacer = ViewModelFakeReplacer(outcome: .replaced)
        let clipboard = ViewModelFakeClipboard()
        let viewModel = makeViewModel(replacer: replacer, clipboard: clipboard)
        var dismissCount = 0
        viewModel.present(correction, snapshot: snapshot) { dismissCount += 1 }

        viewModel.replace()

        XCTAssertEqual(replacer.callCount, 1)
        XCTAssertEqual(viewModel.state, .hidden)
        XCTAssertEqual(dismissCount, 1)
    }

    func testReplacementFallbackShowsCopiedThenDismisses() async throws {
        let replacer = ViewModelFakeReplacer(outcome: .copied)
        let viewModel = makeViewModel(replacer: replacer)
        viewModel.present(correction, snapshot: snapshot) {}

        viewModel.replace()
        XCTAssertEqual(viewModel.state, .copied)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(viewModel.state, .hidden)
    }

    func testCopyAndAutomaticDismissal() async throws {
        let clipboard = ViewModelFakeClipboard()
        let viewModel = makeViewModel(clipboard: clipboard)
        viewModel.present(correction, snapshot: snapshot) {}

        viewModel.copy()
        XCTAssertEqual(clipboard.copiedText, correction.corrected)
        XCTAssertEqual(viewModel.state, .copied)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(viewModel.state, .hidden)
    }

    func testSuggestionAutomaticallyCloses() async throws {
        let viewModel = makeViewModel()
        viewModel.present(correction, snapshot: snapshot) {}

        try await Task.sleep(for: .milliseconds(70))

        XCTAssertEqual(viewModel.state, .hidden)
    }

    private func makeViewModel(
        replacer: ViewModelFakeReplacer = ViewModelFakeReplacer(outcome: .replaced),
        clipboard: ViewModelFakeClipboard = ViewModelFakeClipboard()
    ) -> SelectionCorrectionViewModel {
        SelectionCorrectionViewModel(
            replacer: replacer,
            clipboard: clipboard,
            dismissalDuration: .milliseconds(50),
            copiedFeedbackDuration: .milliseconds(20)
        )
    }

    private var correction: SelectionCorrection {
        SelectionCorrection(
            original: "Ils mange",
            corrected: "Ils mangent",
            changes: [TextChange(range: NSRange(location: 4, length: 5), replacement: "mangent")]
        )
    }

    private var snapshot: SelectionSnapshot {
        SelectionSnapshot(text: "Ils mange", screenRect: nil, sourceBundleID: "editor", isSecure: false)
    }
}

@MainActor
final class SelectionReplacerTests: XCTestCase {
    func testCopiesWhenSourceAppChanged() {
        let reader = ReplacementFakeReader(snapshot: snapshot(text: "texte initial", bundleID: "editor"))
        let injector = ReplacementFakeInjector()
        let pasteboard = ReplacementFakePasteboard()
        let replacer = SelectionReplacer(
            selectionReader: reader,
            injector: injector,
            pasteboard: pasteboard,
            frontmostBundleID: { "other" }
        )

        let outcome = replacer.replace(correction, for: snapshot(text: "texte initial", bundleID: "editor"))

        XCTAssertEqual(outcome, .copied)
        XCTAssertEqual(pasteboard.text, correction.corrected)
        XCTAssertEqual(injector.callCount, 0)
    }

    func testCopiesWhenSelectionChanged() {
        let reader = ReplacementFakeReader(snapshot: snapshot(text: "autre sélection", bundleID: "editor"))
        let injector = ReplacementFakeInjector()
        let pasteboard = ReplacementFakePasteboard()
        let replacer = SelectionReplacer(
            selectionReader: reader,
            injector: injector,
            pasteboard: pasteboard,
            frontmostBundleID: { "editor" }
        )

        let outcome = replacer.replace(correction, for: snapshot(text: "texte initial", bundleID: "editor"))

        XCTAssertEqual(outcome, .copied)
        XCTAssertEqual(injector.callCount, 0)
    }

    private var correction: SelectionCorrection {
        SelectionCorrection(original: "texte initial", corrected: "Texte initial.", changes: [])
    }

    private func snapshot(text: String, bundleID: String) -> SelectionSnapshot {
        SelectionSnapshot(text: text, screenRect: nil, sourceBundleID: bundleID, isSecure: false)
    }
}

@MainActor
final class SelectionCorrectionCoordinatorTests: XCTestCase {
    func testRulesOnlyMessageIsPresentedOncePerActivation() async throws {
        let fixture = makeFixture(service: CoordinatorRulesOnlyService(), presentationDelay: .milliseconds(1))
        fixture.coordinator.start()

        fixture.reader.snapshot = selectedSnapshot("Une phrase correcte.")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(30))
        fixture.reader.snapshot = selectedSnapshot("Une autre phrase correcte.")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(fixture.presenter.engineUnavailableCount, 1)
        fixture.coordinator.stop()
    }

    func testSafeModeUnavailableMessageReachesPresenter() async throws {
        let fixture = makeFixture(service: CoordinatorSafeModeService(), presentationDelay: .milliseconds(1))
        fixture.coordinator.start()

        fixture.reader.snapshot = selectedSnapshot("Une phrase correcte.")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(fixture.presenter.lastUnavailableMessage, SafeModeState.localCleanupUnavailableMessage)
        fixture.coordinator.stop()
    }

    func testRulesOnlySuggestionIsPresentedInsteadOfUnavailableMessage() async throws {
        let fixture = makeFixture(service: CoordinatorRulesSuggestionService(), presentationDelay: .milliseconds(1))
        fixture.coordinator.start()

        fixture.reader.snapshot = selectedSnapshot("Les enfant joue")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(fixture.presenter.presentationCount, 1)
        XCTAssertEqual(fixture.presenter.engineUnavailableCount, 0)
        fixture.coordinator.stop()
    }

    func testDoesNotPresentBeforeAntiFlickerDelay() async throws {
        let service = CoordinatorImmediateService()
        let fixture = makeFixture(service: service, presentationDelay: .milliseconds(60))
        fixture.coordinator.start()

        fixture.reader.snapshot = selectedSnapshot("Ils mange")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(fixture.presenter.presentationCount, 0)
        XCTAssertEqual(fixture.coordinator.state, .processing)

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(fixture.presenter.presentationCount, 1)
        XCTAssertEqual(fixture.coordinator.state, .suggestion)
        fixture.coordinator.stop()
    }

    func testNewSelectionCancelsPreviousCorrectionAndKeepsOneSuggestion() async throws {
        let service = CoordinatorCancellationService()
        let fixture = makeFixture(service: service, presentationDelay: .milliseconds(5))
        fixture.coordinator.start()

        fixture.reader.snapshot = selectedSnapshot("première sélection")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(30))
        fixture.reader.snapshot = selectedSnapshot("deuxième sélection")
        fixture.monitor.send()
        try await Task.sleep(for: .milliseconds(100))

        let cancellationCount = await service.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(fixture.presenter.presentationCount, 1)
        XCTAssertEqual(fixture.presenter.lastSnapshot?.text, "deuxième sélection")
        XCTAssertGreaterThanOrEqual(fixture.presenter.dismissCount, 2)
        fixture.coordinator.stop()
    }

    private func makeFixture(
        service: any SelectionCorrectionService,
        presentationDelay: Duration
    ) -> CoordinatorFixture {
        let monitor = CoordinatorEventMonitor()
        let reader = CoordinatorSelectionReader()
        let settings = CoordinatorSelectionSettings()
        let watcher = SelectionWatcher(
            eventMonitor: monitor,
            accessibilityReader: reader,
            clipboardReader: reader,
            settings: settings,
            ownBundleID: "dictamac",
            debounceDuration: .milliseconds(1)
        )
        let presenter = CoordinatorPresenter()
        let coordinator = SelectionCorrectionCoordinator(
            watcher: watcher,
            service: service,
            presenter: presenter,
            dictionary: CoordinatorDictionary(),
            presentationDelay: presentationDelay
        )
        return CoordinatorFixture(
            coordinator: coordinator,
            monitor: monitor,
            reader: reader,
            presenter: presenter
        )
    }

    private func selectedSnapshot(_ text: String) -> SelectionSnapshot {
        SelectionSnapshot(text: text, screenRect: nil, sourceBundleID: "editor", isSecure: false)
    }
}

@MainActor
private final class ViewModelFakeReplacer: SelectionReplacing {
    let outcome: SelectionReplacementOutcome
    private(set) var callCount = 0

    init(outcome: SelectionReplacementOutcome) { self.outcome = outcome }

    func replace(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot
    ) -> SelectionReplacementOutcome {
        callCount += 1
        return outcome
    }
}

@MainActor
private final class ViewModelFakeClipboard: SelectionClipboardCopying {
    private(set) var copiedText: String?
    func copy(_ text: String) { copiedText = text }
}

@MainActor
private final class ReplacementFakeReader: SelectedTextReading {
    let snapshot: SelectionSnapshot?
    init(snapshot: SelectionSnapshot?) { self.snapshot = snapshot }
    func readSelection() -> SelectionSnapshot? { snapshot }
}

@MainActor
private final class ReplacementFakeInjector: TextInjector {
    private(set) var callCount = 0
    func insert(_ text: String) -> TextInjectionOutcome {
        callCount += 1
        return .pasted
    }
}

@MainActor
private final class ReplacementFakePasteboard: PasteboardProviding {
    var changeCount = 0
    private(set) var text: String?
    func readItems() -> [PasteboardItemContents] { [] }
    func replaceItems(with items: [PasteboardItemContents]) -> Int { changeCount }
    func writeTransientText(_ text: String) -> Int { writeText(text) }
    func writeText(_ text: String) -> Int {
        self.text = text
        changeCount += 1
        return changeCount
    }
}

private actor CoordinatorImmediateService: SelectionCorrectionService {
    func engineStatus() async -> SelectionCorrectionEngine { .local }

    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        suggestion(for: text)
    }
}

private actor CoordinatorCancellationService: SelectionCorrectionService {
    private(set) var cancellationCount = 0

    func engineStatus() async -> SelectionCorrectionEngine { .local }

    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        if text == "première sélection" {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                cancellationCount += 1
                throw error
            }
        }
        return suggestion(for: text)
    }
}

private actor CoordinatorRulesOnlyService: SelectionCorrectionService {
    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        .unchanged(text)
    }
}

private actor CoordinatorRulesSuggestionService: SelectionCorrectionService {
    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        suggestion(for: text)
    }
}

private actor CoordinatorSafeModeService: SelectionCorrectionService {
    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection {
        .unchanged(text)
    }

    func engineUnavailableMessage() async -> String? {
        SafeModeState.localCleanupUnavailableMessage
    }
}

private func suggestion(for text: String) -> SelectionCorrection {
    SelectionCorrection(
        original: text,
        corrected: text + ".",
        changes: [TextChange(range: NSRange(location: (text as NSString).length, length: 0), replacement: ".")]
    )
}

@MainActor
private final class CoordinatorEventMonitor: SelectionEventMonitoring {
    private var continuation: AsyncStream<Void>.Continuation?

    func events() -> AsyncStream<Void> {
        AsyncStream { continuation = $0 }
    }

    func send() { continuation?.yield(()) }
    func stop() { continuation?.finish() }
}

@MainActor
private final class CoordinatorSelectionReader: SelectedTextReading {
    var snapshot: SelectionSnapshot?
    func readSelection() -> SelectionSnapshot? { snapshot }
}

private struct CoordinatorSelectionSettings: SelectionCorrectionSettings {
    let isEnabled = true
    let isClipboardFallbackEnabled = false
    let allowsCloud = false
    let excludedBundleIDs: Set<String> = []
}

private struct CoordinatorDictionary: PersonalDictionary {
    func entries() -> [DictionaryEntry] { [] }
    func replaceEntries(_ entries: [DictionaryEntry]) throws {}
    func addCanonicalTerm(_ canonical: String) throws -> Bool { false }
}

@MainActor
private final class CoordinatorPresenter: SelectionCorrectionPresenting {
    private(set) var presentationCount = 0
    private(set) var dismissCount = 0
    private(set) var lastSnapshot: SelectionSnapshot?
    private(set) var engineUnavailableCount = 0
    private(set) var lastUnavailableMessage: String?

    func present(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        presentationCount += 1
        lastSnapshot = snapshot
    }

    func dismiss() { dismissCount += 1 }

    func presentEngineUnavailable(
        for snapshot: SelectionSnapshot,
        message: String?,
        onActivateCloud: @escaping @MainActor () -> Void,
        onLoadLocal: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        engineUnavailableCount += 1
        lastUnavailableMessage = message
        lastSnapshot = snapshot
    }
}

@MainActor
private struct CoordinatorFixture {
    let coordinator: SelectionCorrectionCoordinator
    let monitor: CoordinatorEventMonitor
    let reader: CoordinatorSelectionReader
    let presenter: CoordinatorPresenter
}
