import XCTest
import AVFoundation
@testable import OfflineCore
final class AudioNormalizerTests: XCTestCase {
    func testStereo48kBecomesMono16kWithSignalPreserved() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for channel in 0..<2 {
            for frame in 0..<48000 { buffer.floatChannelData![channel][frame] = 0.25 * sin(Float(frame) * 2 * .pi * 440 / 48000) }
        }
        let normalizer = AudioNormalizer()
        let output = try normalizer.convert(buffer) + normalizer.finish()
        XCTAssertEqual(output.count, 16000, accuracy: 100)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(output.map { abs($0) }.max() ?? 0, 0.2)
    }
    func testMono16kIsNotDroppedOrDuplicated() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        buffer.frameLength = 1600
        for i in 0..<1600 { buffer.floatChannelData![0][i] = 0.125 }
        let converter = AudioNormalizer()
        let first = try converter.convert(buffer); let second = try converter.convert(buffer)
        XCTAssertEqual(first.count + second.count, 3200)
        XCTAssertEqual(first.first ?? 0, 0.125, accuracy: 0.001)
    }
    func testEmptyBufferDoesNotInventSamples() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
        XCTAssertTrue(try AudioNormalizer().convert(buffer).isEmpty)
    }
}
