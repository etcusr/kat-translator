import Foundation
import ImageIO
import OfflineCore
@main struct Probe {
    static func main() async throws {
        let ocr = HybridOCR()
        for (lang,stem,expected) in [(SpeechLanguage.english,"english","Please do not add sugar"),(.russian,"eslav","Пожалуйста, не добавляйте сахар")] {
            let url = URL(fileURLWithPath:".build/ocr-probe/"+stem+".png")
            let source = CGImageSourceCreateWithURL(url as CFURL,nil)!
            let image = CGImageSourceCreateImageAtIndex(source,0,nil)!
            for force in [false,true] {
                let result = try await ocr.recognize(image,source:lang,forceOpen:force,modelURL:URL(fileURLWithPath:"model-store/downloads/ocr-"+stem+".onnx"))
                let text = result.blocks.map(\.text).joined(separator:" ")
                print(stem,result.engine,text)
                guard text == expected else { throw NSError(domain:"OCRProbe mismatch",code:1) }
            }
        }
        for (lang, stem, expected) in [(SpeechLanguage.french, "french", "Le train part à 17h45."), (.german, "german", "Bitte keinen Zucker hinzufügen.")] {
            guard HybridOCR.supports(lang) else { print(stem, "Vision unavailable on this OS"); continue }
            let url = URL(fileURLWithPath: ".build/ocr-probe/" + stem + ".png")
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let result = try await ocr.recognize(image, source: lang, forceOpen: false, modelURL: nil)
            let text = result.blocks.map(\.text).joined(separator: " ")
            print(stem, result.engine, text)
            guard text == expected else { throw NSError(domain: "Multilingual OCR mismatch", code: 1) }
        }
        await ocr.unload(); print("Hybrid OCR full image paths passed")
    }
}
