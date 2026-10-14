import XCTest
import OfflineCore
@testable import Kat_translator

private final class BudgetProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TranslationProgress] = []
    func append(_ value: TranslationProgress) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshots: [TranslationProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

final class TranslationOutputBudgetTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func fixture(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func testLongNewsPlansResponseSpaceBeforeGeneration() async throws {
        guard let reportPath = ProcessInfo.processInfo.environment["KAT_PREFLIGHT_REPORT"] else {
            throw XCTSkip("Opt-in long-input preflight benchmark")
        }
        let article = try fixture("tests/fixtures/translation-output-limit-ru.txt")
        let secondArticle = try fixture("tests/fixtures/context-comparison-yandex-ru.txt")
        // Two distinct articles together: avoid a repeated-source fixture that a model may deduplicate.
        let source = [article, secondArticle].joined(separator: "\n\n")
        let backend = LlamaTranslationBackend()
        try await backend.load(modelURL: root.appendingPathComponent("model-store/downloads/Index-Translate-9B.Q4_K_M.gguf"), model: .index9B)
        do {
            _ = try await backend.translate(text: "Проверка готовности модели.", source: .russian, target: .english)
            let progress = BudgetProgress()
            let started = Date().timeIntervalSince1970
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            let result = try await backend.translate(text: source, source: .russian, target: .english) { progress.append($0) }
            let updates = progress.snapshots
            let data = try JSONSerialization.data(withJSONObject: [
                "source": source, "sourceCharacters": source.count, "translation": result.text,
                "startedAt": started, "finishedAt": Date().timeIntervalSince1970,
                "seconds": result.processingSeconds, "fragments": result.fragments,
                "thermalBefore": thermal, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue,
                "progress": updates.map { ["totalParts": $0.totalParts, "completedParts": $0.completedParts, "completedCharacters": $0.completedCharacters] }
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: reportPath))
            await backend.unload()
            XCTAssertEqual(updates.first?.totalParts, 2, "Reserve response space before the first generation, not after a discarded attempt")
            XCTAssertTrue(updates.allSatisfy { $0.totalParts == 2 }, "Planned parts should remain stable for this fixture")
            XCTAssertEqual(updates.last?.completedCharacters, source.count)
            XCTAssertEqual(result.fragments, 2)
            // Landmarks span both articles. Inspect full output in the report as well.
            for phrase in ["Khortytsia", "Civil Defense", "local authorities", "Yandex", "Sasovo", "Malkov"] {
                XCTAssertTrue(result.text.localizedCaseInsensitiveContains(phrase), phrase)
            }
        } catch {
            await backend.unload(); throw error
        }
    }
    /// Production backend + actual Index weights, opt-in to avoid loading a large model in normal unit runs.
    func testNewsFitsWithoutDiscardedGeneration() async throws {
        guard let reportPath = ProcessInfo.processInfo.environment["KAT_OUTPUT_BUDGET_REPORT"] else {
            throw XCTSkip("Opt-in output-budget benchmark")
        }
        let source = try fixture("tests/fixtures/translation-output-limit-ru.txt")
        let backend = LlamaTranslationBackend()
        try await backend.load(modelURL: root.appendingPathComponent("model-store/downloads/Index-Translate-9B.Q4_K_M.gguf"), model: .index9B)
        do {
            _ = try await backend.translate(text: "Проверка готовности модели.", source: .russian, target: .english)
            var rows: [[String: Any]] = []
            var fragmentCounts: [Int] = [], progressCounts: [Int] = []
            for run in 1...2 {
                let progress = BudgetProgress()
                let start = Date().timeIntervalSince1970
                let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
                let result = try await backend.translate(text: source, source: .russian, target: .english) { progress.append($0) }
                let updates = progress.snapshots
                fragmentCounts.append(result.fragments)
                progressCounts.append(updates.map(\.totalParts).max() ?? 0)
                rows.append(["run": run, "startedAt": start, "finishedAt": Date().timeIntervalSince1970,
                    "seconds": result.processingSeconds, "firstTokenSeconds": result.firstTokenSeconds.map { $0 as Any } ?? NSNull(),
                    "fragments": result.fragments, "translation": result.text,
                    "progress": updates.map { ["totalParts": $0.totalParts, "completedParts": $0.completedParts, "completedCharacters": $0.completedCharacters] },
                    "thermalBefore": thermalBefore, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue])
                print("OUTPUT_BUDGET_RUN", run, result.processingSeconds, result.fragments)
            }
            let data = try JSONSerialization.data(withJSONObject: ["source": source, "sourceCharacters": source.count, "rows": rows], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: reportPath))
            await backend.unload()
            XCTAssertEqual(fragmentCounts, [1, 1], "The output fits the 2048-token context; do not discard 512 tokens and retry")
            XCTAssertEqual(progressCounts, [1, 1], "The progress must remain one part for this article")
        } catch {
            await backend.unload(); throw error
        }
    }
    func testLongGenerationCanBeCancelledAndNextTranslationStillWorks() async throws {
        guard ProcessInfo.processInfo.environment["KAT_OUTPUT_BUDGET_REPORT"] != nil else { throw XCTSkip("Opt-in native cancellation test") }
        let source = try fixture("tests/fixtures/translation-output-limit-ru.txt")
        let backend = LlamaTranslationBackend()
        try await backend.load(modelURL: root.appendingPathComponent("model-store/downloads/Index-Translate-9B.Q4_K_M.gguf"), model: .index9B)
        do {
            let progress = BudgetProgress()
            let task = Task { try await backend.translate(text: source, source: .russian, target: .english) { progress.append($0) } }
            while progress.snapshots.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
            try await Task.sleep(for: .milliseconds(500))
            backend.cancel()
            do { _ = try await task.value; XCTFail("Expected cancellation during generation") }
            catch is CancellationError {}
            let next = try await backend.translate(text: "Спасибо.", source: .russian, target: .english)
            XCTAssertTrue(next.text.lowercased().contains("thank"), next.text)
            XCTAssertEqual(next.fragments, 1)
            // Inputs larger than the prompt limit must still be partitioned before any generation.
            let oversized = Array(repeating: source, count: 3).joined(separator: "\n\n")
            let preflight = BudgetProgress()
            do {
                _ = try await backend.translate(text: oversized, source: .russian, target: .english) {
                    preflight.append($0); backend.cancel()
                }
                XCTFail("Expected cancellation immediately after preflight")
            } catch is CancellationError {}
            XCTAssertGreaterThan(preflight.snapshots.first?.totalParts ?? 0, 1)
            XCTAssertEqual(preflight.snapshots.first?.completedParts, 0)
            await backend.unload()
        } catch {
            await backend.unload(); throw error
        }
    }
}
