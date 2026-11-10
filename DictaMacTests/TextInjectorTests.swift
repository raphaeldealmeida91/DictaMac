import AppKit
import XCTest
@testable import DictaMac

@MainActor
final class ClipboardTextInjectorTests: XCTestCase {
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func testRestoresEveryTypeOfEveryItem() throws {
        let originalItems = [
            PasteboardItemContents(representations: [
                .string: Data("texte".utf8),
                .html: Data("<b>texte</b>".utf8)
            ]),
            PasteboardItemContents(representations: [
                .png: Data([0x89, 0x50, 0x4E, 0x47]),
                NSPasteboard.PasteboardType("com.example.custom"): Data([1, 2, 3])
            ])
        ]
        let pasteboard = FakePasteboard(items: originalItems)
        let scheduler = ManualRestoreScheduler()
        var pasteCount = 0
        let injector = makeInjector(pasteboard: pasteboard, scheduler: scheduler, pasteCommand: {
            pasteCount += 1
        })

        XCTAssertEqual(injector.insert("dictée"), .pasted)

        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.items.count, 1)
        XCTAssertEqual(pasteboard.items[0].representations[.string], Data("dictée".utf8))
        XCTAssertNotNil(pasteboard.items[0].representations[Self.concealedType])
        XCTAssertNotNil(pasteboard.items[0].representations[Self.transientType])

        scheduler.run()

        XCTAssertEqual(pasteboard.items, originalItems)
    }

    func testRestoresAnEmptyPasteboard() throws {
        let pasteboard = FakePasteboard(items: [])
        let scheduler = ManualRestoreScheduler()
        let injector = makeInjector(pasteboard: pasteboard, scheduler: scheduler)

        XCTAssertEqual(injector.insert("dictée"), .pasted)
        XCTAssertFalse(pasteboard.items.isEmpty)

        scheduler.run()

        XCTAssertTrue(pasteboard.items.isEmpty)
    }

    func testDoesNotRestoreAfterAnExternalChange() throws {
        let original = [PasteboardItemContents(representations: [.string: Data("avant".utf8)])]
        let external = [PasteboardItemContents(representations: [.string: Data("copie utilisateur".utf8)])]
        let pasteboard = FakePasteboard(items: original)
        let scheduler = ManualRestoreScheduler()
        let injector = makeInjector(pasteboard: pasteboard, scheduler: scheduler)

        XCTAssertEqual(injector.insert("dictée"), .pasted)
        pasteboard.simulateExternalWrite(external)
        let writesBeforeRestore = pasteboard.replaceCallCount

        scheduler.run()

        XCTAssertEqual(pasteboard.items, external)
        XCTAssertEqual(pasteboard.replaceCallCount, writesBeforeRestore)
    }

    func testKeepsTextInClipboardWhenSecureInputPreventsPaste() {
        let pasteboard = FakePasteboard(items: [])
        let scheduler = ManualRestoreScheduler()
        let injector = makeInjector(
            pasteboard: pasteboard,
            scheduler: scheduler,
            canPasteIntoFocusedElement: { false }
        )

        XCTAssertEqual(injector.insert("à coller"), .copiedToClipboard)
        scheduler.run()
        XCTAssertEqual(pasteboard.items.first?.representations[.string], Data("à coller".utf8))
    }

    func testAttemptsPasteWithoutAnAXCompatibleFocusedElement() {
        let pasteboard = FakePasteboard(items: [])
        let scheduler = ManualRestoreScheduler()
        var pasteCount = 0
        let injector = makeInjector(
            pasteboard: pasteboard,
            scheduler: scheduler,
            canPasteIntoFocusedElement: { true },
            pasteCommand: { pasteCount += 1 }
        )

        XCTAssertEqual(injector.insert("champ web"), .pasted)
        XCTAssertEqual(pasteCount, 1)
    }

    func testKeepsTextInClipboardWhenPasteCommandFails() {
        let pasteboard = FakePasteboard(items: [])
        let scheduler = ManualRestoreScheduler()
        let injector = makeInjector(pasteboard: pasteboard, scheduler: scheduler, pasteCommand: {
            throw TextInjectionError.eventCreationFailed
        })

        XCTAssertEqual(injector.insert("à coller"), .copiedToClipboard)
        scheduler.run()
        XCTAssertEqual(pasteboard.items.first?.representations[.string], Data("à coller".utf8))
    }

    func testInjectedPermissionCacheControlsPasteDecision() {
        let pasteboard = FakePasteboard(items: [])
        let scheduler = ManualRestoreScheduler()
        let permissionCache = PermissionStateCache()
        let injector = makeInjector(
            pasteboard: pasteboard,
            scheduler: scheduler,
            permissionCache: permissionCache
        )

        XCTAssertEqual(injector.insert("sans permission"), .copiedToClipboard)
        permissionCache.updateAccessibility(true)
        XCTAssertEqual(injector.insert("avec permission"), .pasted)
    }

    func testDirectPermissionCheckRecoversFromStaleDeniedCache() {
        let pasteboard = FakePasteboard(items: [])
        let scheduler = ManualRestoreScheduler()
        let permissionCache = PermissionStateCache()
        let injector = makeInjector(
            pasteboard: pasteboard,
            scheduler: scheduler,
            permissionCache: permissionCache,
            accessibilityIsTrusted: { true }
        )

        XCTAssertEqual(injector.insert("permission accordée"), .pasted)
    }

    private func makeInjector(
        pasteboard: FakePasteboard,
        scheduler: ManualRestoreScheduler,
        permissionCache: PermissionStateCache? = nil,
        accessibilityIsTrusted: @escaping ClipboardTextInjector.AccessibilityTrustCheck = { false },
        canPasteIntoFocusedElement: @escaping @MainActor () -> Bool = { true },
        pasteCommand: @escaping ClipboardTextInjector.PasteCommand = {}
    ) -> ClipboardTextInjector {
        let resolvedPermissionCache = permissionCache ?? Self.authorizedPermissionCache()
        return ClipboardTextInjector(
            permissionCache: resolvedPermissionCache,
            pasteboard: pasteboard,
            accessibilityIsTrusted: accessibilityIsTrusted,
            canPasteIntoFocusedElement: canPasteIntoFocusedElement,
            pasteCommand: pasteCommand,
            scheduleRestore: scheduler.schedule
        )
    }

    private static func authorizedPermissionCache() -> PermissionStateCache {
        let cache = PermissionStateCache()
        cache.updateAccessibility(true)
        return cache
    }
}

@MainActor
private final class FakePasteboard: PasteboardProviding {
    private(set) var changeCount = 0
    private(set) var items: [PasteboardItemContents]
    private(set) var replaceCallCount = 0

    init(items: [PasteboardItemContents]) {
        self.items = items
    }

    func readItems() -> [PasteboardItemContents] { items }

    @discardableResult
    func replaceItems(with items: [PasteboardItemContents]) -> Int {
        replaceCallCount += 1
        self.items = items
        changeCount += 1
        return changeCount
    }

    @discardableResult
    func writeTransientText(_ text: String) -> Int {
        items = [PasteboardItemContents(representations: [
            .string: Data(text.utf8),
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"): Data(),
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType"): Data()
        ])]
        changeCount += 1
        return changeCount
    }

    @discardableResult
    func writeText(_ text: String) -> Int {
        items = [PasteboardItemContents(representations: [.string: Data(text.utf8)])]
        changeCount += 1
        return changeCount
    }

    func simulateExternalWrite(_ items: [PasteboardItemContents]) {
        self.items = items
        changeCount += 1
    }
}

@MainActor
private final class ManualRestoreScheduler {
    private var action: (@MainActor () -> Void)?

    func schedule(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func run() {
        let pendingAction = action
        action = nil
        pendingAction?()
    }
}
