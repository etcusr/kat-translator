import XCTest
import AVFoundation
@testable import OfflineCore

final class AudioFileImportTests: XCTestCase {
    private func fixture(seconds: Double, rate: Double = 48000, channels: AVAudioChannelCount = 2, compressed: Bool = false) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(compressed ? "m4a" : "wav")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false))
        let settings: [String: Any] = compressed
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 128000]
            : format.settings
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let count = AVAudioFrameCount(seconds * rate)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, count)))
        pcm.frameLength = count
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(count) {
                pcm.floatChannelData![channel][frame] = 0.25 * sin(Float(frame) * 2 * .pi * 440 / Float(rate))
            }
        }
        if count > 0 { try file.write(from: pcm) }
        return url
    }

    func testStereoFilePreservesWholeRecordingAndConvertsTo16kMono() throws {
        let url = try fixture(seconds: 1.35, rate: 44100)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try Data(contentsOf: url)
        let audio = try AudioFileImport.read(url)
        XCTAssertEqual(audio.samples.count, 21600, accuracy: 2)
        XCTAssertEqual(audio.durationSeconds, 1.35, accuracy: 0.001)
        XCTAssertGreaterThan(audio.samples.suffix(1000).map(abs).max() ?? 0, 0.2, "The final block/decoder tail must survive")
        XCTAssertTrue(audio.samples.allSatisfy(\.isFinite))
        XCTAssertEqual(try Data(contentsOf: url), original, "Import must not modify the user's file")
    }

    func testCompressedM4AIsDecodedBeforeRecognition() throws {
        let url = try fixture(seconds: 2, compressed: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let audio = try AudioFileImport.read(url)
        XCTAssertEqual(audio.durationSeconds, 2, accuracy: 0.06)
        XCTAssertGreaterThan(audio.samples.suffix(1600).map(abs).max() ?? 0, 0.15)
    }

    func testMP3DecodedDurationPreservesBothSentences() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "audio-import", withExtension: "mp3"))
        let audio = try AudioFileImport.read(url)
        XCTAssertEqual(audio.durationSeconds, 5.014, accuracy: 0.1)
        XCTAssertGreaterThan(audio.samples.map(abs).max() ?? 0, 0.1)
    }

    func testTooLongFileIsRejectedRatherThanSilentlyTruncated() throws {
        let url = try fixture(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try AudioFileImport.read(url, maximumSeconds: 1)) {
            guard case AudioFileImportError.tooLong = $0 else { return XCTFail("Expected a duration error, got \($0)") }
        }
    }

    func testEmptyAndInvalidFilesFailWithoutStartingRecognition() throws {
        let empty = try fixture(seconds: 0)
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        defer { try? FileManager.default.removeItem(at: empty); try? FileManager.default.removeItem(at: invalid) }
        try Data("not an audio file".utf8).write(to: invalid)
        XCTAssertThrowsError(try AudioFileImport.read(empty)) {
            guard case AudioFileImportError.tooShort = $0 else { return XCTFail("Expected empty audio rejection") }
        }
        XCTAssertThrowsError(try AudioFileImport.read(invalid)) {
            guard case AudioFileImportError.unreadable = $0 else { return XCTFail("Expected unsupported/damaged file rejection") }
        }
    }

    func testCancelledImportDoesNotOpenTheFile() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AudioFileImport.read(URL(fileURLWithPath: "/nonexistent-audio.wav"))
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Expected cancellation before file access, got \(error)") }
    }
}
