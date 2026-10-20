import Foundation
// Standalone parity bridge links the production TranslationChunks.swift unchanged.
enum PipelineError: Error { case tooLong }
@main struct PlannerProbe {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let pieces = try (object["blocks"] as! [String]).map { try TranslationChunks.plan($0, count: count) }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["pieces": pieces]))
        FileHandle.standardOutput.write(Data([10]))
    }
    static func count(_ text: String) -> Int {
        FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: ["count": text]))
        FileHandle.standardOutput.write(Data([10]))
        return Int(readLine()!)!
    }
}
