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
    func testRecordingGainCoversQuietLevelsAndPreservesRelativeDynamics() throws {
        for amplitude: Float in [0.002, 0.006, 0.025, 0.1] {
            var input = (0..<32000).map { sin(Float($0) * 0.17) * amplitude }
            input[100] = 0.9; input[101] = -0.9
            let gain = try XCTUnwrap(SpeechLoudness.recordingGain(for: input, sampleRate: 16000))
            XCTAssertGreaterThan(gain, 1)
            XCTAssertLessThanOrEqual(gain, 100)
            let result = input.map { SpeechLoudness.recordingAdjusted($0, gain: gain) }
            let voice = result[1000..<30000]
            let rms = sqrt(voice.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(voice.count))
            XCTAssertGreaterThan(rms, 0.13)
            XCTAssertLessThan(rms, 0.18)
            XCTAssertTrue(result.allSatisfy { $0.isFinite && abs($0) <= 0.70 })
            // Appending silence must not make the same phrase louder.
            let padded = try XCTUnwrap(SpeechLoudness.recordingGain(for: input + [Float](repeating: 0, count: 640000), sampleRate: 16000))
            XCTAssertEqual(gain, padded, accuracy: gain * 0.01)
        }
    }
    func testRecordingLeavesSilenceNoiseFloorAndLoudInputAlone() {
        for value: Float in [0, 0.0001, 0.0009, 0.3] {
            XCTAssertNil(SpeechLoudness.recordingGain(for: [Float](repeating: value, count: 32000), sampleRate: 16000))
        }
        var nearSilent = [Float](repeating: 0.0001, count: 32000)
        nearSilent[100] = 0.9
        XCTAssertNil(SpeechLoudness.recordingGain(for: nearSilent, sampleRate: 16000))
        XCTAssertNil(SpeechLoudness.recordingGain(for: [.nan], sampleRate: 16000))
        XCTAssertNil(SpeechLoudness.recordingGain(for: [.infinity], sampleRate: 16000))
        XCTAssertNil(SpeechLoudness.recordingGain(for: [0.1], sampleRate: 0))
    }

}
