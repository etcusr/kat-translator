import XCTest
@testable import OfflineCore

final class RetiredThaiVoiceTests: XCTestCase {
    func testRemovalIsScopedAndSafeToRepeat() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let retired = RetiredThaiVoice.ids.flatMap { ["Models/\($0).bin", "Models/\($0).json", "Downloads/\($0)/resume.data"] }
        let retained = ["Models/wayu-prosody.bin", "Models/index-translate-9b-q4km.bin", "History/entries.json", "Downloads/wayu-prosody/resume.data"]
        for path in retired + retained {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        try RetiredThaiVoice.removeFiles(root: root)
        try RetiredThaiVoice.removeFiles(root: root)
        for path in retired { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
        for path in retained { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(path.utf8)) }
    }
}
