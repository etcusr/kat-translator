import XCTest
import OfflineCore
#if os(macOS)
@testable import Kat_translator
#else
@testable import OfflineTranslator
import UIKit
#endif

private final class ArticleProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[String: Any]] = []
    func append(_ p: TranslationProgress) {
        lock.lock(); defer { lock.unlock() }
        values.append(["timestamp": Date().timeIntervalSince1970,
                       "totalParts": p.totalParts, "completedParts": p.completedParts,
                       "totalCharacters": p.totalCharacters, "completedCharacters": p.completedCharacters])
        print("ARTICLE_PROGRESS", p.completedParts, p.totalParts, p.completedCharacters)
    }
    var snapshots: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return values }
}

/// Explicitly opt-in. Uses the shipping translator, installed weights and unmodified limits.
final class ArticleDeviceBenchmarkTests: XCTestCase {
    /// Opt-in (KAT_COMPACT_ROUTING=1): device probe, Index 2B and OPUS direction packages through
    /// RoutedTranslationBackend. Files are copied beforehand into Documents/kat-bench.
    func testCompactRoutingOnDevice() async throws {
        guard ProcessInfo.processInfo.environment["KAT_COMPACT_ROUTING"] == "1" else { throw XCTSkip("Opt-in compact routing") }
        let bench = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("kat-bench")
        var lines: [String] = []
        let probe = await DeviceProbe.run()
        lines.append("probe \(probe)")
        let router = RoutedTranslationBackend()
        try await router.load(modelURL: bench.appendingPathComponent("Index-Translate-2B.Q4_K_M.gguf"), model: .index2B)
        let english = try await router.translate(text: "Поезд до Казани отправится завтра в 07:45.", source: .russian, target: .english)
        lines.append("2b \(english.processingSeconds) \(english.text)")
        try await router.load(modelURL: bench.appendingPathComponent("opus"), model: .opusDirections)
        let german = try await router.translate(text: "Поезд до Казани отправится завтра в 07:45.", source: .russian, target: .german)
        lines.append("ru-de \(german.processingSeconds) \(german.text)")
        let russian = try await router.translate(text: "Der Zug nach Kasan fährt morgen um 07:45 ab.", source: .german, target: .russian)
        lines.append("de-ru \(russian.processingSeconds) \(russian.text)")
        await router.unload()
        try lines.joined(separator: "\n").write(to: bench.appendingPathComponent("compact-routing.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(english.text.localizedCaseInsensitiveContains("train"), english.text)
        XCTAssertTrue(german.text.contains("Zug"), german.text)
        XCTAssertTrue(russian.text.lowercased().contains("поезд"), russian.text)
    }

    /// Opt-in Index 2B vs 9B comparison through the shipping backend (KAT_COMPACT_BENCHMARK=1).
    /// 2B weights and the optional RU article are copied beforehand into Documents/kat-bench;
    /// nothing is downloaded and the installed 9B stays in place.
    func testCompactModelsOnDevice() async throws {
        guard ProcessInfo.processInfo.environment["KAT_COMPACT_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in compact model comparison")
        }
        let bench = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("kat-bench")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "article-device-benchmark", withExtension: "json"))
        let articles = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])
        var cases: [(id: String, text: String, source: SpeechLanguage, target: SpeechLanguage)] = []
        if let shake = articles.first(where: { $0["id"] as? String == "shake" }), let text = shake["text"] as? String {
            cases.append(("shake-en-ru", text, .english, .russian))
        }
        let russian = bench.appendingPathComponent("article-ru.txt")
        if let text = try? String(contentsOf: russian, encoding: .utf8) { cases.append(("news-ru-en", text.trimmingCharacters(in: .whitespacesAndNewlines), .russian, .english)) }
        let store = ModelStore(root: ModelDownloader.root.appendingPathComponent("Models"))
        let installed9B = try await store.installedURL(for: ModelCatalog.indexTranslation)
        var models: [(String, URL)] = [("index-2b", bench.appendingPathComponent("Index-Translate-2B.Q4_K_M.gguf"))]
        if let installed9B { models.append(("index-9b", installed9B)) }
        var rows: [[String: Any]] = []
        let output = bench.appendingPathComponent("compact-report.json")
        func save() throws {
            let report: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString, "physicalMemory": ProcessInfo.processInfo.physicalMemory, "rows": rows]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        for (name, url) in models {
            let backend = LlamaTranslationBackend()
            let loadStart = ProcessInfo.processInfo.systemUptime
            try await backend.load(modelURL: url, model: .index9B)
            let load = ProcessInfo.processInfo.systemUptime - loadStart
            _ = try await backend.translate(text: "The telescope is ready for its next test.", source: .english, target: .russian)
            for pass in 1...2 {
                for item in cases {
                    try await Task.sleep(for: .seconds(10))
                    let thermal = ProcessInfo.processInfo.thermalState.rawValue
                    let result = try await backend.translate(text: item.text, source: item.source, target: item.target)
                    rows.append(["model": name, "case": item.id, "pass": pass, "loadSeconds": load, "seconds": result.processingSeconds,
                                 "firstTokenSeconds": result.firstTokenSeconds.map { $0 as Any } ?? NSNull(), "fragments": result.fragments,
                                 "sourceCharacters": item.text.count, "translation": result.text,
                                 "thermalBefore": thermal, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue])
                    try save()
                    print("COMPACT_DONE", name, item.id, pass, result.processingSeconds)
                    XCTAssertFalse(result.text.isEmpty)
                }
            }
            await backend.unload()
        }
    }

    func testArticlesOnDevice() async throws {
        guard ProcessInfo.processInfo.environment["KAT_ARTICLE_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in article/device comparison")
        }
        #if os(iOS)
        let previousIdle = await MainActor.run { () -> Bool in
            let previous = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            return previous
        }
        defer { Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = previousIdle } }
        #endif
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "article-device-benchmark", withExtension: "json"))
        let articles = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])
        let output = ProcessInfo.processInfo.environment["KAT_ARTICLE_REPORT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("article-device-benchmark.json")
        let store = ModelStore(root: ModelDownloader.root.appendingPathComponent("Models"))
        let installed = try await store.installedURL(for: ModelCatalog.indexTranslation)
        #if os(macOS)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let modelURL = installed ?? repo.appendingPathComponent("Dependencies/downloads/Index-Translate-9B.Q4_K_M.gguf")
        #else
        let modelURL = try XCTUnwrap(installed, "Index 9B must already be installed; benchmark never downloads weights")
        #endif
        let backend = LlamaTranslationBackend()
        var rows: [[String: Any]] = []
        var report: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemory": ProcessInfo.processInfo.physicalMemory,
            "model": ModelCatalog.indexTranslation.id, "modelSHA256": ModelCatalog.indexTranslation.sha256,
            "direction": "eng-rus", "contextTokens": 2048, "repeatPasses": 2,
            "pauseBetweenRunsSeconds": 10, "startedAt": Date().timeIntervalSince1970,
            "articles": articles]
        func save() throws {
            report["rows"] = rows
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        try save()
        let loadStart = ProcessInfo.processInfo.systemUptime
        try await backend.load(modelURL: modelURL, model: .index9B)
        report["loadSeconds"] = ProcessInfo.processInfo.systemUptime - loadStart
        do {
            let warmup = try await backend.translate(text: "The telescope is ready for its next test.", source: .english, target: .russian)
            report["warmupSeconds"] = warmup.processingSeconds
            try save()
            for pass in 1...2 {
                let ordered = pass == 1 ? articles : Array(articles.reversed())
                for article in ordered {
                    try await Task.sleep(for: .seconds(10))
                    let id = try XCTUnwrap(article["id"] as? String)
                    let source = try XCTUnwrap(article["text"] as? String)
                    let progress = ArticleProgress()
                    let started = Date().timeIntervalSince1970
                    let thermal = ProcessInfo.processInfo.thermalState.rawValue
                    print("ARTICLE_START", id, pass, source.count, thermal)
                    let result = try await backend.translate(text: source, source: .english, target: .russian) { progress.append($0) }
                    let updates = progress.snapshots
                    rows.append(["id": id, "pass": pass, "sourceCharacters": source.count,
                        "startedAt": started, "finishedAt": Date().timeIntervalSince1970,
                        "seconds": result.processingSeconds, "translation": result.text,
                        "firstTokenSeconds": result.firstTokenSeconds.map { $0 as Any } ?? NSNull(),
                        "fragments": result.fragments, "progress": updates,
                        "thermalBefore": thermal, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue])
                    try save()
                    print("ARTICLE_DONE", id, pass, result.processingSeconds, result.fragments)
                    XCTAssertFalse(result.text.isEmpty)
                    XCTAssertEqual(updates.last?["completedCharacters"] as? Int, source.count)
                    XCTAssertEqual(updates.last?["completedParts"] as? Int, result.fragments)
                }
            }
            await backend.unload()
            report["finishedAt"] = Date().timeIntervalSince1970
            report["completed"] = true
            try save()
        } catch {
            await backend.unload()
            report["error"] = String(describing: error)
            try? save()
            throw error
        }
    }
}
