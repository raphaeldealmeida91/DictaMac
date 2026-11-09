import XCTest
@testable import DictaMac

final class DictationSessionPolicyTests: XCTestCase {
    func testCancellationInvalidatesAnInFlightTranscription() throws {
        var policy = DictationSessionPolicy()
        let generation = try XCTUnwrap(policy.beginRecording())
        XCTAssertTrue(policy.beginTranscription(for: generation, reason: .released))

        XCTAssertTrue(policy.cancel())
        XCTAssertEqual(policy.state, .idle)
        XCTAssertFalse(policy.beginInjection(for: generation))

        policy.complete(generation: generation)
        XCTAssertEqual(policy.state, .idle)
    }

    func testMaximumDurationStopsRecordingCleanly() throws {
        var policy = DictationSessionPolicy()
        let generation = try XCTUnwrap(policy.beginRecording())

        XCTAssertTrue(policy.beginTranscription(for: generation, reason: .maximumDuration))
        XCTAssertEqual(policy.state, .transcribing)
        XCTAssertEqual(policy.lastStopReason, .maximumDuration)
    }

    func testNewPressIsIgnoredUntilPreviousDictationCompletes() throws {
        var policy = DictationSessionPolicy()
        let generation = try XCTUnwrap(policy.beginRecording())
        XCTAssertTrue(policy.beginTranscription(for: generation, reason: .released))
        XCTAssertNil(policy.beginRecording())

        policy.complete(generation: generation)
        XCTAssertNotNil(policy.beginRecording())
    }
}
