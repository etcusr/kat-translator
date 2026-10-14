import Foundation

/// Exact paths owned by the retired ThaiTTS package. Other models and history are preserved.
public enum RetiredThaiVoice {
    public static let ids = ["thaitts-encoder", "thaitts-decoder", "thaitts-postnet", "thaitts-vocoder"]

    public static func removeFiles(root: URL) throws {
        let manager = FileManager.default
        for id in ids {
            for path in ["Models/\(id).bin", "Models/\(id).json", "Downloads/\(id)"] {
                let url = root.appendingPathComponent(path)
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            }
        }
    }
}
