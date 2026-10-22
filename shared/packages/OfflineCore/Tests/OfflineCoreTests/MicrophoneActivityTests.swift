import XCTest
@testable import OfflineCore

final class MicrophoneActivityTests: XCTestCase {
    func testSilenceAndInvalidSamplesAreQuietAndFinite() {
        for samples: [Float] in [[], [0, 0], [.nan, .infinity, -.infinity]] {
            let value = MicrophoneActivity(samples: samples, speechDetected: false)
            XCTAssertEqual(value.level, 0)
            XCTAssertFalse(value.speechDetected)
        }
    }
    func testInputLevelDoesNotDeclareNoiseToBeSpeech() {
        let noise = MicrophoneActivity(samples: Array(repeating: 0.2, count: 512), speechDetected: false)
        XCTAssertGreaterThan(noise.level, 0.5)
        XCTAssertFalse(noise.speechDetected)
        let quietSpeech = MicrophoneActivity(samples: Array(repeating: 0.005, count: 512), speechDetected: true)
        XCTAssertGreaterThan(quietSpeech.level, 0)
        XCTAssertLessThan(quietSpeech.level, noise.level)
        XCTAssertTrue(quietSpeech.speechDetected)
    }
    func testMeterDoesNotModifyPCMAndClampsClipping() {
        let pcm: [Float] = [-2, -1, 0, 1, 2]
        let original = pcm
        XCTAssertEqual(MicrophoneActivity(samples: pcm, speechDetected: true).level, 1)
        XCTAssertEqual(pcm, original)
    }
}
