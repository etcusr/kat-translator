import Foundation
import OfflineCore

extension ModelCatalog {
    static let wayuVoice = ModelDescriptor(id: "wayu-prosody", title: L10n.text("Тайский · Wayu Kokoro"),
        remoteURL: URL(string: "https://huggingface.co/kunato/wayu-kokoro-thai-v1/resolve/50d7f60e41ac118e5bb92b0ba52c30bb7830103c/onnx/prosody_fp32.onnx")!,
        byteCount: 78259639, sha256: "cab0963ab960a43e12cb2b2a232fd712bd5c0b369e86ad0c18090b81aa4eee35")
    static let wayuCurves = ModelDescriptor(id: "wayu-curves", title: L10n.text("Тайский · Wayu Kokoro"),
        remoteURL: URL(string: "https://huggingface.co/kunato/wayu-kokoro-thai-v1/resolve/50d7f60e41ac118e5bb92b0ba52c30bb7830103c/onnx/curves_fp32.onnx")!,
        byteCount: 33721740, sha256: "bc7c0a7c4e1a44c301143f9d1d34686b9a73dff7e577284a8781b0e428b17d1d")
    static let wayuDecoder = ModelDescriptor(id: "wayu-decoder", title: L10n.text("Тайский · Wayu Kokoro"),
        remoteURL: URL(string: "https://huggingface.co/kunato/wayu-kokoro-thai-v1/resolve/50d7f60e41ac118e5bb92b0ba52c30bb7830103c/onnx/decoder_fp32.onnx")!,
        byteCount: 213445776, sha256: "e512c7e8cd05aefe1702b5f10581247a41b1c774a92c6a0d4538cad3a52d162b")
    static let wayuStyles = ModelDescriptor(id: "wayu-styles", title: L10n.text("Тайский · Wayu Kokoro"),
        remoteURL: URL(string: "https://huggingface.co/kunato/wayu-kokoro-thai-v1/resolve/50d7f60e41ac118e5bb92b0ba52c30bb7830103c/onnx/voicepacks.npz")!,
        byteCount: 6294562, sha256: "4a75ac3a5f25d2cffdd5272192e898ea2f23da6b3895650f19d95abd8fe32c5f")
}
