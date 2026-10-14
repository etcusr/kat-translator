import XCTest
import AVFoundation
@testable import OfflineCore
final class TranslationHistoryTests: XCTestCase {
    func testOriginalSpeechPublishesOnlyCompleteAudioAndRespectsRecordingSettings() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        let pending = try await store.saveOriginalSpeech(text: "Привет", language: .russian)
        let id = try XCTUnwrap(pending)
        var entries = try await store.list(); XCTAssertTrue(entries.isEmpty)
        try await store.appendAudio(pcm, to: id)
        await store.abortAudio(id)
        entries = try await store.list(); XCTAssertTrue(entries.isEmpty)
        let index = try String(contentsOf: root.appendingPathComponent("history.json"))
        XCTAssertFalse(index.contains(id.uuidString))

        await store.setRecording(text: true, audio: false)
        let disabled = try await store.saveOriginalSpeech(text: "Не сохранять", language: .russian)
        XCTAssertNil(disabled)
        await store.setRecording(text: false, audio: true)
        let saved = try await store.saveOriginalSpeech(text: "Секрет", language: .russian)
        let completed = try XCTUnwrap(saved)
        try await store.appendAudio(pcm, to: completed); try await store.finishAudio(completed)
        entries = try await TranslationHistory(root: root).list()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .originalSpeech)
        XCTAssertEqual(entries.first?.source, .russian)
        XCTAssertEqual(entries.first?.target, .russian)
        XCTAssertNil(entries.first?.text)
        let file = try await store.copyAudio(completed, into: root.appendingPathComponent("share"))
        XCTAssertGreaterThan(try AVAudioFile(forReading: file).length, 0)
    }
    func testImageHistorySurvivesRestartSharesAndPrunesIndependently() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        // A valid one-pixel PNG is enough to exercise storage without UI or a model.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let saved = try await store.saveImage(png, original: "hello", translation: "привет", source: .english, target: .russian)
        let id = try XCTUnwrap(saved)
        let restored = TranslationHistory(root: root)
        let entries = try await restored.list()
        XCTAssertEqual(entries.first?.kind, .imageTranslation)
        XCTAssertEqual(entries.first?.hasImage, true)
        XCTAssertEqual(entries.first?.text?.translation, "привет")
        let copy = try await restored.copyImage(id, into: root.appendingPathComponent("share"))
        XCTAssertEqual(try Data(contentsOf: copy), png)
        try await restored.setPolicy(HistoryPolicy(textCount: 100, imageCount: 1))
        _ = try await restored.saveImage(png, original: "second", translation: "второй", source: .english, target: .russian)
        let pruned = try await restored.list()
        XCTAssertEqual(pruned.filter(\.hasImage).count, 1)
        XCTAssertEqual(pruned.first(where: { $0.id == id })?.text?.translation, "привет")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString + ".png").path))
        XCTAssertEqual(try Data(contentsOf: copy), png, "A shared copy survives retention")
        try await restored.removeAll()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".png") })
    }
    func testImageRecordingOptOutAndFailedCommitLeaveNoImage() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let writer = FailingIndexWriter()
        let store = TranslationHistory(root: root, indexWriter: { try writer.write($0, to: $1) })
        await store.setRecording(text: false, audio: true, images: false)
        let skipped = try await store.saveImage(png, original: "private", translation: "secret", source: .english, target: .russian)
        XCTAssertNil(skipped)
        await store.setRecording(text: false, audio: false, images: true)
        writer.failAfterSuccessfulWrites(0)
        do {
            _ = try await store.saveImage(png, original: "private", translation: "secret", source: .english, target: .russian)
            XCTFail("Expected write failure")
        } catch {}
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".png") })
        _ = try await store.saveImage(png, original: "private", translation: "secret", source: .english, target: .russian)
        let entries = try await store.list()
        XCTAssertEqual(entries.count, 1); XCTAssertNil(entries.first?.text); XCTAssertEqual(entries.first?.hasImage, true)
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private var pcm: SpeechPCM { SpeechPCM(samples: (0..<22050).map { sin(Float($0) * 0.05) * 0.2 }, sampleRate: 22050) }
    func testDisablingBothHistoriesDoesNotSaveNewDataOrDeleteExistingEntries() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        let old = try await store.save(original: "old", translation: "old", source: .russian)
        await store.setRecording(text: false, audio: false)
        let skipped = try await store.save(original: "private", translation: "private", source: .russian)
        XCTAssertNil(skipped)
        let entries = try await store.list()
        XCTAssertEqual(entries.map(\.id), [try XCTUnwrap(old)])
        let index = try String(contentsOf: root.appendingPathComponent("history.json"), encoding: .utf8)
        XCTAssertFalse(index.contains("private"))
    }
    func testAudioOnlyNeverPersistsTextAndSurvivesRestart() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        await store.setRecording(text: false, audio: true)
        let saved = try await store.save(original: "private", translation: "secret", source: .russian)
        let id = try XCTUnwrap(saved)
        let unfinished = try await store.list(); XCTAssertTrue(unfinished.isEmpty)
        try await store.appendAudio(pcm, to: id); try await store.finishAudio(id)
        let entries = try await TranslationHistory(root: root).list()
        XCTAssertEqual(entries.count, 1); XCTAssertNil(entries.first?.text); XCTAssertEqual(entries.first?.hasAudio, true)
        let index = try String(contentsOf: root.appendingPathComponent("history.json"), encoding: .utf8)
        XCTAssertFalse(index.contains("private")); XCTAssertFalse(index.contains("secret"))
    }
    func testTextOnlySkipsAudioWithoutAnArchiveErrorAndCanBeReenabled() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        await store.setRecording(text: true, audio: false)
        let saved = try await store.save(original: "a", translation: "b", source: .russian)
        let id = try XCTUnwrap(saved)
        try await store.appendAudio(pcm, to: id); try await store.finishAudio(id)
        let entries = try await store.list()
        XCTAssertEqual(entries.first?.text?.translation, "b"); XCTAssertEqual(entries.first?.hasAudio, false)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix("m4a") })
        await store.setRecording(text: true, audio: true)
        try await store.appendAudio(pcm, to: id); try await store.finishAudio(id)
        let restored = try await store.list(); XCTAssertEqual(restored.first?.hasAudio, true)
    }
    func testClearRemovesTextCompleteAndPartialAudioAndAllowsNewHistory() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        let first = try await store.save(original: "first", translation: "first", source: .russian)
        let a = try XCTUnwrap(first)
        try await store.appendAudio(pcm, to: a); try await store.finishAudio(a)
        let second = try await store.save(original: "second", translation: "second", source: .english)
        try await store.appendAudio(pcm, to: XCTUnwrap(second))
        let unrelated = root.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: unrelated)
        try await store.removeAll()
        let entries = try await TranslationHistory(root: root).list(); XCTAssertTrue(entries.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(files.contains { $0.hasSuffix("m4a") }); XCTAssertTrue(files.contains("keep.txt"))
        let next = try await store.save(original: "new", translation: "new", source: .english)
        let newEntries = try await store.list(); XCTAssertEqual(newEntries.map(\.id), [try XCTUnwrap(next)])
    }
    func testFailedClearIndexWritePreservesExistingAudio() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = FailingIndexWriter()
        let store = TranslationHistory(root: root, indexWriter: { try writer.write($0, to: $1) })
        let saved = try await store.save(original: "a", translation: "b", source: .russian)
        let id = try XCTUnwrap(saved)
        try await store.appendAudio(pcm, to: id); try await store.finishAudio(id)
        writer.failAfterSuccessfulWrites(0)
        do { try await store.removeAll(); XCTFail("Expected write failure") }
        catch { XCTAssertEqual((error as NSError).domain, "InjectedIndexFailure") }
        let restored = TranslationHistory(root: root)
        let entries = try await restored.list(); XCTAssertEqual(entries.first?.hasAudio, true)
        let copy = try await restored.copyAudio(id, into: root.appendingPathComponent("exports"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }
    func testNewVoiceSampleRatesCanBeArchivedAndShared() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        for rate in [22050, 44100] {
            let id = try await store.save(original: "a", translation: "b", source: .english, target: .thai)!
            let pcm = SpeechPCM(samples: (0..<rate).map { sin(Float($0) * 0.05) * 0.2 }, sampleRate: rate)
            try await store.appendAudio(pcm, to: id); try await store.finishAudio(id)
            let copy = try await store.copyAudio(id, into: root.appendingPathComponent("exports"))
            let audio = try AVAudioFile(forReading: copy)
            XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 1, accuracy: 0.1)
        }
    }
    func testOldHistoryWithoutTargetStillDecodesAndNewTargetSurvivesRestart() async throws {
        let old = "[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"createdAt\":0,\"source\":\"en\",\"hasAudio\":false,\"text\":{\"original\":\"Hello\",\"translation\":\"Привет\"}}]"
        let entries = try JSONDecoder().decode([HistoryEntry].self, from: Data(old.utf8))
        XCTAssertEqual(entries.first?.target, .russian)
        XCTAssertEqual(entries.first?.kind, .translation)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        _ = try await store.save(original: "Bonjour", translation: "こんにちは", source: .french, target: .japanese)
        let restored = try await TranslationHistory(root: root).list()
        XCTAssertEqual(restored.first?.source, .french)
        XCTAssertEqual(restored.first?.target, .japanese)
    }
    func testTextSurvivesRestartAndIndependentAudioLimit() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        try await store.setPolicy(HistoryPolicy(textCount: 100, audioCount: 1))
        let a = try await store.save(original: "a", translation: "A", source: .russian)!
        try await store.appendAudio(pcm, to: a); try await store.finishAudio(a)
        let b = try await store.save(original: "b", translation: "B", source: .english)!
        try await store.appendAudio(pcm, to: b); try await store.finishAudio(b)
        let list = try await TranslationHistory(root: root).list()
        XCTAssertEqual(list.count, 2); XCTAssertEqual(list.filter(\.hasAudio).map(\.id), [b])
        XCTAssertEqual(list.first(where: { $0.id == a })?.text?.translation, "A")
    }
    func testAgeZeroKeepsOldTextButCountStillApplies() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root); let now = Date(timeIntervalSince1970: 2_000_000_000)
        try await store.setPolicy(HistoryPolicy(textCount: 1, textDays: 0), now: now)
        _ = try await store.save(original: "old", translation: "old", source: .russian, now: now.addingTimeInterval(-400*86400))
        let b = try await store.save(original: "new", translation: "new", source: .russian, now: now.addingTimeInterval(-399*86400))!
        try await store.prune(now: now)
        let list = try await store.list(); XCTAssertEqual(list.map(\.id), [b])
        try await store.setPolicy(HistoryPolicy(textDays: 30), now: now)
        let expired = try await store.list(); XCTAssertTrue(expired.isEmpty)
    }
    func testM4AContainsAllChunksAndShareCopySurvivesDeletion() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        let id = try await store.save(original: "a", translation: "A", source: .russian)!
        try await store.appendAudio(pcm, to: id); try await store.appendAudio(pcm, to: id); try await store.finishAudio(id)
        let copy = try await store.copyAudio(id, into: root.appendingPathComponent("exports"))
        try await store.remove(id)
        let audio = try AVAudioFile(forReading: copy)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 2, accuracy: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }
    func testCancelledAudioKeepsTextAndNeverPublishesPartialFile() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        let id = try await store.save(original: "a", translation: "A", source: .russian)!
        try await store.appendAudio(pcm, to: id); await store.abortAudio(id)
        let entries = try await store.list(); XCTAssertFalse(try XCTUnwrap(entries.first).hasAudio)
        XCTAssertEqual(entries.first?.text?.translation, "A")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString + ".partial.m4a").path))
    }
    func testPruningWriteFailureDoesNotDeleteCommittedAudio() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = FailingIndexWriter()
        let store = TranslationHistory(root: root, indexWriter: { try writer.write($0, to: $1) })
        let id = try await store.save(original: "a", translation: "A", source: .russian)!
        try await store.appendAudio(pcm, to: id)
        writer.failAfterSuccessfulWrites(1)
        do { try await store.finishAudio(id); XCTFail("Expected pruning write failure") }
        catch { XCTAssertEqual((error as NSError).domain, "InjectedIndexFailure") }
        // Both the committed index and the finished audio must survive a failed retention write.
        let restarted = TranslationHistory(root: root)
        let entries = try await restarted.list()
        XCTAssertTrue(try XCTUnwrap(entries.first).hasAudio)
        let copy = try await restarted.copyAudio(id, into: root.appendingPathComponent("exports"))
        let audio = try AVAudioFile(forReading: copy)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 1, accuracy: 0.1)
    }
}

private final class FailingIndexWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int?
    func failAfterSuccessfulWrites(_ count: Int) { lock.lock(); defer { lock.unlock() }; remaining = count }
    func write(_ data: Data, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        if let count = remaining {
            if count == 0 { remaining = nil; throw NSError(domain: "InjectedIndexFailure", code: 1) }
            remaining = count - 1
        }
        try data.write(to: url, options: .atomic)
    }
}
