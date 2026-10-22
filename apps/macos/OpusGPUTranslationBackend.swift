import Foundation
import OfflineCore
import Darwin

/// One request owns cancellation. Cancel asks the worker to stop the request in flight, so the warm worker
/// (both direction models) survives; a worker that does not answer in time is killed, which releases
/// Metal allocations without disturbing the separately embedded Index/Thai interpreter.
private final class OpusGPUJob: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var interrupt: (() -> Void)?
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func check() throws { if isStopped { throw CancellationError() } }
    func bind(_ interrupt: (() -> Void)?) throws {
        lock.lock(); defer { lock.unlock() }
        if stopped { throw CancellationError() }; self.interrupt = interrupt
    }
    func cancel() {
        lock.lock(); stopped = true; let interrupt = interrupt; self.interrupt = nil; lock.unlock()
        interrupt?()
    }
}

final class OpusGPUTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.opus.metal", qos: .userInitiated)
    private let lock = NSLock()
    /// Guards `input`: cancel writes to the worker from the cancelling thread.
    private let inputLock = NSLock()
    private let script: URL?
    private var job: OpusGPUJob?
    private var directory: URL?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    private var requestID = 0
    /// True when the worker has answered everything sent to it and can serve the next request.
    private var synced = false
    static let cancelGrace: TimeInterval = 3
    /// `script` replaces the bundled worker in tests.
    init(script: URL? = nil) { self.script = script }
    private func setJob(_ value: OpusGPUJob?) { lock.lock(); defer { lock.unlock() }; job = value }
    func cancel() { lock.lock(); let job = job; lock.unlock(); job?.cancel() }
    var workerProcessIdentifier: Int32? { queue.sync { process?.isRunning == true ? process?.processIdentifier : nil } }
    private func closeWorker() {
        if let process { Self.stop(process) }
        inputLock.lock(); try? input?.close(); input = nil; inputLock.unlock()
        try? output?.close(); output = nil; process = nil; pending = Data(); synced = false
    }
    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        var bytes = try JSONSerialization.data(withJSONObject: object); bytes.append(10)
        inputLock.lock(); defer { inputLock.unlock() }
        guard handle === input else { throw PipelineError.inference }
        try handle.write(contentsOf: bytes)
    }
    /// Process.waitUntilExit() could wait forever here: after a cancelled request the next worker had exited,
    /// yet unload() never returned (sample: closeWorker → -[NSConcreteTask waitUntilExit], no worker process left).
    /// Wait with waitpid(WNOHANG) instead and escalate to SIGKILL; an unreaped child's pid cannot be reused.
    static func stop(_ process: Process, grace: TimeInterval = 3) {
        guard process.processIdentifier > 0 else { return }
        let pid = process.processIdentifier
        if process.isRunning { process.terminate() }
        func reaped(within seconds: TimeInterval) -> Bool {
            let end = ProcessInfo.processInfo.systemUptime + seconds
            while true {
                var status: Int32 = 0
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid || (result == -1 && errno == ECHILD) || !process.isRunning { return true }
                if result == -1 && errno != EINTR { return true }
                if ProcessInfo.processInfo.systemUptime >= end { return false }
                usleep(10_000)
            }
        }
        if reaped(within: grace) { return }
        kill(pid, SIGKILL)
        _ = reaped(within: grace)
    }
    /// Reads the reply to request `id` (nil: the ready line of a starting worker). A cancelled request still
    /// waits up to `cancelGrace` for the worker's reply, so the protocol stays in step and the worker is kept.
    private func response(_ job: OpusGPUJob, id: Int?) throws -> [String: Any] {
        var deadline: TimeInterval?
        while true {
            if let end = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: end); pending.removeSubrange(...end)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == id else { throw PipelineError.inference }
                synced = true
                return object
            }
            if job.isStopped {
                guard id != nil else { throw CancellationError() }
                let now = ProcessInfo.processInfo.systemUptime
                if deadline == nil { deadline = now + Self.cancelGrace }
                if let deadline, now >= deadline { throw CancellationError() }
            }
            guard let output else { throw PipelineError.inference }
            var poller = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw PipelineError.inference }
            if ready == 0 { continue }
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
        if let process, process.isRunning, synced { return }
        closeWorker()
        guard let directory, let resources = Bundle.main.resourceURL,
              let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("OpusPython") else { throw PipelineError.modelLoad }
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = executable
        let worker = script ?? resources.appendingPathComponent("OpusPython/opus_gpu.py")
        process.arguments = ["-S", "-B", worker.path, directory.path]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8",
            "PYTHONHOME": resources.appendingPathComponent("python").path,
            "PYTHONPATH": resources.appendingPathComponent("OpusPython").path,
            "PYTHONNOUSERSITE": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.standardError
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) // EPIPE becomes a thrown write error
        inputLock.lock(); input = stdin.fileHandleForWriting; inputLock.unlock()
        self.process = process; output = stdout.fileHandleForReading
        try job.check(); try process.run()
        try? stdin.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close()
        let ready = try response(job, id: nil)
        guard ready["ready"] as? Bool == true, ready["device"] as? String == "mps:0" else { closeWorker(); throw PipelineError.modelLoad }
        NSLog("OPUS GPU worker ready: Metal FP16 beam5")
    }
    private func request(_ command: String, text: String, source: SpeechLanguage, target: SpeechLanguage, job: OpusGPUJob) throws -> [String: Any] {
        try ensureWorker(job)
        guard let input else { throw PipelineError.inference }
        requestID += 1; let id = requestID
        try job.bind { [weak self] in try? self?.send(["command": "cancel", "id": id], to: input) }
        synced = false
        try send(["command": command, "id": id, "text": text, "source": source.rawValue, "target": target.rawValue], to: input)
        let result = try response(job, id: id); try job.bind(nil); try job.check()
        // A failure inside the worker (e.g. Metal) may leave it unusable: start a fresh one next time.
        if result["code"] as? Int == -1 { closeWorker(); throw PipelineError.inference }
        return result
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
                } catch {
                    // Cancellation and errors such as noSpeech keep a worker that answered everything.
                    if !self.synced { self.closeWorker() }
                    c.resume(throwing: error)
                }
            } }
        } onCancel: { job.cancel() }
    }
    func unload() async {
        cancel()
        await withCheckedContinuation { c in queue.async { self.closeWorker(); self.directory = nil; c.resume() } }
    }
    deinit { closeWorker() }
}
