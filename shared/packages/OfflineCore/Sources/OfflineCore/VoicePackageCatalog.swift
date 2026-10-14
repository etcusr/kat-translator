import Foundation

public struct VoicePackagePart: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let remoteURL: URL
    public let byteCount: Int64
    public let sha256: String
    public init(id: String, path: String, remoteURL: URL, byteCount: Int64, sha256: String) {
        self.id = id; self.path = path; self.remoteURL = remoteURL; self.byteCount = byteCount; self.sha256 = sha256
    }
}
public struct VoicePackageDefinition: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case archive, files, piper }
    public let id: String
    public let language: String
    public let title: String
    public let license: String
    public let sourceURL: URL
    public let kind: Kind
    public let languageAliases: [String: String]?
    public func supports(_ language: String) -> Bool { self.language == language || languageAliases?[language] != nil }
    public func runtimeLanguage(_ language: String) -> String { languageAliases?[language] ?? language }
    public let piperPreparation: PiperPreparation?
    public let parts: [VoicePackagePart]
    public init(id: String, language: String, title: String, license: String, sourceURL: URL, kind: Kind, parts: [VoicePackagePart], piperPreparation: PiperPreparation? = nil, languageAliases: [String: String]? = nil) {
        self.id = id; self.language = language; self.title = title; self.license = license
        self.sourceURL = sourceURL; self.kind = kind; self.parts = parts; self.piperPreparation = piperPreparation; self.languageAliases = languageAliases
    }
    public var models: [ModelDescriptor] {
        parts.map { ModelDescriptor(id: $0.id, title: title, remoteURL: $0.remoteURL, byteCount: $0.byteCount, sha256: $0.sha256) }
    }
}
/// Download ownership is explicit: completing/removing a token file belongs to the same voice as its weights.
public struct VoicePackageCatalog: Sendable {
    public let packages: [VoicePackageDefinition]
    private let owners: [String: VoicePackageDefinition]
    public init(_ packages: [VoicePackageDefinition]) throws {
        var owners: [String: VoicePackageDefinition] = [:]
        for package in packages {
            guard !package.language.isEmpty, package.parts.first?.id == package.id,
                  package.kind != .archive || package.parts.count == 1,
                  package.kind != .piper || (package.parts.count == 1 && package.piperPreparation != nil),
                  Set(package.parts.map(\.path)).count == package.parts.count else { throw PackageError.incomplete }
            for part in package.parts {
                guard !part.id.isEmpty, part.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
                      PackageArchive.safePath(part.path), part.path != "receipt.json", part.byteCount > 0,
                      part.sha256.count == 64, part.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                      part.remoteURL.scheme == "https", owners[part.id] == nil else { throw PackageError.unsafePath }
                owners[part.id] = package
            }
        }
        self.packages = packages; self.owners = owners
    }
    public func package(containing componentID: String) -> VoicePackageDefinition? { owners[componentID] }
    public func voices(language: String) -> [VoicePackageDefinition] { packages.filter { $0.supports(language) } }
}

public struct PiperPreparation: Codable, Equatable, Sendable {
    public let metadataSuffix: Data
    public let tokens: String
    public init(metadataSuffix: Data, tokens: String) { self.metadataSuffix = metadataSuffix; self.tokens = tokens }
}
