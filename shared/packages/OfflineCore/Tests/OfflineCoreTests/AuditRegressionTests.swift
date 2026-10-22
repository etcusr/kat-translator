import XCTest
import AVFoundation
import ImageIO
@testable import OfflineCore

/// Regressions from the 22 October 2026 code audit (docs/maintenance/audit-fix-plan-2026-10-22.md).
/// Each test was first run against the unfixed code to confirm the problem exists.
final class AuditRegressionTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("audit-" + UUID().uuidString) }
    private func tone(seconds: Int, rate: Int = 16000) -> SpeechPCM {
        SpeechPCM(samples: (0..<(seconds * rate)).map { sin(Float($0) * 0.05) * 0.2 }, sampleRate: rate)
    }

    // B1: chunk planning must cost roughly the chunk, not the whole remaining text, per chunk.
    func testChunkPlanningWorkIsLinearInTextLength() throws {
        let sentence = "Это обычное предложение для проверки разбиения длинного текста на части. "
        let text = String(repeating: sentence, count: 280) // ~20 000 characters
        var counted = 0
        let chunks = try TranslationChunks.plan(text, limit: 128, count: { counted += $0.count; return ($0.count + 3) / 4 })
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { ($0.count + 3) / 4 <= 128 })
        XCTAssertLessThan(counted, text.count * 40, "tokenizer work grows quadratically with text length")
    }

    // B2: on a strong device Auto must still use an installed OPUS model when no Index model exists.
    func testAutoOnStrongDeviceFallsBackToInstalledOpus() {
        func resolve(_ s: SpeechLanguage, _ t: SpeechLanguage, installed: Set<TranslationModel>, direction: Bool = false) -> TranslationModel? {
            AutoTranslation.resolve(source: s, target: t, strongDevice: true, installed: { installed.contains($0) }, directionInstalled: { _, _ in direction })
        }
        XCTAssertEqual(resolve(.russian, .english, installed: [.opusBig]), .opusBig)
        XCTAssertEqual(resolve(.russian, .german, installed: [], direction: true), .opusDirections)
        XCTAssertEqual(resolve(.russian, .english, installed: [.opusBig, .index9B]), .index9B)
        XCTAssertNil(resolve(.russian, .japanese, installed: []))
    }

    // B3: an unreadable index must not block history forever; its bytes are kept as a backup.
    func testUnreadableHistoryIndexIsBackedUpAndHistoryKeepsWorking() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appendingPathComponent("history.json"))
        let store = TranslationHistory(root: root)
        let entries = try await store.list()
        XCTAssertTrue(entries.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("history.unreadable-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(backups[0])), "not json")
        let id = try await store.save(original: "a", translation: "b", source: .russian, target: .english)
        XCTAssertNotNil(id)
        try await store.removeAll()
        let cleared = try await store.list()
        XCTAssertTrue(cleared.isEmpty)
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("history.unreadable-") || $0.hasPrefix("Recovered-") }
        XCTAssertTrue(left.isEmpty, "clearing history must also clear recovered copies")
    }

    // B3: one entry of an unknown (newer) kind must not hide the others; its media is not deleted.
    func testUnknownHistoryKindKeepsOtherEntriesAndMedia() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let first = TranslationHistory(root: root)
        _ = try await first.save(original: "one", translation: "1", source: .russian, target: .english)
        let audioID = try await first.save(original: "two", translation: "2", source: .russian, target: .english)!
        try await first.appendAudio(tone(seconds: 1), to: audioID); try await first.finishAudio(audioID)
        let index = root.appendingPathComponent("history.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: index)) as! [[String: Any]]
        var future = json[0]; let futureID = UUID()
        future["id"] = futureID.uuidString; future["storedKind"] = "futureKind"; future["hasAudio"] = true
        json.append(future)
        try JSONSerialization.data(withJSONObject: json).write(to: index)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent(futureID.uuidString + ".m4a"))
        let reopened = TranslationHistory(root: root)
        let entries = try await reopened.list()
        XCTAssertEqual(entries.count, 2)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.contains { $0.hasSuffix(futureID.uuidString + ".m4a") }, "media of an unreadable entry was deleted")
        XCTAssertTrue(files.contains { $0.contains("history.unreadable-") })
    }

    // B4: synthesized speech longer than one minute must be archived and shareable.
    func testHistoryArchivesSpeechLongerThanOneMinute() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationHistory(root: root)
        let id = try await store.save(original: "a", translation: "b", source: .russian, target: .english)!
        try await store.appendAudio(tone(seconds: 90), to: id); try await store.finishAudio(id)
        let copy = try await store.copyAudio(id, into: root.appendingPathComponent("exports"))
        let audio = try AVAudioFile(forReading: copy)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 90, accuracy: 0.5)
    }

    @MainActor func testShareCacheKeepsSpeechLongerThanOneMinute() throws {
        let cache = TextSpeechShareCache(); defer { cache.clear() }
        try cache.begin(text: "b", language: .english, original: false)
        try cache.append(tone(seconds: 90)); cache.finish()
        let out = root(); defer { try? FileManager.default.removeItem(at: out) }
        let copy = try XCTUnwrap(try cache.copy(text: "b", language: .english, original: false, into: out))
        let audio = try AVAudioFile(forReading: copy)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 90, accuracy: 0.5)
    }

    // B10: a microphone on a channel other than the first must not be lost when mixing to mono.
    func testSecondChannelSignalSurvivesMonoConversion() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for frame in 0..<48000 {
            buffer.floatChannelData![0][frame] = 0
            buffer.floatChannelData![1][frame] = 0.5 * sin(Float(frame) * 2 * .pi * 440 / 48000)
        }
        let normalizer = AudioNormalizer()
        let output = try normalizer.convert(buffer) + normalizer.finish()
        XCTAssertGreaterThan(output.map { abs($0) }.max() ?? 0, 0.1, "second-channel speech became silence")
    }
}

/// Reference copy of the planner before the 22 October fix, used to prove identical output.
private enum PreviousChunkPlanner {
    static func plan(_ text: String, limit: Int, count: (String) -> Int) throws -> [String] {
        var rest = text[...], parts: [String] = []
        let sentence = try NSRegularExpression(pattern: #"\n\s*\n|\n|[.!?。！？][\"”’\)]?\s+"#)
        let whitespace = try NSRegularExpression(pattern: #"\s+"#)
        while !rest.isEmpty {
            let value = String(rest)
            if count(value) <= limit { parts.append(value); break }
            let chars = Array(rest)
            var low = 0, high = chars.count
            while low < high {
                let middle = (low + high + 1) / 2
                if count(String(chars.prefix(middle))) <= limit { low = middle } else { high = middle - 1 }
            }
            guard low > 0 else { throw PipelineError.tooLong }
            var bounded = String(chars.prefix(low))
            let range = NSRange(bounded.startIndex..., in: bounded)
            if let match = sentence.matches(in: bounded, range: range).last ?? whitespace.matches(in: bounded, range: range).last,
               let boundary = Range(NSRange(location: 0, length: match.range.upperBound), in: bounded) {
                bounded = String(bounded[boundary])
            }
            while count(bounded) > limit && !bounded.isEmpty { bounded.removeLast() }
            guard !bounded.isEmpty else { throw PipelineError.tooLong }
            parts.append(bounded); rest = rest.dropFirst(bounded.count)
        }
        return parts
    }
}

final class AuditChunkEquivalenceTests: XCTestCase {
    func testFasterPlannerProducesExactlyTheSameChunks() throws {
        var generator = SystemRandomNumberGenerator()
        let words = ["кот", "translation", "猫🙂", "предложение.", "line\n", "para.\n\n", "Mr.", "e.g.", "(test)", "«цитата»", "!", "very-long-hyphenated-word"]
        var inputs = ["First sentence. Second sentence.\nThird line.\n\nNext paragraph.", String(repeating: "猫🙂", count: 400),
                      "  leading and trailing  ", "", String(repeating: "a", count: 3000)]
        for _ in 0..<40 { inputs.append((0..<Int.random(in: 1...600, using: &generator)).map { _ in words.randomElement(using: &generator)! }.joined(separator: " ")) }
        for input in inputs {
            for limit in [5, 17, 128] {
                for count in [{ (s: String) in s.count }, { (s: String) in (s.count + 3) / 4 }, { (s: String) in s.utf8.count / 3 + 1 }] {
                    let old = Result { try PreviousChunkPlanner.plan(input, limit: limit, count: count) }
                    let new = Result { try TranslationChunks.plan(input, limit: limit, count: count) }
                    switch (old, new) {
                    case let (.success(a), .success(b)): XCTAssertEqual(a, b)
                    case (.failure, .failure): break
                    default: XCTFail("planner outcome changed for limit \(limit)")
                    }
                }
            }
        }
    }
    func testPlannerStopsWhenCancelled() {
        var calls = 0
        XCTAssertThrowsError(try TranslationChunks.plan(String(repeating: "Слово ", count: 5000), limit: 16,
                                                         count: { calls += 1; return $0.count }, cancelled: { calls > 3 })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertLessThanOrEqual(calls, 5)
    }
}

// Audit 22.10 (B22): pieces split for the model budget keep the source paragraph and line breaks.
final class AuditTranslationJoinTests: XCTestCase {
    func testJoinerRestoresSourceBoundaries() throws {
        let source = "Первый абзац. Второе предложение.\n\nВторой абзац\nс переносом строки. Конец."
        let pieces = try TextSegments.split(source) { $0.count <= 20 }
        XCTAssertGreaterThan(pieces.count, 2)
        var joiner = TranslationJoiner()
        for piece in pieces {
            let text = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { joiner.skip(piece) } else { joiner.append("[" + text + "]", for: piece) }
        }
        XCTAssertTrue(joiner.text.contains("\n\n"), "paragraph break lost: \(joiner.text)")
        XCTAssertEqual(joiner.text.components(separatedBy: "\n\n").count, 2)
        XCTAssertFalse(joiner.text.hasPrefix(" ") || joiner.text.hasPrefix("\n"))
    }
    func testSkippedWhitespacePieceStillSeparatesParagraphs() {
        var joiner = TranslationJoiner()
        joiner.append("A", for: "A.")
        joiner.skip("\n\n")
        joiner.append("B", for: "B.")
        XCTAssertEqual(joiner.text, "A\n\nB")
    }
}

final class AuditDownloadTests: XCTestCase {
    private let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    // Audit 22.10 (iOS M8): a read failure during startup verification (e.g. a protected file before first
    // unlock) must not delete the receipt of a verified model; only an integrity failure does.
    func testUnreadableModelKeepsReceiptButCorruptionRemovesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("audit-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = ModelDescriptor(id: "audit-model", title: "Audit", remoteURL: URL(string: "https://example.invalid/m.bin")!, byteCount: 3, sha256: abc)
        let staged = root.appendingPathComponent("staged.bin"); try Data("abc".utf8).write(to: staged)
        let store = ModelStore(root: root.appendingPathComponent("Models"))
        let file = try await store.verifyAndInstall(stagingURL: staged, model: model)
        let receipt = root.appendingPathComponent("Models/audit-model.json"), cache = root.appendingPathComponent("Models/audit-model.verified.json")
        try? FileManager.default.removeItem(at: cache)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        _ = try? await store.installedURL(for: model)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path), "A read error deleted the receipt")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let readable = try await store.installedURL(for: model)
        XCTAssertEqual(readable, file)
        try? FileManager.default.removeItem(at: cache); try Data("abd".utf8).write(to: file)
        let corrupt = try await store.installedURL(for: model)
        XCTAssertNil(corrupt); XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
    }
    // Audit 22.10 (iOS M8): temporary assembly folders left by a killed process are removed later.
    func testPackageAssemblyRemovesStaleTemporaryFolders() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("audit-package-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("packages")
        let stale = root.appendingPathComponent("staging-" + UUID().uuidString), piper = root.appendingPathComponent("piper-" + UUID().uuidString)
        let fresh = root.appendingPathComponent("staging-" + UUID().uuidString)
        for folder in [stale, piper, fresh] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(count: 1024).write(to: folder.appendingPathComponent("part.bin"))
        }
        let old = Date().addingTimeInterval(-2 * 86_400)
        for folder in [stale, piper] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.path) }
        let a = parent.appendingPathComponent("a.bin"); try Data("abc".utf8).write(to: a)
        let package = ModelPackage(id: "audit-package", archiveRoot: "audit", files: [PackageFile(path: "a", byteCount: 3, sha256: abc)])
        _ = try await PackageStore(root: root).install(files: ["a": a], package: package)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: piper.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "A folder of a running assembly was removed")
    }
}

final class AuditHistoryImageFormatTests: XCTestCase {
    private func image(_ type: CFString) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    // Audit 22.10 (iOS C1, owner O18): camera photos are kept as JPEG (PNG photos were 10+ MB and slow to encode);
    // PNG entries, such as Mac screen captures and older history, keep working.
    func testHistoryKeepsJPEGAndPNGImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("audit-images-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = TranslationHistory(root: root)
        let jpeg = try image("public.jpeg" as CFString), png = try image("public.png" as CFString)
        let savedPhoto = try await history.saveImage(jpeg, original: "a", translation: "б", source: .english, target: .russian)
        let savedCapture = try await history.saveImage(png, original: "c", translation: "д", source: .english, target: .russian)
        let photo = try XCTUnwrap(savedPhoto), capture = try XCTUnwrap(savedCapture)
        let reopened = TranslationHistory(root: root)
        let photoData = try await reopened.imageData(photo), captureData = try await reopened.imageData(capture)
        XCTAssertEqual(photoData, jpeg); XCTAssertEqual(captureData, png)
        let exports = root.appendingPathComponent("exports")
        let photoCopy = try await reopened.copyImage(photo, into: exports), captureCopy = try await reopened.copyImage(capture, into: exports)
        XCTAssertEqual(photoCopy.pathExtension, "jpg"); XCTAssertEqual(captureCopy.pathExtension, "png")
        let entries = try await reopened.list()
        XCTAssertTrue(entries.allSatisfy(\.hasImage))
        try await reopened.remove(photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(photo.uuidString + ".jpg").path))
        let orphan = root.appendingPathComponent(UUID().uuidString + ".jpg"); try jpeg.write(to: orphan)
        _ = try await TranslationHistory(root: root).list()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path), "An unowned JPEG was kept")
        let cleared = TranslationHistory(root: root)
        _ = try await cleared.saveImage(jpeg, original: "e", translation: "ё", source: .english, target: .russian)
        try await cleared.removeAll()
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }
        XCTAssertEqual(left, [], "Clear history kept images")
    }
}
