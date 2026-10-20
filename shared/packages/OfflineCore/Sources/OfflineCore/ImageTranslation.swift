import Foundation
import Combine

/// Normalized coordinates, with the origin at the top left of the upright image.
public struct ImageTextBox: Sendable, Equatable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        let right = min(1, max(0, x + width)), bottom = min(1, max(0, y + height))
        self.x = min(1, max(0, x)); self.y = min(1, max(0, y))
        self.width = max(0, right - self.x); self.height = max(0, bottom - self.y)
    }
}
public struct ImageTextBlock: Sendable, Equatable {
    public let text: String, box: ImageTextBox
    public init(text: String, box: ImageTextBox) { self.text = text; self.box = box }
}
public struct TranslatedImageBlock: Sendable {
    public let original: String, translation: String, box: ImageTextBox
}
/// One translator owns one native context. New scenes replace pending work rather than queueing frames.
@MainActor public final class ImageTranslationSession: ObservableObject {
    @Published public private(set) var translated: [TranslatedImageBlock] = []
    @Published public private(set) var partialTranslation: TranslatedImageBlock?
    @Published public private(set) var progress: TranslationProgress?
    public var showsTranslationPartials = false
    private var displayPartials = false
    private var model: TranslationModel = .index9B
    private var partialRequest: UUID?
    public var displayedBlocks: [TranslatedImageBlock] {
        blocks.compactMap { block in
            if let finished = translated.first(where: { $0.original == block.text && $0.box == block.box }) { return finished }
            if let partialTranslation, partialTranslation.original == block.text, partialTranslation.box == block.box { return partialTranslation }
            return nil
        }
    }
    @Published public private(set) var ready = false
    @Published public private(set) var working = false
    @Published public private(set) var error: String?
    @Published public private(set) var complete = false
    @Published public private(set) var timing: TranslationTiming?
    private var scene = 0
    private var recognitionSeconds: Double?
    private var translationSeconds = 0.0
    private let backend: any TranslationBackend
    private var blocks: [ImageTextBlock] = []
    private var source: SpeechLanguage = .russian
    private var target: SpeechLanguage = .english
    private var cache: [String: String] = [:]
    private var order: [String] = []
    private var generation = 0
    private var job: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    public init(backend: any TranslationBackend) { self.backend = backend }
    private func key(_ text: String, _ source: SpeechLanguage, _ target: SpeechLanguage) -> String { source.rawValue + ">" + target.rawValue + ":" + text }
    public func prepare(_ url: URL, model: TranslationModel = .index9B) async {
        if let closing { await closing.value }
        guard job == nil, !ready else { return }
        generation += 1; let id = generation; working = true; error = nil; self.model = model
        let task = Task {
            defer { working = false; job = nil }
            do { try await backend.load(modelURL: url, model: model); try Task.checkCancellation(); guard id == generation else { return }; ready = true }
            catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
        job = task; await task.value
    }
    public func submit(_ blocks: [ImageTextBlock], source: SpeechLanguage, target: SpeechLanguage? = nil, recognitionSeconds: Double? = nil) {
        guard ready, closing == nil else { return }
        scene += 1; partialRequest = nil; partialTranslation = nil; progress = nil
        displayPartials = showsTranslationPartials && model == .index9B
        timing = nil; self.recognitionSeconds = recognitionSeconds; translationSeconds = 0
        self.blocks = blocks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.box.width > 0 && $0.box.height > 0 }
        self.source = source; self.target = target ?? source.opposite; error = nil; publish()
        startIfNeeded()
    }
    private func publish() {
        translated = blocks.compactMap { block in
            guard let text = source == target ? block.text : cache[key(block.text, source, target)] else { return nil }
            return TranslatedImageBlock(original: block.text, translation: text, box: block.box)
        }
        complete = !blocks.isEmpty && translated.count == blocks.count
        timing = complete ? TranslationTiming(recognitionSeconds: recognitionSeconds, translationSeconds: translationSeconds) : nil
    }
    private func startIfNeeded() {
        guard job == nil, ready, !complete, !blocks.isEmpty else { return }
        let id = generation; working = true
        job = Task {
            defer { partialRequest = nil; partialTranslation = nil; progress = nil; working = false; job = nil }
            do {
                while id == generation, !Task.isCancelled,
                      let block = blocks.first(where: { cache[key($0.text, source, target)] == nil }) {
                    let language = source, destination = target, cacheKey = key(block.text, source, target), requestScene = scene
                    let request = UUID(), display = displayPartials
                    partialRequest = request
                    let result = try await backend.translate(text: block.text, source: language, target: destination, progress: { [weak self] value in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == id, self.scene == requestScene, self.partialRequest == request else { return }
                            self.progress = value
                        }
                    }, partial: { [weak self] text in
                        Task { @MainActor [weak self] in
                            guard display, let self, self.generation == id, self.scene == requestScene, self.partialRequest == request else { return }
                            self.partialTranslation = TranslatedImageBlock(original: block.text, translation: text, box: block.box)
                        }
                    })
                    partialRequest = nil; partialTranslation = nil; progress = nil
                    try Task.checkCancellation(); guard id == generation else { return }
                    guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PipelineError.inference }
                    if requestScene == scene { translationSeconds += max(0, result.processingSeconds) }
                    cache[cacheKey] = result.text; order.append(cacheKey)
                    // Keep current scene entries while evicting old scenes.
                    if order.count > 256, let victim = order.first(where: { candidate in !blocks.contains { key($0.text, source, target) == candidate } }) {
                        cache[victim] = nil; order.removeAll { $0 == victim }
                    }
                    publish()
                }
            } catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
    }
    public func clearScene() { scene += 1; partialRequest = nil; partialTranslation = nil; progress = nil; blocks = []; recognitionSeconds = nil; translationSeconds = 0; publish() }
    public func waitForIdle() async { await job?.value }
    public func close(preservingResult: Bool = false) async {
        if let closing { await closing.value; return }
        generation += 1; partialRequest = nil; partialTranslation = nil; progress = nil; ready = false; job?.cancel(); backend.cancel(); if !preservingResult { clearScene() }
        let previous = job
        let task = Task { await previous?.value; await backend.unload(); cache = [:]; order = []; closing = nil }
        closing = task; await task.value
    }
}
