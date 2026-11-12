import XCTest
@testable import DictaMac

final class PunctuationNormalizerTests: XCTestCase {
    func testRemovesDoubledAndConflictingPunctuation() {
        XCTAssertEqual(
            PunctuationNormalizer.normalize("bonjour,, tu peux venir?."),
            "Bonjour, tu peux venir ?"
        )
    }

    func testConvertsParasiticEllipsesToPeriods() {
        XCTAssertEqual(
            PunctuationNormalizer.normalize("je pense... que nous pouvons partir"),
            "Je pense. Que nous pouvons partir"
        )
        XCTAssertEqual(
            PunctuationNormalizer.normalize("donc … on se retrouve demain"),
            "Donc. On se retrouve demain"
        )
    }

    func testPreservesSpokenFinalEllipsis() {
        XCTAssertEqual(
            PunctuationNormalizer.normalize("je ne sais pas points de suspension"),
            "Je ne sais pas…"
        )
    }

    func testAppliesFrenchSpacing() {
        XCTAssertEqual(
            PunctuationNormalizer.normalize("bonjour , attention: vraiment !"),
            "Bonjour, attention : vraiment !"
        )
    }

    func testConvertsQuotationMarksToFrenchQuotes() {
        XCTAssertEqual(
            PunctuationNormalizer.normalize("il a dit \"bonjour\"."),
            "Il a dit « bonjour »."
        )
        XCTAssertEqual(
            PunctuationNormalizer.normalize("“bonjour” !"),
            "« Bonjour » !"
        )
    }
}
