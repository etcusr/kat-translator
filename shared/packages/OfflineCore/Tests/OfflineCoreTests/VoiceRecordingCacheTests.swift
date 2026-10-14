import XCTest
import AVFoundation
@testable import OfflineCore

@MainActor final class VoiceRecordingCacheTests: XCTestCase {
    func testQuietRecordingExportIsLouderWithoutClippingOrChangingCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = VoiceRecordingCache(root: root.appendingPathComponent("cache"))
        var input = (0..<32000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16000)) * 0.025 }
        input[16000] = 0.99; input[16001] = -0.99
        let audio = CapturedAudio(samples: input)
        try await cache.replace(with: audio)
        let shared = try XCTUnwrap(cache.copy(into: root.appendingPathComponent("share")))
        let file = try AVAudioFile(forReading: shared)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
        let quiet = samples[2000..<14000]
        let rms = sqrt(quiet.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(quiet.count))
        XCTAssertGreaterThan(rms, 0.06, "The actual exported AAC must raise quiet speech, not just the player volume")
        XCTAssertLessThan(rms, 0.09)
        XCTAssertLessThan(samples.map(abs).max()!, 1, "Leave headroom for AAC peaks")
        XCTAssertEqual(Double(buffer.frameLength) / file.processingFormat.sampleRate, 2, accuracy: 0.1)
        XCTAssertEqual(audio.samples, input, "Recognition must retain the unprocessed microphone samples")
    }
    func testReplacementCleanupAndInvalidAudioCannotExposePreviousRecording() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = VoiceRecordingCache(root: root)
        try await cache.replace(with: CapturedAudio(samples: Array(repeating: 0.1, count: 16000)))
        let old = try XCTUnwrap(cache.url)
        try await cache.replace(with: CapturedAudio(samples: Array(repeating: 0.2, count: 32000)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        let latest = try XCTUnwrap(cache.url)
        let audio = try AVAudioFile(forReading: latest)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 2, accuracy: 0.1)
        do { try await cache.replace(with: CapturedAudio(samples: [.nan])); XCTFail("Invalid audio accepted") }
        catch {}
        XCTAssertNil(cache.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: latest.path))
        cache.clear(); XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testHistoryHonorsOptOutAndTextPrivacyAndOwnsAnIndependentCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = VoiceRecordingCache(root: root.appendingPathComponent("cache"))
        try await cache.replace(with: CapturedAudio(samples: Array(repeating: 0.1, count: 16000)))
        let original = try XCTUnwrap(cache.url), historyRoot = root.appendingPathComponent("history")
        let store = TranslationHistory(root: historyRoot)
        await store.setRecording(text: true, audio: false)
        let disabled = try await store.saveOriginalRecording(original, text: "Private", language: .english)
        XCTAssertNil(disabled)
        await store.setRecording(text: false, audio: true)
        let saved = try await store.saveOriginalRecording(original, text: "Private", language: .english)
        let id = try XCTUnwrap(saved)
        cache.clear()
        let restored = TranslationHistory(root: historyRoot)
        let entries = try await restored.list()
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?.kind, .originalRecording)
        XCTAssertNil(entries.first?.text); XCTAssertEqual(entries.first?.source, .english)
        let copy = try await restored.copyAudio(id, into: root.appendingPathComponent("share"))
        XCTAssertGreaterThan(try AVAudioFile(forReading: copy).length, 0)
        let index = try String(contentsOf: historyRoot.appendingPathComponent("history.json"))
        XCTAssertFalse(index.contains("Private"))
        try await restored.setPolicy(HistoryPolicy(audioDays: 1), now: Date().addingTimeInterval(2 * 86400))
        let expired = try await restored.list(); XCTAssertTrue(expired.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyRoot.appendingPathComponent(id.uuidString + ".m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }
}
