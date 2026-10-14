import XCTest
@testable import OfflineCore
final class SpeechLoudnessTests: XCTestCase {
    func testQuietSpeechIsRaisedWithoutChangingTiming() {
        let samples = (0..<24000).map { Float(sin(Double($0) * 0.12)) * 0.04 }
        let result = SpeechLoudness.normalize(SpeechPCM(samples: samples, sampleRate: 24000))
        XCTAssertEqual(result.samples.count, samples.count); XCTAssertEqual(result.sampleRate, 24000)
        XCTAssertGreaterThan(result.samples.map(abs).max()!, 0.14)
        XCTAssertLessThanOrEqual(result.samples.map(abs).max()!, 0.161)
    }
    func testIsolatedPeaksDoNotPreventGainAndRemainBelowCeiling() {
        var samples = (0..<24000).map { Float(sin(Double($0) * 0.12)) * 0.04 }
        samples[100] = 0.99; samples[101] = -0.99
        let result = SpeechLoudness.normalize(SpeechPCM(samples: samples, sampleRate: 24000))
        XCTAssertGreaterThan(abs(result.samples[20]), abs(samples[20]) * 2)
        XCTAssertTrue(result.samples.allSatisfy { $0.isFinite && abs($0) <= 0.89 })
        XCTAssertGreaterThan(result.samples[100], 0); XCTAssertLessThan(result.samples[101], 0)
    }
    func testSilenceRemainsSilentAndAlreadyLoudAudioIsNotAmplified() {
        XCTAssertEqual(SpeechLoudness.normalize(SpeechPCM(samples: [Float](repeating: 0, count: 1000), sampleRate: 24000)).samples, [Float](repeating: 0, count: 1000))
        let loud = [Float](repeating: 0.3, count: 1000)
        XCTAssertEqual(SpeechLoudness.normalize(SpeechPCM(samples: loud, sampleRate: 24000)).samples, loud)
    }
}
