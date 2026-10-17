import Foundation
import OfflineCore
final class SpeechCancelFlag: @unchecked Sendable {
    let pointer: OpaquePointer
    init() throws { guard let p = wt_cancel_create() else { throw PipelineError.modelLoad }; pointer = p }
    func cancel() { wt_cancel_set(pointer) }
    var cancelled: Bool { wt_abort(UnsafeMutableRawPointer(pointer)) }
    deinit { wt_cancel_free(pointer) }
}
final class SherpaSpeechBackend: SpeechSynthesisBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.synthesis", qos: .userInitiated)
    private var omniVoice: OmniVoiceSynthesis?
    private var context: OpaquePointer?
    private var wayuContext: UnsafeMutableRawPointer?
    private var wayuDirectory: URL?
    private var wayuVoice = WayuVoice.defaultVoice
    private var diagnosticModel = ""
    private var mmsTokens: String?
    private var supertonic = false
    private var languageCode = "en"
    private let lock = NSLock()
    private var flag: SpeechCancelFlag?
    func load(directory: URL, language: SpeechLanguage) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in queue.async {
            self.diagnosticModel = directory.lastPathComponent + ":" + language.rawValue
            let loadStart = Date.timeIntervalSinceReferenceDate
            SpeechMemoryTrace.record("load.begin", model: self.diagnosticModel)
            defer { SpeechMemoryTrace.record("load.end", model: self.diagnosticModel, seconds: Date.timeIntervalSinceReferenceDate - loadStart, code: self.context != nil || self.wayuContext != nil || self.omniVoice != nil ? 0 : -1) }
            self.omniVoice = nil
            if let context = self.context { SherpaOnnxDestroyOfflineTts(context); self.context = nil }
            if let wayu = self.wayuContext { ot_wayu_free(wayu); self.wayuContext = nil }
            self.wayuDirectory = nil; self.mmsTokens = nil
            if language == .thai, let fragment = directory.fragment, fragment.hasPrefix("wayu:") {
                guard ot_wayu_frontend_init(Bundle.main.resourcePath ?? Bundle.main.bundlePath) != 0 else { c.resume(throwing: PipelineError.modelLoad); return }
                self.wayuVoice = WayuVoice(rawValue: String(fragment.dropFirst(5))) ?? WayuVoice.defaultVoice
                self.wayuDirectory = directory
                self.wayuContext = ot_wayu_load(directory.appendingPathComponent("wayu-prosody.bin").path,
                    directory.appendingPathComponent("wayu-curves.bin").path, directory.appendingPathComponent("wayu-decoder.bin").path)
                if self.wayuContext == nil { c.resume(throwing: PipelineError.modelLoad) } else { c.resume() }
                return
            }
            if directory.lastPathComponent == "omnivoice-q8-base" {
                do {
                    guard let definition = AdditionalVoiceCatalog.catalog.package(containing: "omnivoice-q8-base"), definition.supports(language.rawValue) else { throw PipelineError.voiceUnavailable }
                    self.omniVoice = try OmniVoiceSynthesis(directory: directory, language: definition.runtimeLanguage(language.rawValue))
                    c.resume()
                } catch { c.resume(throwing: error) }
                return
            }
            if language == .thai { c.resume(throwing: PipelineError.modelLoad); return }
            self.languageCode = language.rawValue
            self.supertonic = FileManager.default.fileExists(atPath: directory.appendingPathComponent("tts.json").path)
            if self.supertonic {
                self.context = ot_supertonic_create(directory.path)
                if self.context == nil { c.resume(throwing: PipelineError.modelLoad) } else { c.resume() }
                return
            }
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
                  files.filter({ $0.pathExtension == "onnx" }).count == 1,
                  let model = files.first(where: { $0.pathExtension == "onnx" })?.lastPathComponent else {
                c.resume(throwing: PipelineError.modelLoad); return
            }
            if directory.lastPathComponent.hasPrefix("mms-tts-") {
                guard let tokens = try? String(contentsOf: directory.appendingPathComponent("tokens.txt"), encoding: .utf8) else {
                    c.resume(throwing: PipelineError.modelLoad); return
                }
                self.mmsTokens = tokens
            }
            var data = directory.appendingPathComponent("espeak-ng-data").path
            if directory.lastPathComponent.hasPrefix("piper-"), !FileManager.default.fileExists(atPath: data) {
                guard let bundled = Bundle.main.url(forResource: "espeak-ng-data", withExtension: nil) else {
                    c.resume(throwing: PipelineError.modelLoad); return
                }
                data = bundled.path
            }
            self.context = ot_tts_create(directory.appendingPathComponent(model).path,
                directory.appendingPathComponent("tokens.txt").path, FileManager.default.fileExists(atPath: data) ? data : "")
            if self.context == nil { c.resume(throwing: PipelineError.modelLoad) } else { c.resume() }
        } }
    }
    private func setFlag(_ value: SpeechCancelFlag?) { lock.lock(); defer { lock.unlock() }; flag = value }
    func cancel() { lock.lock(); defer { lock.unlock() }; flag?.cancel() }
    func synthesize(text: String) async throws -> SpeechPCM {
        try Task.checkCancellation()
        let flag = try SpeechCancelFlag(); setFlag(flag); defer { setFlag(nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in self.queue.async {
                if let omni = self.omniVoice {
                    let start = Date.timeIntervalSinceReferenceDate
                    SpeechMemoryTrace.record("synthesis.begin", model: self.diagnosticModel)
                    do {
                        let pcm = try omni.synthesize(text, flag: flag)
                        SpeechMemoryTrace.record("synthesis.end", model: self.diagnosticModel, seconds: Date.timeIntervalSinceReferenceDate - start, code: Int32(pcm.samples.count))
                        continuation.resume(returning: pcm)
                    } catch {
                        SpeechMemoryTrace.record("synthesis.end", model: self.diagnosticModel, seconds: Date.timeIntervalSinceReferenceDate - start, code: flag.cancelled ? -5 : -1)
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let wayu = self.wayuContext, let directory = self.wayuDirectory {
                    do {
                        guard !flag.cancelled else { throw CancellationError() }
                        var tokens = [Int64](repeating: 0, count: 502)
                        let length = ot_wayu_frontend_tokens(text, &tokens, Int32(tokens.count))
                        guard length > 2 else { throw length == -2 ? PipelineError.tooLong : WayuSpeechError.pronunciation }
                        var style = [Float](repeating: 0, count: 256)
                        guard ot_wayu_frontend_style(directory.appendingPathComponent("wayu-styles.bin").path, self.wayuVoice.rawValue, length - 2, &style) != 0 else { throw PipelineError.modelLoad }
                        guard !flag.cancelled else { throw CancellationError() }
                        var count: Int32 = 0
                        let output = ot_wayu_generate(wayu, &tokens, length, &style, &count, UnsafeMutableRawPointer(flag.pointer))
                        guard let output else {
                            if flag.cancelled { throw CancellationError() }
                            throw count == -2 ? PipelineError.tooLong : PipelineError.invalidAudio
                        }
                        defer { ot_wayu_audio_free(output) }
                        guard !flag.cancelled else { throw CancellationError() }
                        continuation.resume(returning: SpeechPCM(samples: Array(UnsafeBufferPointer(start: output, count: Int(count))), sampleRate: 24000))
                    } catch { continuation.resume(throwing: error) }
                    return
                }
                guard let context = self.context, !flag.cancelled else { continuation.resume(throwing: CancellationError()); return }
                // Voices read "16-е" as digits plus a letter; spell such ordinals out first.
                let text = self.languageCode == "ru" ? RussianSpeechText.expandOrdinals(text) : text
                let input: String
                do { input = try self.mmsTokens.map { try MMSSpeechText.prepare(text, tokens: $0, language: self.languageCode) } ?? text }
                catch { continuation.resume(throwing: error); return }
                let synthesisStart = Date.timeIntervalSinceReferenceDate
                SpeechMemoryTrace.record("synthesis.begin", model: self.diagnosticModel)
                let output = self.supertonic
                    ? ot_supertonic_generate(context, text, self.languageCode, UnsafeMutableRawPointer(flag.pointer))
                    : ot_tts_generate(context, input, UnsafeMutableRawPointer(flag.pointer))
                SpeechMemoryTrace.record("synthesis.end", model: self.diagnosticModel, seconds: Date.timeIntervalSinceReferenceDate - synthesisStart, code: output?.pointee.n ?? -1)
                guard let output else { continuation.resume(throwing: flag.cancelled ? CancellationError() : PipelineError.invalidAudio); return }
                defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(output) }
                guard !flag.cancelled else { continuation.resume(throwing: CancellationError()); return }
                let n = Int(output.pointee.n); let rate = Int(output.pointee.sample_rate)
                guard rate > 0, n > 0, let samples = output.pointee.samples else { continuation.resume(throwing: PipelineError.invalidAudio); return }
                guard n <= rate * 60 else { continuation.resume(throwing: PipelineError.tooLong); return }
                let pcm = Array(UnsafeBufferPointer(start: samples, count: n))
                guard pcm.allSatisfy(\.isFinite) else { continuation.resume(throwing: PipelineError.invalidAudio); return }
                continuation.resume(returning: SpeechPCM(samples: pcm, sampleRate: rate))
            } }
        } onCancel: { flag.cancel() }
    }
    func unload() async {
        cancel()
        await withCheckedContinuation { c in queue.async {
            self.omniVoice = nil
            if let p = self.context { SherpaOnnxDestroyOfflineTts(p); self.context = nil }
            if let p = self.wayuContext { ot_wayu_free(p); self.wayuContext = nil }; self.wayuDirectory = nil
            c.resume()
        } }
    }
    deinit { if let context { SherpaOnnxDestroyOfflineTts(context) }; if let wayuContext { ot_wayu_free(wayuContext) } }
}

private enum WayuSpeechError: LocalizedError {
    case pronunciation
    var errorDescription: String? { L10n.text("Wayu не смог прочитать часть текста. Попробуйте записать иностранные имена тайскими буквами. Перевод сохранён.") }
}
