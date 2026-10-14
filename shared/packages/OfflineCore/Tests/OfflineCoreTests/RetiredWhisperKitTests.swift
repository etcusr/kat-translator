import XCTest
@testable import OfflineCore

final class RetiredWhisperKitTests: XCTestCase {
    func testCleanupIsScopedAndIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        let removed = ["Recognitionshared/packages/asr-whisperkit-turbo/TextDecoder.mlmodelc/weights/weight.bin",
                       "Recognitionshared/packages/asr-whisperkit-turbo.verified.json",
                       "Documents/DevelopmentModels/whisperkit-turbo/weights.bin"] + RetiredWhisperKit.partIDs.flatMap {
            ["Models/\($0).bin", "Models/\($0).json", "Models/\($0).verified.json", "Downloads/\($0)/resume.data"]
        }
        let retained = ["Models/whisper-large-v3-turbo-f16.bin", "Models/index-translate-9b-q4km.bin",
                        "Recognitionshared/packages/asr-parakeet-ultra/weights.bin", "Voiceshared/packages/ru/voice.onnx",
                        "History/history.json", "Documents/DevelopmentModels/parakeet-ultra-coreml/weights.bin"]
        for path in removed + retained {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        try RetiredWhisperKit.removeFiles(root: root, documents: documents)
        try RetiredWhisperKit.removeFiles(root: root, documents: documents)
        for path in removed { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
        for path in retained { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(path.utf8)) }
    }
}
