import Foundation
import Combine
@MainActor public final class SessionController: ObservableObject {
    @Published public private(set) var transcript = ""
    @Published public private(set) var isProcessing = false
    @Published public private(set) var isLoaded = false
    @Published public private(set) var isLoading = false
    @Published public private(set) var isUnloading = false
    @Published public private(set) var error: String?
    @Published public private(set) var lastResult: ASRResult?
    @Published public private(set) var loadSeconds: Double?
    public var isBusy: Bool { isProcessing || isLoading || isUnloading }
    private let backend: any ASRBackend
    private var operation = 0
    private var active: Task<ASRResult, Error>?
    private var loading: Task<Void, Error>?
    private var unloading: Task<Void, Never>?
    public init(backend: any ASRBackend) { self.backend = backend }
    public func load(_ url: URL) async {
        guard !isBusy, !isLoaded else { return }
        operation += 1; let id = operation
        isLoading = true; error = nil
        let start = ProcessInfo.processInfo.systemUptime
        let job = Task { try await backend.load(modelURL: url) }; loading = job
        defer { isLoading = false; loading = nil }
        do {
            try await job.value
            guard id == operation else { return }
            isLoaded = true; loadSeconds = ProcessInfo.processInfo.systemUptime - start
        } catch { if id == operation { self.error = error.localizedDescription } }
    }
    public func recognize(_ audio: CapturedAudio, language: SpeechLanguage) async {
        guard isLoaded, !isBusy, !audio.samples.isEmpty else { return }
        operation += 1; let id = operation
        isProcessing = true; error = nil; transcript = ""; lastResult = nil
        let job = Task { try await backend.transcribe(audio, language: language) }; active = job
        defer { isProcessing = false; active = nil }
        do {
            let result = try await job.value
            guard id == operation, !job.isCancelled else { return }
            transcript = result.text; lastResult = result
            if result.text.isEmpty { error = L10n.text("Речь не распознана. Попробуйте ещё раз.") }
        } catch is CancellationError { }
        catch { if id == operation { self.error = error.localizedDescription } }
    }
    public func cancel() {
        operation += 1; active?.cancel(); backend.cancel(); transcript = ""; lastResult = nil
    }
    public func unload() async {
        if let unloading { await unloading.value; return }
        isUnloading = true
        cancel()
        let recognition = active; let load = loading
        let job = Task {
            _ = await recognition?.result; _ = await load?.result
            await backend.unload()
            isLoaded = false; isUnloading = false; loadSeconds = nil
            unloading = nil
        }
        unloading = job
        await job.value
    }
}
