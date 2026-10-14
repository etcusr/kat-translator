import XCTest
import SwiftUI
import AppKit
import AVFoundation
import Vision
import OfflineCore
@testable import Kat_translator

final class MacRuntimeTests: XCTestCase {
    @MainActor func testDownloadConsentAndCancellation() async throws {
        let suite = "download-consent-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DownloadAccessSettings(defaults: defaults)
        let request = DownloadRequest(network: DownloadNetworkMonitor(fixedState: .cellular), settings: settings)
        let items = [DownloadAccessItem(id: "model", bytes: 5_780_000_000, phase: .idle, installed: false)]
        var started = 0
        await request.request(items) { started += 1 }
        XCTAssertEqual(request.prompt?.maximumBytes, 5_780_000_000)
        XCTAssertEqual(started, 0)
        request.confirm(allowCellular: false)
        XCTAssertNotNil(request.prompt)
        request.cancel(); request.didDismiss()
        XCTAssertEqual(started, 0)
        XCTAssertFalse(settings.allowCellular)
        await request.request(items) { started += 1 }
        request.confirm(allowCellular: true)
        XCTAssertNil(request.prompt)
        XCTAssertEqual(started, 0, "Wait for dismissal before starting or navigating")
        XCTAssertTrue(DownloadAccessSettings(defaults: defaults).allowCellular)
        request.didDismiss(); request.didDismiss()
        XCTAssertEqual(started, 1)
        // A previously granted permission still shows the size before a new costly transfer.
        await request.request(items) { started += 1 }
        XCTAssertNotNil(request.prompt)
        request.cancel(); request.didDismiss()
        XCTAssertEqual(started, 1)
    }
    @MainActor func testOpusDirectionDownloadsRequireConsentForTheirCombinedSize() async throws {
        let suite = "opus-download-consent-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DownloadAccessSettings(defaults: defaults)
        let directions = OpusDirectionPackages()
        let routes = Array(OpusDirectionRoutes.all.filter(\.hosted).prefix(2))
        XCTAssertEqual(routes.count, 2)
        let selected = Set(routes.map(\.packageID))
        let pending = OpusDirectionsView.pending(selected, directions)
        let items = pending.flatMap(\.downloaders).map(\.downloadAccessItem)
        for allowed in [false, true] {
            settings.allowCellular = allowed
            let request = DownloadRequest(network: DownloadNetworkMonitor(fixedState: .cellular), settings: settings)
            var started = 0
            await request.request(items) { started += 1 }
            XCTAssertEqual(request.prompt?.maximumBytes, routes.reduce(0) { $0 + $1.bytes })
            XCTAssertEqual(started, 0)
            request.cancel(); request.didDismiss()
            XCTAssertEqual(started, 0)
            await request.request(items) { started += 1 }
            request.confirm(allowCellular: true)
            XCTAssertEqual(started, 0)
            request.didDismiss()
            XCTAssertEqual(started, 1)
        }
    }
    /// Opt-in: real network download, SHA-256 check and install inside the running app's storage
    /// (the sandbox container in the Mac App Store configuration).
    @MainActor func testRealDownloadInstallsIntoAppStorage() async throws {
        guard ProcessInfo.processInfo.environment["KAT_REAL_DOWNLOAD_TEST"] == "1" else { throw XCTSkip("Opt-in network download") }
        let part = try XCTUnwrap(RecognitionPackages.definitions.first { $0.id == RecognitionCatalog.ultraID }?.parts.first { $0.path == "JointDecisionv3.mlmodelc/weights/weight.bin" })
        let item = ModelDownloader(model: ModelDescriptor(id: "sandbox-download-check", title: "Sandbox download check", remoteURL: part.remoteURL, byteCount: part.byteCount, sha256: part.sha256))
        await item.restore(); await item.cancel()
        if item.installedURL != nil { await item.remove() }
        item.start()
        let deadline = Date().addingTimeInterval(300)
        while item.installedURL == nil && Date() < deadline {
            XCTAssertFalse([.failed, .restartRequired].contains(item.state.phase), item.state.error ?? "transfer failed")
            if [.failed, .restartRequired].contains(item.state.phase) { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let installed = try XCTUnwrap(item.installedURL, "not installed: \(item.state.phase.rawValue)")
        XCTAssertTrue(installed.path.hasPrefix(ModelDownloader.root.path))
        print("SANDBOX_DOWNLOAD_OK bytes=\(part.byteCount) sandboxed=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil) root=\(ModelDownloader.root.path.contains("/Containers/"))")
        await item.remove()
        try? FileManager.default.removeItem(at: item.transferRoot)
    }
    /// Opt-in for store-build checks: copy installed model folders (never History) from a direct
    /// build's data folder into this sandboxed app's container. APFS clones, so no extra space.
    func testSandboxSeedModels() throws {
        guard let source = ProcessInfo.processInfo.environment["KAT_SANDBOX_SEED_FROM"] else { throw XCTSkip("Opt-in sandbox seeding") }
        let root = ModelDownloader.root
        guard root.path.contains("/Library/Containers/") else { throw XCTSkip("Only inside a sandbox container") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Downloads/<id>/transfer.json records which archives are installed; merge it per item.
        var items = ["Models", "RecognitionPackages", "TranslationPackages", "VoicePackages", "transfer.json"]
        let transfers = URL(fileURLWithPath: source).appendingPathComponent("Downloads")
        items += ((try? FileManager.default.contentsOfDirectory(atPath: transfers.path)) ?? []).map { "Downloads/" + $0 }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        for name in items {
            let from = URL(fileURLWithPath: source).appendingPathComponent(name), to = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) else { continue }
            try FileManager.default.copyItem(at: from, to: to)
        }
        // Optional settings snapshot (`defaults export <direct bundle id>`), so state matches the direct build.
        if let plist = ProcessInfo.processInfo.environment["KAT_SANDBOX_SEED_DEFAULTS"],
           let values = NSDictionary(contentsOfFile: plist) as? [String: Any] {
            for (key, value) in values where !key.hasPrefix("NS") && !key.hasPrefix("Apple") { UserDefaults.standard.set(value, forKey: key) }
        }
        print("SANDBOX_SEEDED", (try? FileManager.default.contentsOfDirectory(atPath: root.path).sorted()) ?? [])
    }
    /// Opt-in: return the sandbox container to a first-launch state after store-build checks.
    func testSandboxResetContainerData() throws {
        guard ProcessInfo.processInfo.environment["KAT_SANDBOX_RESET"] == "1" else { throw XCTSkip("Opt-in sandbox reset") }
        let root = ModelDownloader.root
        guard root.path.contains("/Library/Containers/") else { throw XCTSkip("Never reset outside a sandbox container") }
        try? FileManager.default.removeItem(at: root)
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        print("SANDBOX_RESET", FileManager.default.fileExists(atPath: root.path))
    }
    @MainActor func testDownloadOfflineAndUnmeteredPaths() async throws {
        let suite = "download-network-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DownloadAccessSettings(defaults: defaults)
        let items = [DownloadAccessItem(id: "voice", bytes: 100_000_000, phase: .idle, installed: false)]
        for state: DownloadNetworkState in [.offline, .wifi, .wired, .expensive] {
            let request = DownloadRequest(network: DownloadNetworkMonitor(fixedState: state), settings: settings)
            var started = 0
            await request.request(items) { started += 1 }
            if state == .wifi || state == .wired {
                XCTAssertNil(request.prompt); XCTAssertEqual(started, 1)
            } else {
                XCTAssertNotNil(request.prompt); XCTAssertEqual(started, 0)
                request.confirm(allowCellular: true); request.didDismiss()
                XCTAssertEqual(started, state == .offline ? 0 : 1)
            }
        }
        let request = DownloadRequest(network: DownloadNetworkMonitor(fixedState: .offline), settings: settings)
        var localAction = false
        await request.request([]) { localAction = true }
        XCTAssertTrue(localAction, "Already installed packages need no connection")
        XCTAssertNil(request.prompt)
    }
    @MainActor func testDownloadWarningRendering() async throws {
        let request = DownloadRequest(network: DownloadNetworkMonitor(fixedState: .cellular))
        let host = NSHostingView(rootView: DownloadAccessPrompt(request: request, maximumBytes: 7_600_000_000))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(".build/cellular-download/mac-warning.png"))
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate; recognition.recognitionLanguages = ["en-US", "ru-RU"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([recognition])
        let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("7.6") || text.contains("7,6"), text)
        XCTAssertTrue(text.contains("Download") || text.contains("Скачать"), text)
        XCTAssertTrue(text.contains("Cancel") || text.contains("Отмена"), text)
    }
    @MainActor func testVoiceCardsVisibleWhileAutomaticPlaybackStillFinishing() async throws {
        let player = VoiceCardTestPlayer()
        let pipeline = ConversationPipeline(asr: VoiceCardTestASR(), translator: VoiceCardTestMT(), speech: VoiceCardTestSpeech(), player: player)
        let model = AppModel(session: pipeline)
        await model.packages.restore()
        let url = FileManager.default.temporaryDirectory
        await pipeline.prepare(PipelineFiles(asr: url, translation: url, voices: [.english: url], translationModel: .index9B), memorySaving: false)
        model.finishing = true // finishRecording awaits the entire automatic playback.
        let host = NSHostingView(rootView: ConversationView(model: model).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 900), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        let job = Task { await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, target: .english, speakResult: true, inputMode: "fixture", thermal: "nominal") }
        defer { pipeline.cancel(); job.cancel(); model.finishing = false; window.close() }
        for _ in 0..<1000 {
            if player.continuation != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(pipeline.isSpeaking)
        try await Task.sleep(for: .milliseconds(250))
        func assertVisibleCards(_ name: String) throws {
            // Read actual rendered pixels: in-process SwiftUI accessibility proxies
            // do not expose their descendants through NSAccessibilityProtocol.
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(".build/voice-playback-results/mac-\(name).png"))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "ru-RU"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(text.contains("Your room is ready"), text)
            XCTAssertTrue(text.contains("Ваш номер готов"), text)
        }
        try assertVisibleCards("playing")
        pipeline.toggleSpeechPause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(pipeline.isSpeechPaused)
        try assertVisibleCards("paused")
        pipeline.cancel(); await job.value
        XCTAssertEqual(pipeline.voiceFields.translatedText, "Your room is ready. Check in at eleven thirty.")
    }
    @MainActor func testDesktopResourceSampling() async throws {
        let monitor = ResourceMonitor()
        monitor.reset(); monitor.sample()
        XCTAssertNil(monitor.appCPU, "CPU needs two samples, never display an invented initial zero")
        try await Task.sleep(for: .milliseconds(250))
        monitor.sample()
        XCTAssertTrue((0...100).contains(try XCTUnwrap(monitor.appCPU)))
        XCTAssertTrue((0...100).contains(try XCTUnwrap(monitor.systemCPU)))
        XCTAssertGreaterThan(try XCTUnwrap(monitor.footprint), 0)
        XCTAssertGreaterThan(try XCTUnwrap(monitor.residentMemory), 0)
        XCTAssertGreaterThanOrEqual(monitor.peakFootprint, try XCTUnwrap(monitor.footprint))
        XCTAssertEqual(monitor.physicalMemory, ProcessInfo.processInfo.physicalMemory)
        XCTAssertNil(monitor.availableToApp, "The iOS allocation-budget metric is unavailable on Mac")
        XCTAssertGreaterThan(try XCTUnwrap(monitor.storageTotal), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(monitor.storageFree), try XCTUnwrap(monitor.storageTotal))
    }
    @MainActor func testAirborneCatHasUnclippedDrawingSpace() throws {
        var motion = CatProgressMotion(progress: 0.4, now: 0)
        motion.advance(progress: 0.55, active: true, now: 0.4)
        motion.advance(progress: 0.6, active: true, now: 0.8)
        for width: CGFloat in [72, 160] {
            for degrees in stride(from: 0.0, through: 360, by: 30) {
                let headroom = width * 0.6
                let view = CatProgressDrawing(motion: motion, playfulLeap: sin(.pi * degrees / 360), playfulRotation: degrees, headroom: headroom)
                    .frame(width: width, height: width * 0.8 + headroom).background(Color.black)
                let renderer = ImageRenderer(content: view); renderer.scale = 1
                let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                var top = image.pixelsHigh, bottom = 0, left = image.pixelsWide, right = 0
                for y in 0..<image.pixelsHigh {
                    for x in 0..<image.pixelsWide {
                        guard let c = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.greenComponent > 0.5 else { continue }
                        top = min(top, y); bottom = max(bottom, y); left = min(left, x); right = max(right, x)
                    }
                }
                XCTAssertGreaterThan(bottom, top, "Cat must be visible")
                XCTAssertGreaterThan(top, 1, "Airborne cat must not touch the Canvas ceiling at \(degrees) degrees")
                XCTAssertLessThan(bottom, image.pixelsHigh - 1)
                XCTAssertGreaterThan(left, 0)
                XCTAssertLessThan(right, image.pixelsWide - 1)
            }
        }
    }
    @MainActor func testResponsivePreparationRendering() throws {
        func render(_ size: CGSize) throws -> NSBitmapImageRep {
            let content = ModelPreparationView(checking: false, status: "Loading translation…", canCancel: false, cancel: {}, availableSize: size)
                .frame(width: size.width, height: size.height).background(Color.black)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content); renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: root.appendingPathComponent(".build/responsive-preparation/render-\(Int(size.width)).png"))
            return bitmap
        }
        func greenBounds(_ image: NSBitmapImageRep) -> (width: Int, height: Int, count: Int) {
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.greenComponent > 0.65 && color.redComponent > 0.4 && color.blueComponent < 0.4 {
                        xs.append(x); ys.append(y)
                    }
                }
            }
            return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0), xs.count)
        }
        let small = try render(CGSize(width: 420, height: 500))
        let large = try render(CGSize(width: 1440, height: 900))
        let a = greenBounds(small), b = greenBounds(large)
        XCTAssertGreaterThan(a.count, 100)
        XCTAssertGreaterThan(b.width, a.width * 2)
        XCTAssertGreaterThan(b.height, a.height * 3 / 2)
        XCTAssertGreaterThan(b.count, a.count * 2)
        for image in [small, large] {
            for point in [(0, 0), (image.pixelsWide - 1, image.pixelsHigh - 1), (20, image.pixelsHigh / 2)] {
                let color = try XCTUnwrap(image.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
                XCTAssertLessThan(color.redComponent + color.greenComponent + color.blueComponent, 0.01)
            }
        }
    }
    @MainActor func testArchivedSpeechPlayerPauseResumeSpeedAndStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = TranslationHistory(root: root)
        let saved = try await history.save(original: "fixture", translation: "fixture", source: .russian, target: .english)
        let id = try XCTUnwrap(saved)
        try await history.appendAudio(SpeechPCM(samples: Array(repeating: 0, count: 22050), sampleRate: 22050), to: id)
        try await history.finishAudio(id)
        let file = try await history.copyAudio(id, into: root.appendingPathComponent("exports"))
        let player = SpeechPlayer()
        defer { player.stop() }
        player.setRate(2)
        player.pause()
        var completed = false
        let playback = Task { try await player.play(file: file); completed = true }
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(completed, "Playback must stay paused even after the full audio duration")
        player.resume()
        try await playback.value
        XCTAssertTrue(completed)
        player.stop()
        player.pause()
        let stopped = Task { try await player.play(file: file) }
        try await Task.sleep(for: .milliseconds(100))
        player.stop()
        do { try await stopped.value; XCTFail("Stop must cancel the pending file playback") }
        catch is CancellationError {} catch { throw error }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    @MainActor func testAutomaticDetectedTextSwitchesRealOpusAndIndexModels() async throws {
        guard ProcessInfo.processInfo.environment["KAT_AUTO_ROUTING_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in installed OPUS and Index models") }
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        let opus = try XCTUnwrap(packages.translationURL(for: .opusBig))
        let index = try XCTUnwrap(packages.translationURL(for: .index9B))
        let pipeline = ConversationPipeline(asr: VoiceCardTestASR(), translator: RoutedTranslationBackend(),
            speech: VoiceCardTestSpeech(), player: VoiceCardTestPlayer())
        await pipeline.prepare(PipelineFiles(asr: nil, translation: opus, voices: [:], translationModel: .opusBig,
            translationResolver: { source, target in
                let model = try XCTUnwrap(AutoTranslation.resolve(source: source, target: target, strongDevice: false,
                    installed: { [.opusBig, .index9B].contains($0) }, directionInstalled: { _, _ in false }))
                return TranslationInstallation(model: model, url: model == .opusBig ? opus : index)
            }), memorySaving: false)
        XCTAssertTrue(pipeline.isReady, pipeline.error ?? "Preparation failed")
        for (text, language, expectedModel) in [
            ("Der Zug nach Berlin fährt morgen um 07:45 ab.", SpeechLanguage.german, TranslationModel.index9B),
            ("Поезд до Москвы отправится завтра в 07:45.", .russian, .opusBig)
        ] {
            await pipeline.run(audio: nil, text: text, source: nil, target: .english, speakResult: false, inputMode: "test", thermal: "nominal")
            XCTAssertNil(pipeline.error)
            XCTAssertEqual(pipeline.resolvedSource, language)
            XCTAssertEqual(pipeline.samples.last?.translationModelID, expectedModel.rawValue)
            XCTAssertTrue(pipeline.translatedText.localizedCaseInsensitiveContains("train"), pipeline.translatedText)
            XCTAssertTrue(pipeline.translatedText.contains("07:45") || pipeline.translatedText.contains("7:45"), pipeline.translatedText)
            print("AUTO_REAL_MODEL", expectedModel.rawValue, pipeline.translatedText)
        }
        await pipeline.unload()
    }
    @MainActor func testNativeBackendsWithExistingModels() async throws {
        var report: [String: Any] = [:]
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        XCTAssertTrue(packages.setupReady(LanguageSetup(primaryID: "ru", targetIDs: ["en"]), model: .index9B))
        let mt = LlamaTranslationBackend()
        try await mt.load(modelURL: try XCTUnwrap(packages.indexTranslation.installedURL), model: .index9B)
        let phrase = "Я приеду 15 октября в 23:30. Нужен номер на двоих на две ночи."
        let start = Date()
        let translation = try await mt.translate(text: phrase, source: .russian, target: .english)
        report["translation"] = translation.text; report["translationSeconds"] = Date().timeIntervalSince(start)
        XCTAssertFalse(translation.text.isEmpty)
        XCTAssertTrue(translation.text.contains("15"), translation.text)
        XCTAssertTrue(translation.text.contains("23:30") || translation.text.contains("11:30"), translation.text)
        await mt.unload()

        let asr = WhisperBackend()
        try await asr.load(modelURL: try XCTUnwrap(packages.whisper.installedURL))
        // Sandboxed store-build checks pass locations the container may read and write.
        let environment = ProcessInfo.processInfo.environment
        let fixtures = environment["KAT_ASR_FIXTURES"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent(".build/apple-asr/fixtures")
        let file = try AVAudioFile(forReading: fixtures.appendingPathComponent("short.aiff"))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let normalizer = AudioNormalizer()
        let audio = CapturedAudio(samples: try normalizer.convert(buffer) + normalizer.finish())
        let transcript = try await asr.transcribe(audio, language: .russian)
        report["transcription"] = transcript.text
        XCTAssertTrue(transcript.text.lowercased().contains("сахар"), transcript.text)
        await asr.unload()

        let tts = SherpaSpeechBackend()
        try await tts.load(directory: try XCTUnwrap(packages.voiceDirectories[ModelCatalog.englishVoice.id]), language: .english)
        let pcm = try await tts.synthesize(text: "Your room is ready. Check in at eleven thirty.")
        report["speechSamples"] = pcm.samples.count; report["speechRate"] = pcm.sampleRate
        XCTAssertGreaterThan(pcm.samples.count, pcm.sampleRate)
        XCTAssertGreaterThan(pcm.samples.map { abs($0) }.max() ?? 0, 0.01)
        await tts.unload()

        // Check embedded Python + resources, without using the host's Python installation.
        XCTAssertNotEqual(ot_wayu_frontend_init(Bundle.main.resourcePath!), 0)
        var tokens = [Int64](repeating: 0, count: 512)
        let count = ot_wayu_frontend_tokens("สวัสดีครับ", &tokens, 512)
        XCTAssertGreaterThan(count, 2)
        report["thaiTokenCount"] = count
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: (environment["KAT_RUNTIME_REPORT_DIR"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent(".build/macos")).appendingPathComponent("runtime-report.json"))
    }
    /// Opt-in (KAT_SPEECH_INTEGRATION=1): installed Whisper ASR, English TTS and the embedded Thai
    /// frontend, without translation models. Used for sandboxed store-build checks.
    @MainActor func testInstalledSpeechAndThaiFrontend() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KAT_SPEECH_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in installed speech models") }
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        // Same routed ASR as the app: Parakeet (Core ML) when installed, else Omnilingual or Whisper.
        let asr = RoutedASRBackend()
        let asrURL = try XCTUnwrap(packages.recognition.ultra ?? packages.omnilingualDirectory ?? packages.whisper.installedURL)
        try await asr.load(modelURL: asrURL)
        let fixtures = environment["KAT_ASR_FIXTURES"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent(".build/apple-asr/fixtures")
        let file = try AVAudioFile(forReading: fixtures.appendingPathComponent("short.aiff"))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let normalizer = AudioNormalizer()
        let transcript = try await asr.transcribe(CapturedAudio(samples: try normalizer.convert(buffer) + normalizer.finish()), language: .russian)
        XCTAssertTrue(transcript.text.lowercased().contains("сахар"), transcript.text)
        await asr.unload()
        let tts = SherpaSpeechBackend()
        func installedVoice() -> URL? { packages.voiceDirectories[ModelCatalog.englishVoice.id] ?? packages.voiceDirectories.first { $0.key.contains("en_US") }?.value }
        // Copied packages are re-verified once (new file identities); allow that to finish.
        for _ in 0..<60 where installedVoice() == nil { try await Task.sleep(for: .seconds(1)); await packages.restore() }
        let voice = try XCTUnwrap(installedVoice(), "voices=\(packages.voiceDirectories.keys.sorted()) errors=\(packages.errors) piper=\(packages.downloaders.filter { $0.model.id.contains("en_US") }.map { "\($0.model.id) installed=\($0.installedURL?.lastPathComponent ?? "nil") phase=\($0.state.phase.rawValue) error=\($0.state.error ?? "-")" })")
        try await tts.load(directory: voice, language: .english)
        let pcm = try await tts.synthesize(text: "Your room is ready. Check in at eleven thirty.")
        XCTAssertGreaterThan(pcm.samples.count, pcm.sampleRate)
        XCTAssertGreaterThan(pcm.samples.map { abs($0) }.max() ?? 0, 0.01)
        await tts.unload()
        XCTAssertNotEqual(ot_wayu_frontend_init(Bundle.main.resourcePath!), 0)
        var tokens = [Int64](repeating: 0, count: 512)
        let count = ot_wayu_frontend_tokens("สวัสดีครับ", &tokens, 512)
        XCTAssertGreaterThan(count, 2)
        print("SPEECH_INTEGRATION_OK model=\(asrURL.lastPathComponent) voice=\(voice.lastPathComponent) asr=\(transcript.text) ttsSamples=\(pcm.samples.count) thaiTokens=\(count)")
    }
    @MainActor func testImageOCRAndInvalidImport() async throws {
        let image = NSImage(size: NSSize(width: 1000, height: 240), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Check in at 23:30 on October 15." as NSString).draw(at: NSPoint(x: 35, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
            return true
        }
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let ocr = HybridOCR()
        let result = try await ocr.recognize(cg, source: .english, forceOpen: false, modelURL: nil)
        let text = result.blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("23:30"), text)
        XCTAssertTrue(text.contains("15"), text)
        await ocr.unload()
        let model = CameraModel(packages: .shared)
        model.importData(Data("not an image".utf8))
        XCTAssertNotNil(model.error); XCTAssertNil(model.image)
    }
    @MainActor func testImageResultPersistsAndArchivesOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageHistory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults.standard
        let keys = ["historyRecordText", "historyRecordImages"]
        let previous = keys.map { defaults.object(forKey: $0) }
        for key in keys { defaults.set(true, forKey: key) }
        defer { for (index, key) in keys.enumerated() { if let old = previous[index] { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        let history = HistoryModel(store: TranslationHistory(root: directory))
        let model = CameraModel(packages: .shared, history: history, backend: VoiceCardTestMT())
        model.source = .english; model.target = .russian
        await model.open(modelURL: directory)
        let fixture = NSImage(size: NSSize(width: 1000, height: 300), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Check in at 23:30 on October 15." as NSString).draw(at: NSPoint(x: 35, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
            return true
        }
        model.importData(try XCTUnwrap(fixture.tiffRepresentation))
        for _ in 0..<200 where model.recognizing { try await Task.sleep(for: .milliseconds(50)) }
        await model.translation.waitForIdle()
        XCTAssertTrue(model.translation.complete, model.error ?? "No image translation")
        let translated = model.translation.translated.map(\.translation)
        await model.close() // Same unload path as tab navigation.
        XCTAssertNotNil(model.image)
        XCTAssertEqual(model.translation.translated.map(\.translation), translated)
        XCTAssertFalse(model.translation.ready)
        for _ in 0..<3 { await model.open(modelURL: directory); await model.close() }
        await history.refresh()
        XCTAssertEqual(history.entries.count, 1, "Tab switches must not duplicate history")
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertTrue(entry.hasImage); XCTAssertEqual(entry.kind, .imageTranslation)
        let copy = await history.imageURL(entry.id)
        let file = try XCTUnwrap(copy)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertNotNil(NSImage(contentsOf: file))
        let host = NSHostingView(rootView: HistoryView(history: history).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 850), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(".build/voice-playback-results/image-history-mac.png"))
        await model.open(modelURL: directory)
        await model.clear()
        XCTAssertNil(model.image); XCTAssertFalse(model.translation.complete); XCTAssertTrue(model.translation.translated.isEmpty)
        await history.refresh(); XCTAssertEqual(history.entries.count, 1, "Clear removes current view only")
        await model.close()
    }

    @MainActor func testImageImportAndTranslation() async throws {
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        let model = CameraModel(packages: packages)
        model.source = .english; model.target = .russian
        await model.open(modelURL: try XCTUnwrap(packages.indexTranslation.installedURL))
        XCTAssertFalse(model.translation.ready, "An empty image tab must not load Index")
        XCTAssertFalse(model.opening)
        let image = NSImage(size: NSSize(width: 1000, height: 240), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Check in at 23:30 on October 15." as NSString).draw(at: NSPoint(x: 35, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
            return true
        }
        model.importData(try XCTUnwrap(image.tiffRepresentation))
        let deadline = Date().addingTimeInterval(90)
        while model.recognizing && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(model.recognizing)
        await model.translation.waitForIdle()
        XCTAssertNil(model.error)
        XCTAssertTrue(model.translation.complete, model.translation.error ?? "Image translation incomplete")
        let text = model.translation.translated.map(\.translation).joined(separator: " ")
        XCTAssertTrue(text.contains("23:30"), text)
        XCTAssertTrue(text.contains("15"), text)
        await model.close()
        XCTAssertFalse(model.translation.ready)
    }

    @MainActor func testMessengerLinksPreserveText() throws {
        let text = "Привет & 23:30 + 15% #ok\nSecond line?"
        for messenger in MacMessenger.allCases {
            let url = try XCTUnwrap(messenger.textURL(text))
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first?.value, text)
            XCTAssertEqual(url.scheme, messenger.scheme)
        }
    }
    @MainActor func testEmptyImageTabDoesNotPrepareTranslator() async throws {
        var preparations = 0
        let model = CameraModel(packages: .shared) { preparations += 1 }
        for _ in 0..<10 {
            await model.open(modelURL: URL(fileURLWithPath: "/unused.gguf"))
            XCTAssertFalse(model.opening); XCTAssertFalse(model.translation.ready)
            await model.close()
        }
        XCTAssertEqual(preparations, 0)
    }

    func testHistoryPreviewPreservesShortTextAndUnicode() {
        let short = "Check in at 23:30.\nOctober 15."
        XCTAssertEqual(HistoryPreview.text(short), short)
        XCTAssertFalse(HistoryPreview.isLong(short))
        let boundary = String(repeating: "猫", count: HistoryPreview.limit)
        XCTAssertEqual(HistoryPreview.text(boundary), boundary)
        XCTAssertFalse(HistoryPreview.isLong(boundary))
        let long = String(repeating: "👨‍👩‍👧‍👦", count: HistoryPreview.limit + 1)
        XCTAssertTrue(HistoryPreview.isLong(long))
        XCTAssertEqual(HistoryPreview.text(long), String(long.prefix(240)) + "…")
        XCTAssertEqual(long.count, 241, "Preview must not mutate the stored text")
        let lines = "One\nTwo\nThree\nFour"
        XCTAssertTrue(HistoryPreview.isLong(lines))
        XCTAssertEqual(HistoryPreview.text(lines), "One Two Three Four")
    }
    func testPanelSizesStayWithinHost() {
        for host in [CGSize(width: 780, height: 680), CGSize(width: 1040, height: 820), CGSize(width: 1700, height: 1200)] {
            let size = KatPanelSize.fit(in: host, maxWidth: 980)
            XCTAssertLessThan(size.width, host.width)
            XCTAssertLessThan(size.height, host.height)
            XCTAssertLessThanOrEqual(size.width, 980)
            XCTAssertGreaterThanOrEqual(size.width, 700)
        }
    }
    @MainActor func testHistoryAudioActionsUseOneRow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryRow-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistory(root: directory)
        let id = try await store.save(original: "Проверка компактной истории.", translation: "Checking compact history.", source: .russian, target: .english)!
        try await store.appendAudio(SpeechPCM(samples: [Float](repeating: 0, count: 22050), sampleRate: 22050), to: id)
        try await store.finishAudio(id)
        let history = HistoryModel(store: store)
        await history.refresh()
        let host = NSHostingView(rootView: HistoryView(history: history).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(".build/voice-playback-results/history-audio-row-mac.png"))
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US", "ru-RU"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        func box(_ words: String) throws -> CGRect {
            try XCTUnwrap(request.results?.first(where: { $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(words) == true })?.boundingBox)
        }
        let copy = try box(L10n.text("Скопировать перевод")), share = try box(L10n.text("Поделиться озвучкой"))
        XCTAssertEqual(copy.midY, share.midY, accuracy: 0.025, "Audio share and copy must use the same action row")
    }

    @MainActor func testHistorySharesAudioFileWithoutTextFallback() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("KatHistoryTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let store = TranslationHistory(root: fixture)
        let id = try await store.save(original: "Оригинал", translation: "Translation", source: .russian, target: .english)
        let entryID = try XCTUnwrap(id)
        let model = HistoryModel(store: store)
        let missing = await model.shareURL(entryID)
        XCTAssertNil(missing, "An entry without audio must never export its text instead")
        let step = 2.0 * Double.pi * 440.0 / 16000.0
        let samples: [Float] = (0..<16000).map { Float(sin(Double($0) * step) * 0.1) }
        try await store.appendAudio(SpeechPCM(samples: samples, sampleRate: 16000), to: entryID)
        try await store.finishAudio(entryID)
        let exported = await model.shareURL(entryID)
        let url = try XCTUnwrap(exported)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "m4a")
        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
        let entries = try await store.list()
        XCTAssertEqual(entries.first?.text?.translation, "Translation")
    }

    @MainActor func testQuitWaitsForCleanupAndCoalescesRepeatedRequests() async {
        let coordinator = MacTerminationCoordinator()
        var finish: CheckedContinuation<Void, Never>?
        var cleanups = 0, replies = 0
        let first = coordinator.request(cleanup: {
            cleanups += 1
            await withCheckedContinuation { finish = $0 }
        }, reply: { replies += 1 })
        XCTAssertEqual(first, .terminateLater)
        while finish == nil { await Task.yield() }
        XCTAssertEqual(replies, 0, "AppKit must not exit before resources have been freed")
        let repeated = coordinator.request(cleanup: { cleanups += 1 }, reply: { replies += 1 })
        XCTAssertEqual(repeated, .terminateLater)
        XCTAssertEqual(cleanups, 1)
        finish?.resume()
        for _ in 0..<100 where replies == 0 { await Task.yield() }
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(coordinator.request(cleanup: { cleanups += 1 }, reply: { replies += 1 }), .terminateNow)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(replies, 1)
    }
    @MainActor func testShutdownIsTerminalForPendingUIActions() async {
        let model = AppModel()
        await model.shutdown()
        await model.shutdown()
        await model.load()
        await model.loadAutomaticallyIfNeeded()
        await model.openCamera()
        await model.beginRecording()
        XCTAssertTrue(model.isShuttingDown)
        XCTAssertFalse(model.session.isReady)
        XCTAssertFalse(model.session.isBusy)
        XCTAssertFalse(model.usingCamera)
        XCTAssertFalse(model.recorder.isRecording)
    }

}

// Deterministic, silent UI fixture: no model inference, microphone or history writes.
private actor VoiceCardTestASR: ASRBackend {
    func load(modelURL: URL) async throws {}
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        ASRResult(text: "Ваш номер готов. Заселение в одиннадцать тридцать.", language: .russian, processingSeconds: 0.1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor VoiceCardTestMT: TranslationBackend {
    func load(modelURL: URL) async throws {}
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        TranslationResult(text: "Your room is ready. Check in at eleven thirty.", firstTokenSeconds: 0.1, processingSeconds: 0.2, fragments: 1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor VoiceCardTestSpeech: SpeechSynthesisBackend {
    func load(directory: URL, language: SpeechLanguage) async throws {}
    func synthesize(text: String) async throws -> SpeechPCM { SpeechPCM(samples: [0], sampleRate: 22050) }
    nonisolated func cancel() {}
    func unload() async {}
}
@MainActor private final class VoiceCardTestPlayer: SpeechPlayback {
    var continuation: CheckedContinuation<Void, Error>?
    func play(_ pcm: SpeechPCM) async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
    func play(file: URL) async throws { try await play(SpeechPCM(samples: [0], sampleRate: 22050)) }
    func stop() { let pending = continuation; continuation = nil; pending?.resume(throwing: CancellationError()) }
    func pause() {}
    func resume() {}
    func setRate(_ rate: Float) {}
}
