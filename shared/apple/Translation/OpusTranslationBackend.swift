import Foundation
import OfflineCore

private final class OpusCancellation: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    init() throws { guard let value = ot_opus_flag_create() else { throw PipelineError.modelLoad }; pointer = value }
    func cancel() { ot_opus_flag_cancel(pointer) }
    deinit { ot_opus_flag_free(pointer) }
}

final class OpusTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.translation.opus", qos: .userInitiated)
    private var context: UnsafeMutableRawPointer?
    private let lock = NSLock()
    private var flag: OpusCancellation?
    /// Direction packages: the TranslationPackages root; one package context is loaded at a time.
    private var directionsRoot: URL?
    private var loadedPackage: String?
    private func setFlag(_ value: OpusCancellation?) { lock.lock(); defer { lock.unlock() }; flag = value }
    func cancel() { lock.lock(); defer { lock.unlock() }; flag?.cancel() }
    func load(modelURL: URL, model: TranslationModel) async throws {
        guard model == .opusDirections else { return try await load(modelURL: modelURL) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in queue.async {
            if let previous = self.context { ot_opus_free(previous); self.context = nil }
            self.directionsRoot = modelURL; self.loadedPackage = nil
            continuation.resume()
        } }
    }
    func load(modelURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in queue.async {
            if let previous = self.context { ot_opus_free(previous); self.context = nil }
            self.directionsRoot = nil; self.loadedPackage = nil
            self.context = ot_opus_load(modelURL.path)
            if self.context != nil { continuation.resume() } else { continuation.resume(throwing: PipelineError.modelLoad) }
        } }
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: { _ in })
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage,
                   progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        try Task.checkCancellation()
        let route = directionsRoot == nil ? nil : OpusDirectionRoutes.route(source.rawValue, target.rawValue, available: { route in
            guard let root = self.directionsRoot else { return false }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent(route.packageID).appendingPathComponent("receipt.json").path)
        })
        guard directionsRoot == nil ? TranslationModel.opusBig.supports(source: source, target: target) : (route != nil || source == target) else { throw PipelineError.modelLanguageUnavailable }
        try TranslationPrompt.validate(text)
        if source == target { return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) }
        let cancellation = try OpusCancellation(); setFlag(cancellation); defer { setFlag(nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in self.queue.async {
                do {
                    if let route, let root = self.directionsRoot, self.loadedPackage != route.packageID {
                        if let previous = self.context { ot_opus_free(previous); self.context = nil }
                        self.context = ot_opus_load(root.appendingPathComponent(route.packageID).path)
                        self.loadedPackage = self.context == nil ? nil : route.packageID
                    }
                    guard let context = self.context else { throw PipelineError.modelLoad }
                    func count(_ part: String) -> Int32 {
                        if let route { return ot_opus_count_direction(context, part, route.direction, route.marker(target.rawValue)) }
                        return ot_opus_count(context, part, source.rawValue, target.rawValue)
                    }
                    let started = ProcessInfo.processInfo.systemUptime
                    let pieces = try OpusTextSegments.split(text) { part in
                        let count = count(part)
                        return count > 0 && count <= 480
                    }
                    var work = TranslationWork(pieces: pieces)
                    var translated = "", fragments = 0
                    progress(work.progress)
                    while let part = work.current {
                        let input = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if input.isEmpty { work.completeCurrent(); progress(work.progress); continue }
                        var output = [CChar](repeating: 0, count: 65_536)
                        let code = route.map { ot_opus_run_direction(context, input, $0.direction, $0.marker(target.rawValue), cancellation.pointer, &output, output.count) }
                            ?? ot_opus_run(context, input, source.rawValue, target.rawValue, cancellation.pointer, &output, output.count)
                        if code == 2 { throw CancellationError() }
                        if code == 1 { try work.splitCurrent(); progress(work.progress); continue }
                        guard code == 0 else { throw PipelineError.inference }
                        let result = String(cString: output).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !result.isEmpty else { throw PipelineError.inference }
                        let leading = part.prefix(while: \.isWhitespace)
                        if !translated.isEmpty { translated += leading.contains("\n") ? "\n\n" : " " }
                        translated += result; fragments += 1
                        work.completeCurrent(); progress(work.progress)
                    }
                    guard !translated.isEmpty else { throw PipelineError.noSpeech }
                    continuation.resume(returning: TranslationResult(text: translated, firstTokenSeconds: nil,
                        processingSeconds: ProcessInfo.processInfo.systemUptime - started, fragments: fragments))
                } catch { continuation.resume(throwing: error) }
            } }
        } onCancel: { cancellation.cancel() }
    }
    func unload() async {
        cancel()
        await withCheckedContinuation { continuation in queue.async {
            if let context = self.context { ot_opus_free(context); self.context = nil }
            self.loadedPackage = nil
            continuation.resume()
        } }
    }
    deinit { if let context { ot_opus_free(context) } }
}
