import Foundation
import CryptoKit
import ArchiveRuntime

public enum PackageArchive {
    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
        && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    public static func extract(_ archive: URL, to destination: URL, package: ModelPackage) throws {
        guard safePath(package.archiveRoot), package.files.allSatisfy({ safePath($0.path) && $0.byteCount >= 0 }),
              Set(package.files.map(\.path)).count == package.files.count,
              !FileManager.default.fileExists(atPath: destination.path) else { throw PackageError.unsafePath }
        guard let reader = ot_bz_open(archive.path) else { throw PackageError.invalidArchive }
        defer { ot_bz_close(reader) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        func read(_ size: Int) throws -> Data {
            var data = Data(count: size); var offset = 0
            while offset < size {
                try Task.checkCancellation()
                let n = data.withUnsafeMutableBytes { bytes in ot_bz_read(reader, bytes.baseAddress!.advanced(by: offset), Int32(size - offset)) }
                guard n > 0 else { throw PackageError.invalidArchive }; offset += Int(n)
            }
            return data
        }
        func field(_ data: Data, _ range: Range<Int>) throws -> String {
            guard let string = String(data: data.subdata(in: range).prefix { $0 != 0 }, encoding: .utf8) else { throw PackageError.invalidArchive }
            return string
        }
        var seen = Set<String>(); var entryCount = 0
        let expected = Dictionary(uniqueKeysWithValues: package.files.map { ($0.path, $0) })
        while true {
            let header = try read(512)
            if header.allSatisfy({ $0 == 0 }) {
                guard try read(512).allSatisfy({ $0 == 0 }), seen == Set(expected.keys) else { throw PackageError.incomplete }
                // Drain the compressed stream too: require a valid bzip2 trailer and bounded tar padding.
                var padding = [UInt8](repeating: 0, count: 4096); var paddingBytes = 0
                while true {
                    try Task.checkCancellation()
                    let n = ot_bz_read(reader, &padding, Int32(padding.count))
                    guard n >= 0 else { throw PackageError.invalidArchive }
                    if n == 0 { break }
                    paddingBytes += Int(n)
                    guard paddingBytes <= 10_240, padding.prefix(Int(n)).allSatisfy({ $0 == 0 }) else { throw PackageError.invalidArchive }
                }
                complete = true; return
            }
            entryCount += 1; guard entryCount <= 2048 else { throw PackageError.invalidArchive }
            let recordedSum = Int(try field(header, 148..<156).trimmingCharacters(in: .whitespaces), radix: 8)
            let sum = header.enumerated().reduce(0) { $0 + ((148..<156).contains($1.offset) ? 32 : Int($1.element)) }
            guard recordedSum == sum else { throw PackageError.invalidArchive }
            let name = try field(header, 0..<100)
            let prefix = try field(header, 345..<500)
            var full = prefix.isEmpty ? name : prefix + "/" + name
            if full.hasSuffix("/") { full.removeLast() }
            guard safePath(full), full == package.archiveRoot || full.hasPrefix(package.archiveRoot + "/") else { throw PackageError.unsafePath }
            let relative = full == package.archiveRoot ? "" : String(full.dropFirst(package.archiveRoot.count + 1))
            guard let size = Int64(try field(header, 124..<136).trimmingCharacters(in: .whitespaces), radix: 8), size >= 0 else { throw PackageError.invalidArchive }
            let type = header[156]
            if type == 53 { // Directories need no writes; file parents are created below.
                guard size == 0 else { throw PackageError.invalidArchive }; continue
            }
            guard type == 48 || type == 0 else { throw PackageError.unsafePath } // no symlinks, hardlinks or extended headers
            guard let file = expected[relative], file.byteCount == size, seen.insert(relative).inserted else { throw PackageError.integrity }
            let output = destination.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw PackageError.incomplete }
            let handle = try FileHandle(forWritingTo: output)
            var hasher = SHA256(); var remaining = size
            do {
                while remaining > 0 {
                    let data = try read(Int(min(remaining, 1_048_576)))
                    try handle.write(contentsOf: data); hasher.update(data: data); remaining -= Int64(data.count)
                }
                try handle.close()
            } catch { try? handle.close(); throw error }
            guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw PackageError.integrity }
            if size % 512 != 0 { _ = try read(Int(512 - size % 512)) }
        }
    }
}
