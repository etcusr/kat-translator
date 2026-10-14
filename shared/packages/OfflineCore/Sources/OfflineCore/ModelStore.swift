import Foundation
import CryptoKit

public struct ModelDescriptor: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let remoteURL: URL
    public let byteCount: Int64
    public let sha256: String
    public init(id: String, title: String, remoteURL: URL, byteCount: Int64, sha256: String) {
        self.id = id; self.title = title; self.remoteURL = remoteURL
        self.byteCount = byteCount; self.sha256 = sha256
    }
    public static let turbo = SharedModelAssets.turbo
    public static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
}
public enum ModelStoreError: LocalizedError {
    case invalidSize, invalidDigest, insufficientSpace, invalidIdentifier
    public var errorDescription: String? {
        switch self {
        case .invalidSize: return L10n.text("Файл скачан не полностью. Попробуйте скачать модель заново.")
        case .invalidDigest: return L10n.text("Проверка целостности не пройдена. Скачайте модель заново.")
        case .insufficientSpace: return L10n.text("Недостаточно свободного места для модели.")
        case .invalidIdentifier: return L10n.text("Некорректный идентификатор модели.")
        }
    }
}
public actor ModelStore {
    private let root: URL
    private(set) var validationBytesRead: Int64 = 0
    private let onUncachedVerification: @Sendable (Bool) -> Void
    public init(root: URL, onUncachedVerification: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.root = root; self.onUncachedVerification = onUncachedVerification
    }
    private func paths(_ model: ModelDescriptor) throws -> (URL, URL) {
        guard !model.id.isEmpty, model.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw ModelStoreError.invalidIdentifier
        }
        return (root.appendingPathComponent(model.id + ".bin"), root.appendingPathComponent(model.id + ".json"))
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    private func validate(_ url: URL, model: ModelDescriptor) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size.map(Int64.init) == model.byteCount else { throw ModelStoreError.invalidSize }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hasher = SHA256()
        // FileHandle may autorelease its Data buffers. Drain each block rather than
        // retaining gigabytes until the async task's surrounding pool is drained.
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            validationBytesRead += Int64(chunk.count)
            return true
        }) {}
        guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == model.sha256 else {
            throw ModelStoreError.invalidDigest
        }
    }
    public func installedURL(for model: ModelDescriptor) throws -> URL? {
        try Task.checkCancellation()
        let (file, receipt) = try paths(model)
        guard let data = try? Data(contentsOf: receipt),
              let saved = try? JSONDecoder().decode(ModelDescriptor.self, from: data),
              // Display names and download mirrors may change; the verified asset stays the same.
              saved.id == model.id, saved.byteCount == model.byteCount, saved.sha256 == model.sha256,
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let stamp = try VerifiedFileStamp(file)
            guard stamp.bytes == model.byteCount else { throw ModelStoreError.invalidSize }
            let cache = root.appendingPathComponent(model.id + ".verified.json")
            let identity = try FileVerificationCache.identity([model.id, String(model.byteCount), model.sha256])
            if FileVerificationCache.matches(cache, identity: identity, files: [model.id: stamp]) { return file }
            // Missing or stale metadata both require the full checksum pass.
            onUncachedVerification(true)
            defer { onUncachedVerification(false) }
            try validate(file, model: model)
            guard try VerifiedFileStamp(file) == stamp else { throw ModelStoreError.invalidDigest }
            try? FileVerificationCache.save(cache, identity: identity, files: [model.id: stamp])
            return file
        }
        catch is CancellationError { throw CancellationError() }
        catch { try? FileManager.default.removeItem(at: receipt); return nil }
    }
    public func verifyAndInstall(stagingURL: URL, model: ModelDescriptor) throws -> URL {
        try prepare()
        let (file, receipt) = try paths(model)
        let before = try VerifiedFileStamp(stagingURL)
        try validate(stagingURL, model: model)
        guard try VerifiedFileStamp(stagingURL) == before else { throw ModelStoreError.invalidDigest }
        try Task.checkCancellation()
        // Only a complete, verified file reaches the final name. The receipt is written last.
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: stagingURL)
        } else { try FileManager.default.moveItem(at: stagingURL, to: file) }
        do {
            try JSONEncoder().encode(model).write(to: receipt, options: .atomic)
            let identity = try FileVerificationCache.identity([model.id, String(model.byteCount), model.sha256])
            try? FileVerificationCache.save(root.appendingPathComponent(model.id + ".verified.json"), identity: identity,
                                            files: [model.id: try VerifiedFileStamp(file)])
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }
    public func remove(_ model: ModelDescriptor) throws {
        let (file, receipt) = try paths(model)
        for url in [receipt, file, root.appendingPathComponent(model.id + ".verified.json")] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
