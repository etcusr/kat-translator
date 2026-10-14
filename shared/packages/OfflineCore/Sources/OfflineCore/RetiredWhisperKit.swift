import Foundation

/// Exact retired package paths only; never touches classic Whisper, Ultra, voices or history.
public enum RetiredWhisperKit {
    public static let id = "asr-whisperkit-turbo"
    public static let partIDs = (0..<31).map { id + "-part-\($0)" }
    public static func removeFiles(root: URL, documents: URL) throws {
        let paths = ["Recognitionshared/packages/\(id)", "Recognitionshared/packages/\(id).verified.json"] + partIDs.flatMap {
            ["Models/\($0).bin", "Models/\($0).json", "Models/\($0).verified.json", "Downloads/\($0)"]
        }
        let urls = paths.map { root.appendingPathComponent($0) } + [documents.appendingPathComponent("DevelopmentModels/whisperkit-turbo")]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
