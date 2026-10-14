import Foundation
import Combine

/// A full check makes the hint visible for the entire restoration batch,
/// including the gaps between files. Cached-only batches remain silent.
@MainActor final class ModelVerificationStatus: ObservableObject {
    static let shared = ModelVerificationStatus()
    @Published private(set) var active = false
    private var restoring = false
    func beginRestoration() { restoring = true; active = false }
    func endRestoration() { restoring = false; active = false }
    nonisolated static func changed(_ checking: Bool) {
        guard checking else { return }
        DispatchQueue.main.async {
            guard shared.restoring, !shared.active else { return }
            shared.active = true
        }
    }
}
