import XCTest
@testable import OfflineCore
final class TextSegmentsTests: XCTestCase {
    func testLongUnicodeInputIsCoveredExactlyOnceWithinBudget() throws {
        let input = "Первое.\n" + String(repeating: "длинное е\u{301} 👩🏽‍💻 ", count: 300) + "<end_of_turn> конец"
        let parts = try TextSegments.split(input) { $0.utf8.count <= 140 }
        XCTAssertGreaterThan(parts.count, 10)
        XCTAssertEqual(parts.joined(), input)
        XCTAssertTrue(parts.allSatisfy { !$0.isEmpty && $0.utf8.count <= 140 })
    }
    func testImpossibleBudgetThrowsInsteadOfLosingText() {
        XCTAssertThrowsError(try TextSegments.split("Я") { $0.utf8.count <= 1 })
    }
    func testSilenceStopsAtFourSecondsAndSpeechResetsTimer() {
        var monitor = SilenceMonitor()
        XCTAssertFalse(monitor.observe(speech: false, seconds: 3.9))
        XCTAssertFalse(monitor.observe(speech: true, seconds: 0.1))
        XCTAssertFalse(monitor.observe(speech: false, seconds: 3.9))
        XCTAssertTrue(monitor.observe(speech: false, seconds: 0.1))
        XCTAssertFalse(monitor.observe(speech: false, seconds: 1))
        XCTAssertTrue(monitor.heardSpeech)
        var empty = SilenceMonitor()
        XCTAssertTrue(empty.observe(speech: false, seconds: 4))
        XCTAssertFalse(empty.heardSpeech)
    }
    func testCustomSilenceDurationAndInvalidSettings() {
        var long = SilenceMonitor(timeout: 12)
        XCTAssertFalse(long.observe(speech: false, seconds: 5))
        XCTAssertFalse(long.observe(speech: false, seconds: 6.9))
        XCTAssertTrue(long.observe(speech: false, seconds: 0.1))
        var short = SilenceMonitor(timeout: 2)
        XCTAssertFalse(short.observe(speech: false, seconds: 1.9))
        XCTAssertTrue(short.observe(speech: false, seconds: 0.1))
        var invalid = SilenceMonitor(timeout: .nan)
        XCTAssertFalse(invalid.observe(speech: false, seconds: 3.9))
        XCTAssertTrue(invalid.observe(speech: false, seconds: 0.1))
        var zero = SilenceMonitor(timeout: 0)
        XCTAssertFalse(zero.observe(speech: false, seconds: 0.9))
        XCTAssertTrue(zero.observe(speech: false, seconds: 0.1))
    }
}
