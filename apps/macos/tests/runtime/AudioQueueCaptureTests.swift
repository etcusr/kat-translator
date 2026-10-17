import XCTest
import AVFoundation
import OfflineCore
@testable import Kat_translator

final class AudioQueueCaptureTests: XCTestCase {
    func testInterleavedCopyPreservesFirstAndLastSamplesAndOwnsMemory() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true))
        var source: [Float] = [0.75, -0.5, 0.25, -0.125, 0.625, -0.875]
        let buffer = try source.withUnsafeMutableBytes { bytes in
            let copied = try AudioQueueCapture.copyPCM(bytes.baseAddress!, byteCount: bytes.count, capacity: bytes.count, format: format)
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            return copied
        }
        XCTAssertEqual(buffer.frameLength, 3)
        let values = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: values, count: 6)), [0.75, -0.5, 0.25, -0.125, 0.625, -0.875])
    }
    func testInvalidByteCountsDoNotReadPastNativeBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: true))
        let source: [Float] = [1, 2]
        try source.withUnsafeBytes { bytes in
            XCTAssertThrowsError(try AudioQueueCapture.copyPCM(bytes.baseAddress!, byteCount: 12, capacity: 8, format: format))
            XCTAssertThrowsError(try AudioQueueCapture.copyPCM(bytes.baseAddress!, byteCount: 7, capacity: 8, format: format))
            XCTAssertThrowsError(try AudioQueueCapture.copyPCM(bytes.baseAddress!, byteCount: 0, capacity: 8, format: format))
        }
    }
    func testQueueChunksMatchEnginePCMThroughTheSameNormalizer() throws {
        let count = 48017
        let source = (0..<count).map { Float(0.3 * sin(Double($0) * 0.057) + 0.2 * cos(Double($0) * 0.013)) }
        let queueFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: true))
        let engineFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false))
        let enginePCM = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: AVAudioFrameCount(count)))
        enginePCM.frameLength = enginePCM.frameCapacity
        source.withUnsafeBufferPointer { enginePCM.floatChannelData![0].update(from: $0.baseAddress!, count: count) }
        let engineNormalizer = AudioNormalizer()
        let expected = try engineNormalizer.convert(enginePCM) + engineNormalizer.finish()
        let queueNormalizer = AudioNormalizer()
        var actual: [Float] = []
        for start in stride(from: 0, to: count, by: 2048) {
            let chunk = Array(source[start..<min(start + 2048, count)])
            let pcm = try chunk.withUnsafeBytes { try AudioQueueCapture.copyPCM($0.baseAddress!, byteCount: $0.count, capacity: $0.count, format: queueFormat) }
            actual += try queueNormalizer.convert(pcm)
        }
        actual += try queueNormalizer.finish()
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertFalse(actual.isEmpty)
        for (value, reference) in zip(actual, expected) { XCTAssertEqual(value, reference, accuracy: 0.000001) }
    }

}
