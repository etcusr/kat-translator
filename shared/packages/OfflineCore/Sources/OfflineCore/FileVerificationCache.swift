import Foundation
import CryptoKit
import Darwin

/// A local receipt of a completed SHA-256 verification, not a replacement for one.
/// lstat avoids URL resource caching; ctime also detects rewrites that restore mtime.
struct VerifiedFileStamp: Codable, Equatable {
    let device: Int32
    let inode: UInt64
    let bytes: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64

    init(_ url: URL) throws {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &info)
        }
        guard result == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileReadCorruptFile)
        }
        device = info.st_dev; inode = info.st_ino; bytes = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec); changedNanos = Int64(info.st_ctimespec.tv_nsec)
    }
}

struct FileVerificationCache: Codable {
    let version: Int
    let identity: String
    let files: [String: VerifiedFileStamp]

    static func identity<T: Encodable>(_ manifest: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(manifest)).map { String(format: "%02x", $0) }.joined()
    }
    static func matches(_ url: URL, identity: String, files: [String: VerifiedFileStamp]) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Self.self, from: data) else { return false }
        return saved.version == 1 && saved.identity == identity && saved.files == files
    }
    static func save(_ url: URL, identity: String, files: [String: VerifiedFileStamp]) throws {
        try JSONEncoder().encode(Self(version: 1, identity: identity, files: files)).write(to: url, options: .atomic)
    }
}
