import Foundation
public struct PackageFile: Codable, Equatable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String
    public init(path: String, byteCount: Int64, sha256: String) { self.path = path; self.byteCount = byteCount; self.sha256 = sha256 }
}
public struct ModelPackage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let archiveRoot: String
    public let files: [PackageFile]
    public init(id: String, archiveRoot: String, files: [PackageFile]) { self.id = id; self.archiveRoot = archiveRoot; self.files = files }
    public var expandedBytes: Int64 { files.reduce(0) { $0 + $1.byteCount } }
}
public enum PackageError: LocalizedError {
    case invalidArchive, unsafePath, integrity, incomplete
    public var errorDescription: String? { L10n.text("Голосовой пакет повреждён или неполон. Скачайте его заново.") }
}
