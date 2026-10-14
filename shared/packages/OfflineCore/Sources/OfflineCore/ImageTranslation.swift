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
    @Published public private(set) var ready = false
    @Published public private(set) var working = false
    @Published public private(set) var error: String?
    @Published public private(set) var complete = false
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
        generation += 1; let id = generation; working = true; error = nil
        let task = Task {
            defer { working = false; job = nil }
            do { try await backend.load(modelURL: url, model: model); try Task.checkCancellation(); guard id == generation else { return }; ready = true }
            catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
        job = task; await task.value
    }
    public func submit(_ blocks: [ImageTextBlock], source: SpeechLanguage, target: SpeechLanguage? = nil) {
        guard ready, closing == nil else { return }
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
    }
    private func startIfNeeded() {
        guard job == nil, ready, !complete, !blocks.isEmpty else { return }
        let id = generation; working = true
        job = Task {
            defer { working = false; job = nil }
            do {
                while id == generation, !Task.isCancelled,
                      let block = blocks.first(where: { cache[key($0.text, source, target)] == nil }) {
                    let language = source, destination = target, cacheKey = key(block.text, source, target)
                    let result = try await backend.translate(text: block.text, source: language, target: destination)
                    try Task.checkCancellation(); guard id == generation else { return }
                    guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PipelineError.inference }
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
    public func clearScene() { blocks = []; publish() }
    public func waitForIdle() async { await job?.value }
    public func close(preservingResult: Bool = false) async {
        if let closing { await closing.value; return }
        generation += 1; ready = false; job?.cancel(); backend.cancel(); if !preservingResult { clearScene() }
        let previous = job
        let task = Task { await previous?.value; await backend.unload(); cache = [:]; order = []; closing = nil }
        closing = task; await task.value
    }
}
