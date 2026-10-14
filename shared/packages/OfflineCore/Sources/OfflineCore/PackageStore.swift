import Foundation
import CryptoKit
public actor PackageStore {
    private let root: URL
    private(set) var validationBytesRead: Int64 = 0
    private let onUncachedVerification: @Sendable (Bool) -> Void
    public init(root: URL, onUncachedVerification: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.root = root; self.onUncachedVerification = onUncachedVerification
    }
    private func directory(_ package: ModelPackage) throws -> URL {
        guard !package.id.isEmpty, package.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw PackageError.unsafePath }
        return root.appendingPathComponent(package.id, isDirectory: true)
    }
    public func readyDirectory(for package: ModelPackage) throws -> URL? {
        let directory = try directory(package); let receipt = directory.appendingPathComponent("receipt.json")
        guard let data = try? Data(contentsOf: receipt), let saved = try? JSONDecoder().decode(ModelPackage.self, from: data), saved == package else { return nil }
        let stamps: [String: VerifiedFileStamp]
        do { stamps = try snapshot(package, directory: directory) }
        catch is CancellationError { throw CancellationError() }
        catch { return nil }
        let identity = try FileVerificationCache.identity(package)
        if FileVerificationCache.matches(cacheURL(package), identity: identity, files: stamps) { return directory }
        onUncachedVerification(true)
        defer { onUncachedVerification(false) }
        for file in package.files {
            try Task.checkCancellation()
            guard PackageArchive.safePath(file.path) else { throw PackageError.unsafePath }
            let url = directory.appendingPathComponent(file.path)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink == false,
                  values?.fileSize.map(Int64.init) == file.byteCount, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var hash = SHA256()
            while try autoreleasepool(invoking: {
                try Task.checkCancellation()
                let data = try handle.read(upToCount: 1_048_576) ?? Data()
                guard !data.isEmpty else { return false }
                hash.update(data: data); validationBytesRead += Int64(data.count); return true
            }) {}
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { return nil }
        }
        guard try snapshot(package, directory: directory) == stamps else { return nil }
        try? FileVerificationCache.save(cacheURL(package), identity: identity, files: stamps)
        return directory
    }
    private func cacheURL(_ package: ModelPackage) -> URL {
        root.appendingPathComponent(package.id + ".verified.json")
    }
    private func snapshot(_ package: ModelPackage, directory: URL) throws -> [String: VerifiedFileStamp] {
        var result: [String: VerifiedFileStamp] = [:]
        for file in package.files {
            try Task.checkCancellation()
            guard PackageArchive.safePath(file.path) else { throw PackageError.unsafePath }
            let stamp = try VerifiedFileStamp(directory.appendingPathComponent(file.path))
            guard stamp.bytes == file.byteCount else { throw PackageError.integrity }
            result[file.path] = stamp
        }
        return result
    }
    private func cacheInstalled(_ package: ModelPackage, directory: URL) {
        // Called only after extraction/assembly has verified every file hash.
        try? FileVerificationCache.save(cacheURL(package), identity: FileVerificationCache.identity(package),
                                        files: snapshot(package, directory: directory))
    }
    public func install(archive: URL, package: ModelPackage) throws -> URL {
        let final = try directory(package)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        let staging = root.appendingPathComponent("staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try PackageArchive.extract(archive, to: staging, package: package)
        try Task.checkCancellation()
        try JSONEncoder().encode(package).write(to: staging.appendingPathComponent("receipt.json"), options: .atomic)
        if FileManager.default.fileExists(atPath: final.path) { _ = try FileManager.default.replaceItemAt(final, withItemAt: staging) }
        else { try FileManager.default.moveItem(at: staging, to: final) }
        cacheInstalled(package, directory: final)
        return final
    }
    /// Assemble a package distributed as separate downloads, verifying each file before publishing it.
    public func install(files: [String: URL], package: ModelPackage) throws -> URL {
        let final = try directory(package)
        guard !package.files.isEmpty, Set(package.files.map(\.path)).count == package.files.count,
              Set(files.keys) == Set(package.files.map(\.path)),
              package.files.allSatisfy({ PackageArchive.safePath($0.path) && $0.path != "receipt.json" && $0.byteCount >= 0 }) else { throw PackageError.unsafePath }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        let staging = root.appendingPathComponent("staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in package.files {
            try Task.checkCancellation()
            let source = files[file.path]!
            let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink == false, info.fileSize.map(Int64.init) == file.byteCount else { throw PackageError.integrity }
            let target = staging.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            let handle = try FileHandle(forReadingFrom: target)
            defer { try? handle.close() }
            var hash = SHA256()
            while try autoreleasepool(invoking: {
                try Task.checkCancellation()
                let data = try handle.read(upToCount: 1_048_576) ?? Data()
                guard !data.isEmpty else { return false }
                hash.update(data: data); validationBytesRead += Int64(data.count); return true
            }) {}
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw PackageError.integrity }
        }
        try Task.checkCancellation()
        try JSONEncoder().encode(package).write(to: staging.appendingPathComponent("receipt.json"), options: .atomic)
        if FileManager.default.fileExists(atPath: final.path) { _ = try FileManager.default.replaceItemAt(final, withItemAt: staging) }
        else { try FileManager.default.moveItem(at: staging, to: final) }
        cacheInstalled(package, directory: final)
        return final
    }
    /// Pinned Piper exports lack runtime metadata. Append the bundled protobuf fields;
    /// the usual package hashes verify the complete derived files before publication.
    public func installPiper(model: URL, preparation: PiperPreparation, package: ModelPackage) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temporary = root.appendingPathComponent("piper-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        let target = temporary.appendingPathComponent("model.onnx")
        try FileManager.default.copyItem(at: model, to: target)
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: preparation.metadataSuffix); try handle.close()
        try Task.checkCancellation()
        let tokens = temporary.appendingPathComponent("tokens.txt")
        try Data(preparation.tokens.utf8).write(to: tokens)
        return try install(files: ["model.onnx": target, "tokens.txt": tokens], package: package)
    }
    public func remove(_ package: ModelPackage) throws {
        let url = try directory(package)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try? FileManager.default.removeItem(at: cacheURL(package))
    }
}
