import Foundation
import Combine

/// Closing invalidates every pending activation, including callers waiting for a previous close.
@MainActor public final class CameraActivationGate {
    private var generation = 0
    public init() {}
    public func invalidate() { generation += 1 }
    public func waitForClose(_ closing: Task<Void,Never>?) async -> Bool {
        let id = generation
        await closing?.value
        return id == generation && !Task.isCancelled
    }
}

/// A single photo import. Cancellation clears UI state immediately; stale completions have no effect.
@MainActor public final class ImageImportSession: ObservableObject {
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?
    private var generation = 0
    private var job: Task<Void,Never>?
    public init() {}
    public func start(load: @escaping @MainActor () async throws -> Data?, consume: @escaping @MainActor (Data) async -> Void) {
        cancel(); let id = generation; busy = true; error = nil
        job = Task {
            defer { if id == generation { busy = false; job = nil } }
            do {
                let data = try await load()
                try Task.checkCancellation()
                guard id == generation else { return }
                guard let data else { error = L10n.text("Не удалось открыть изображение. Выберите другое фото."); return }
                await consume(data)
            } catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
    }
    public func cancel() { generation += 1; job?.cancel(); job = nil; busy = false; error = nil }
}
