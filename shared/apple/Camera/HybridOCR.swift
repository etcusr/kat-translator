import Foundation
import Vision
import CoreGraphics
import ImageIO
import OfflineCore

enum CameraError: LocalizedError {
    case image, noText, modelNeeded, recognition, cameraDenied, cameraUnavailable
    var errorDescription: String? {
        switch self {
        case .image: return L10n.text("Не удалось прочитать изображение. Выберите другое фото.")
        case .noText: return L10n.text("Текст не найден. Поднесите камеру ближе или выберите более чёткий снимок.")
        case .modelNeeded: return L10n.text("Для этого режима нужен открытый OCR-пакет. Скачайте его в настройках распознавания.")
        case .recognition: return L10n.text("Не удалось распознать текст. Попробуйте другой кадр.")
        case .cameraDenied: return L10n.text("Разрешите камеру в настройках iPhone. Можно также выбрать изображение из галереи.")
        case .cameraUnavailable: return L10n.text("Камера недоступна. Можно выбрать изображение из галереи.")
        }
    }
}
private final class OCRCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}
struct OCRObservation: Sendable { let blocks: [ImageTextBlock]; let engine: String }
final class HybridOCR: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.ocr", qos: .userInitiated)
    private var native: UnsafeMutableRawPointer?
    private var modelPath: String?
    private static let recognitionLanguages: [String] = {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }()
    static func supports(_ language: SpeechLanguage) -> Bool {
        recognitionLanguages.contains { $0 == language.rawValue || $0.hasPrefix(language.rawValue + "-") }
    }
    func recognize(_ image: CGImage, source: SpeechLanguage?, forceOpen: Bool, modelURL: URL?) async throws -> OCRObservation {
        try Task.checkCancellation()
        let cancellation = OCRCancellation()
        return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { c in queue.async {
            do {
                try cancellation.check()
                var blocks: [ImageTextBlock] = []
                let useVision = !forceOpen && (source.map(Self.supports) ?? true)
                if useVision {
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                    request.automaticallyDetectsLanguage = source == nil
                    if let source {
                        guard let supported = try request.supportedRecognitionLanguages().first(where: { $0.hasPrefix(source.rawValue) }) else { throw CameraError.recognition }
                        request.recognitionLanguages = [supported]
                    }
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    blocks = (request.results ?? []).compactMap { result in
                        guard let text = result.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                        return ImageTextBlock(text: text, box: Self.box(result.boundingBox))
                    }
                } else {
                    guard source == .russian || source == .english, let modelURL else { throw CameraError.modelNeeded }
                    if self.modelPath != modelURL.path {
                        if let old = self.native { ot_ocr_free(old) }; self.native = nil; self.modelPath = nil
                        guard let native = ot_ocr_load(modelURL.path) else { throw CameraError.recognition }
                        self.native = native; self.modelPath = modelURL.path
                    }
                    guard let native = self.native, let dictURL = Bundle.main.url(forResource: source == .russian ? "ocr-eslav-characters" : "ocr-english-characters", withExtension: "json") else { throw CameraError.recognition }
                    let dictionary = try JSONDecoder().decode([String].self, from: Data(contentsOf: dictURL))
                    let request = VNDetectTextRectanglesRequest(); request.reportCharacterBoxes = false
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    for observation in request.results ?? [] {
                        try cancellation.check()
                        let b = Self.box(observation.boundingBox)
                        let pixels = CGRect(x: b.x * Double(image.width), y: b.y * Double(image.height), width: b.width * Double(image.width), height: b.height * Double(image.height))
                        let padded = pixels.insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
                        guard let crop = image.cropping(to: padded) else { continue }
                        let height = Int(ot_ocr_height(native))
                        let width = min(4096, max(320, Int(ceil(Double(height) * Double(crop.width) / Double(crop.height)))))
                        let scaledWidth = min(width, max(1, Int(ceil(Double(height) * Double(crop.width) / Double(crop.height)))))
                        var rgba = [UInt8](repeating: 0, count: scaledWidth * height * 4)
                        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
                            guard let context = CGContext(data: buffer.baseAddress, width: scaledWidth, height: height, bitsPerComponent: 8, bytesPerRow: scaledWidth*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                            context.interpolationQuality = .high; context.draw(crop, in: CGRect(x: 0, y: 0, width: scaledWidth, height: height)); return true
                        }
                        guard drawn else { throw CameraError.recognition }
                        var input = [Float](repeating: 0, count: 3 * height * width)
                        for y in 0..<height { for x in 0..<scaledWidth { for ch in 0..<3 {
                            input[ch*height*width + y*width+x] = Float(rgba[(y*scaledWidth+x)*4+(2-ch)])/127.5-1
                        } } }
                        var ids = [Int32](repeating: 0, count: 4096)
                        let count = ot_ocr_run(native, input, Int32(width), &ids, Int32(ids.count))
                        guard count > 0 else { throw CameraError.recognition }
                        var previous: Int32 = -1; var text = ""
                        for value in ids.prefix(Int(count)) {
                            guard value >= 0, Int(value) < dictionary.count else { throw CameraError.recognition }
                            if value != 0 && value != previous { text += dictionary[Int(value)] }; previous = value
                        }
                        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { blocks.append(ImageTextBlock(text: text, box: b)) }
                    }
                }
                try cancellation.check()
                c.resume(returning: OCRObservation(blocks: Self.group(blocks), engine: useVision ? "Apple Vision" : "PP-OCRv5"))
            } catch { c.resume(throwing: error) }
        } }
        } onCancel: { cancellation.cancel() }
    }
    private static func box(_ rect: CGRect) -> ImageTextBox { ImageTextBox(x: rect.minX, y: 1-rect.maxY, width: rect.width, height: rect.height) }
    private static func group(_ input: [ImageTextBlock]) -> [ImageTextBlock] {
        var output: [ImageTextBlock] = []
        for block in input.sorted(by: { $0.box.y < $1.box.y }) {
            if let last = output.last {
                let a = last.box, b = block.box, gap = b.y-a.y-a.height
                if abs(a.x-b.x) < 0.025, gap >= -0.002, gap < b.height*0.65, b.y+b.height-a.y < 0.23, last.text.count + block.text.count < 400 {
                    output.removeLast()
                    output.append(ImageTextBlock(text: last.text + "\n" + block.text, box: ImageTextBox(x: min(a.x,b.x), y: a.y, width: max(a.x+a.width,b.x+b.width)-min(a.x,b.x), height: b.y+b.height-a.y)))
                    continue
                }
            }
            output.append(block)
        }
        return output
    }
    func unload() async { await withCheckedContinuation { c in queue.async { if let p = self.native { ot_ocr_free(p) }; self.native = nil; self.modelPath = nil; c.resume() } } }
    deinit { if let native { ot_ocr_free(native) } }
}
