import Foundation

/// Language scope is independent of shared model files. Both directions use the same set.
public struct LanguageSetup: Codable, Equatable, Sendable {
    public static let omnilingualID = "omnilingual-300m-int8"
    public var primaryID: String
    public var targetIDs: [String]
    public var recognition: Bool
    public var speech: Bool
    public init(primaryID: String = "ru", targetIDs: [String] = ["en"], recognition: Bool = true, speech: Bool = true) {
        self.primaryID = primaryID; self.targetIDs = targetIDs; self.recognition = recognition; self.speech = speech
    }
    public var languages: [SpeechLanguage] {
        var seen = Set<String>()
        return ([primaryID] + targetIDs).filter { seen.insert($0).inserted }.compactMap(SpeechLanguage.init(rawValue:))
    }
    public var isValid: Bool { SpeechLanguage(rawValue: primaryID) != nil && languages.count >= 2 && languages.allSatisfy { language in TranslationModel.selectable.contains { TranslationLanguage.details(language).connected(to: $0) } } }
    public var recommendedTranslation: TranslationModel { recommendedTranslation(strongDevice: false) }
    /// The first-run device check decides: a powerful device always gets Index 9B (best quality,
    /// one model for every language); otherwise OPUS where its pairs suffice, Index 9B for the rest.
    public func recommendedTranslation(strongDevice: Bool) -> TranslationModel {
        if !strongDevice && isValid && Set(languages.map(\.rawValue)) == ["ru", "en"] { return .opusBig }
        return .index9B
    }
    public var recognitionIDs: Set<String> {
        guard recognition else { return [] }
        return Set(languages.compactMap {
            if $0.whisperCode != nil { return ModelDescriptor.turbo.id }
            if RecognitionCatalog.omnilingualCodes[$0.rawValue] != nil { return Self.omnilingualID }
            return nil
        })
    }
    public var voiceLanguages: [SpeechLanguage] { speech ? languages.filter(\.hasVoice) : [] }
    public var missingRecognition: [SpeechLanguage] { recognition ? languages.filter { !$0.supportsRecognition } : [] }
    public var missingSpeech: [SpeechLanguage] { speech ? languages.filter { !$0.hasVoice } : [] }
}
public struct DownloadRequirement: Sendable {
    public let id: String
    public let bytes: Int64
    public let installed: Bool
    public init(id: String, bytes: Int64, installed: Bool) { self.id = id; self.bytes = bytes; self.installed = installed }
    public static func missingBytes(_ files: [Self]) -> Int64 {
        var seen = Set<String>()
        let installed = Set(files.filter(\.installed).map(\.id))
        return files.filter { !installed.contains($0.id) && seen.insert($0.id).inserted }.reduce(0) { $0 + $1.bytes }
    }
}
