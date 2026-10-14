import XCTest
@testable import OfflineCore
final class SpeechSilenceLimiterTests: XCTestCase {
    func testLongPauseBecomesOneSecondWithoutLosingSpeech() {
        let source = [Float](repeating: 0.4, count: 1000) + [Float](repeating: 0, count: 3000) + [Float](repeating: -0.4, count: 1000)
        let result = SpeechSilenceLimiter.compact(SpeechPCM(samples: source, sampleRate: 1000))
        XCTAssertEqual(result.samples.count, 3000)
        XCTAssertEqual(Array(result.samples.prefix(1000)), [Float](repeating: 0.4, count: 1000))
        XCTAssertEqual(Array(result.samples.suffix(1000)), [Float](repeating: -0.4, count: 1000))
    }
    func testNaturalPauseAndQuietButAudibleSpeechArePreserved() {
        let source = [Float](repeating: 0.004, count: 2000) + [Float](repeating: 0, count: 600) + [Float](repeating: 0.1, count: 1000)
        XCTAssertEqual(SpeechSilenceLimiter.compact(SpeechPCM(samples: source, sampleRate: 1000)).samples, source)
    }
    func testEdgePaddingIsBoundedForConsecutiveFragments() {
        let source = [Float](repeating: 0, count: 2000) + [Float](repeating: 0.2, count: 1000) + [Float](repeating: 0, count: 2000)
        XCTAssertEqual(SpeechSilenceLimiter.compact(SpeechPCM(samples: source, sampleRate: 1000)).samples.count, 1160)
    }
}
