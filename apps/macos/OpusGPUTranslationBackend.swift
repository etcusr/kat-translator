import Foundation
import OfflineCore
import Darwin

/// One request owns cancellation. Killing this dedicated worker releases Metal allocations
/// without disturbing the separately embedded Index/Thai interpreter.
private final class OpusGPUJob: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    func check() throws { lock.lock(); defer { lock.unlock() }; if stopped { throw CancellationError() } }
    func bind(_ process: Process?) throws {
        lock.lock(); defer { lock.unlock() }
        if stopped { throw CancellationError() }; self.process = process
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }; stopped = true
        if let process, process.isRunning { process.terminate() }
    }
}

final class OpusGPUTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.opus.metal", qos: .userInitiated)
    private let lock = NSLock()
    private var job: OpusGPUJob?
    private var directory: URL?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    private func setJob(_ value: OpusGPUJob?) { lock.lock(); defer { lock.unlock() }; job = value }
    func cancel() { lock.lock(); defer { lock.unlock() }; job?.cancel() }
    private func closeWorker() {
        if let process { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        try? input?.close(); try? output?.close(); input = nil; output = nil; process = nil; pending = Data()
    }
    private func response(_ job: OpusGPUJob) throws -> [String: Any] {
        while true {
            try job.check()
            if let end = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: end); pending.removeSubrange(...end)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw PipelineError.inference }
                return object
            }
            guard let output else { throw PipelineError.inference }
            // FileHandle.read(upToCount:) may wait for the entire buffer on a pipe.
            // A protocol line can be much shorter; consume the currently available bytes.
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                try job.check(); throw PipelineError.inference
            }
            pending.append(contentsOf: bytes.prefix(count))
            guard pending.count < 1024 * 1024 else { throw PipelineError.inference }
        }
    }
    private func ensureWorker(_ job: OpusGPUJob) throws {
        try job.check()
        if let process, process.isRunning { try job.bind(process); return }
        closeWorker()
        guard let directory, let resources = Bundle.main.resourceURL,
              let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("OpusPython") else { throw PipelineError.modelLoad }
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = executable
        process.arguments = ["-S", "-B", resources.appendingPathComponent("OpusPython/opus_gpu.py").path, directory.path]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8",
            "PYTHONHOME": resources.appendingPathComponent("python").path,
            "PYTHONPATH": resources.appendingPathComponent("OpusPython").path,
            "PYTHONNOUSERSITE": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.standardError
        self.process = process; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        try job.check(); try process.run()
        try? stdin.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close()
        try job.bind(process)
        let ready = try response(job)
        guard ready["ready"] as? Bool == true, ready["device"] as? String == "mps:0" else { throw PipelineError.modelLoad }
        NSLog("OPUS GPU worker ready: Metal FP16 beam5")
    }
    private func request(_ command: String, text: String, source: SpeechLanguage, target: SpeechLanguage, job: OpusGPUJob) throws -> [String: Any] {
        try ensureWorker(job)
        var bytes = try JSONSerialization.data(withJSONObject: ["command": command, "text": text, "source": source.rawValue, "target": target.rawValue])
        bytes.append(10); try input?.write(contentsOf: bytes)
        let result = try response(job); try job.check(); return result
    }
    func load(modelURL: URL) async throws {
        let job = OpusGPUJob(); setJob(job); defer { setJob(nil) }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in queue.async {
                do { self.closeWorker(); self.directory = modelURL; try self.ensureWorker(job); try job.bind(nil); c.resume() }
                catch { self.closeWorker(); c.resume(throwing: error) }
            } }
        } onCancel: { job.cancel() }
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: { _ in })
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        try Task.checkCancellation()
        guard TranslationModel.opusBig.supports(source: source, target: target) else { throw PipelineError.modelLanguageUnavailable }
        try TranslationPrompt.validate(text)
        if source == target { return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) }
        let job = OpusGPUJob(); setJob(job); defer { setJob(nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in queue.async {
                do {
                    let start = ProcessInfo.processInfo.systemUptime
                    var preflightError: Error?
                    let pieces = try OpusTextSegments.split(text) { part in
                        if preflightError != nil { return true }
                        do {
                            let answer = try self.request("count", text: part, source: source, target: target, job: job)
                            guard answer["code"] as? Int == 0, let count = answer["count"] as? Int else { throw PipelineError.inference }
                            return count > 0 && count <= 480
                        } catch { preflightError = error; return true }
                    }
                    if let preflightError { throw preflightError }
                    var work = TranslationWork(pieces: pieces), translated = "", fragments = 0
                    progress(work.progress)
                    while let part = work.current {
                        let input = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if input.isEmpty { work.completeCurrent(); progress(work.progress); continue }
                        let answer = try self.request("run", text: input, source: source, target: target, job: job)
                        if answer["code"] as? Int == 1 { try work.splitCurrent(); progress(work.progress); continue }
                        guard answer["code"] as? Int == 0, answer["device"] as? String == "mps:0",
                              let output = answer["text"] as? String, !output.isEmpty else { throw PipelineError.inference }
                        if !translated.isEmpty { translated += part.prefix(while: \.isWhitespace).contains("\n") ? "\n\n" : " " }
                        translated += output; fragments += 1; work.completeCurrent(); progress(work.progress)
                    }
                    try job.bind(nil)
                    guard !translated.isEmpty else { throw PipelineError.noSpeech }
                    c.resume(returning: TranslationResult(text: translated, firstTokenSeconds: nil, processingSeconds: ProcessInfo.processInfo.systemUptime-start, fragments: fragments))
                } catch { self.closeWorker(); c.resume(throwing: error) }
            } }
        } onCancel: { job.cancel() }
    }
    func unload() async {
        cancel()
        await withCheckedContinuation { c in queue.async { self.closeWorker(); self.directory = nil; c.resume() } }
    }
    deinit { closeWorker() }
}
