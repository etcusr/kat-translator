import AppKit
import SwiftUI
import Translation

struct Sample: Codable {
    let id: String
    let source: String
    let target: String
    let kind: String
    let text: String
}

struct Measurement: Codable {
    let id: String
    let source: String
    let target: String
    let kind: String
    let text: String
    let engine: String
    let phase: String
    let pass: Int
    let seconds: Double
    let output: String
    let error: String?
    let availability: String
}

enum Backend: String, CaseIterable, Identifiable {
    case fast = "Apple · скорость"
    case quality = "Apple · качество"
    case small = "Kat · Index 2B"
    case large = "Kat · Index 9B MLX + MTP2"
    var id: String { rawValue }
    var apple: Bool { self == .fast || self == .quality }
    var strategy: TranslationSession.Strategy { self == .quality ? .highFidelity : .lowLatency }
    var key: String {
        switch self {
        case .fast: "apple-lowLatency"
        case .quality: "apple-highFidelity-requested"
        case .small: "index2b"
        case .large: "index9b"
        }
    }
}

@MainActor final class Lab: ObservableObject {
    @Published var backend: Backend = .fast
    @Published var source = "ru"
    @Published var text = "Подскажите, пожалуйста, как пройти к стойке регистрации?"
    @Published var output = ""
    @Published var status = "Отдельная тестовая сборка. Обычное приложение не изменено."
    @Published var busy = false
    @Published var configuration: TranslationSession.Configuration?
    private var task: Task<Void, Never>?
    private var session: TranslationSession?
    private var process: Process?
    var target: String { source == "ru" ? "en" : "ru" }
    let samples = (try? JSONDecoder().decode([Sample].self,
        from: Data(contentsOf: Bundle.main.url(forResource: "cases", withExtension: "json")!))) ?? []

    func prepare() {
        guard !busy, backend.apple else { return }
        busy = true
        status = "Подготовка языков Apple. При необходимости подтвердите системную загрузку."
        var next = TranslationSession.Configuration(source: .init(identifier: source),
            target: .init(identifier: target), preferredStrategy: backend.strategy)
        next.invalidate()
        configuration = next
    }

    func prepare(using value: TranslationSession) async {
        session = value
        do {
            try await value.prepareTranslation()
            status = "Языки подготовлены. Теперь можно переводить."
        } catch {
            status = "Подготовка: \(error.localizedDescription)"
        }
        session = nil
        busy = false
    }

    func cancel() {
        task?.cancel()
        session?.cancel()
        process?.terminate()
        // Keep controls locked until the active operation has actually finished.
        status = "Остановка…"
    }

    func translate() {
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard text.utf8.count <= 12000 else {
            status = "Для этого эксперимента используйте текст до 12 КБ."
            return
        }
        let selected = backend
        let sample = Sample(id: "manual", source: source, target: target, kind: "manual", text: text)
        busy = true
        output = ""
        status = selected.apple ? "Перевод…" : "Загрузка модели Kat и перевод…"
        task = Task {
            defer { busy = false; session = nil; process = nil; task = nil }
            do {
                if selected.apple {
                    let row = await apple(sample, backend: selected, pass: 0, phase: "manual")
                    output = row.output
                    status = row.error ?? String(format: "Перевод: %.3f с · %@", row.seconds, selected.rawValue)
                } else {
                    let result = try await kat(sample, backend: selected)
                    guard !Task.isCancelled else { throw CancellationError() }
                    output = result.output
                    status = String(format: "Перевод: %.3f с · загрузка модели: %.2f с", result.seconds, result.load_seconds)
                }
            } catch { status = "Перевод: \(error.localizedDescription)" }
        }
    }

    func apple(_ sample: Sample, backend: Backend, pass: Int, phase: String) async -> Measurement {
        let availability = await LanguageAvailability(preferredStrategy: backend.strategy)
            .status(from: .init(identifier: sample.source), to: .init(identifier: sample.target))
        let value = TranslationSession(installedSource: .init(identifier: sample.source),
            target: .init(identifier: sample.target), preferredStrategy: backend.strategy)
        session = value
        let start = ContinuousClock.now
        var result = "", failure: String?
        do {
            try Task.checkCancellation()
            result = try await value.translate(sample.text).targetText
        } catch { failure = String(describing: error) }
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        session = nil
        return Measurement(id: sample.id, source: sample.source, target: sample.target,
            kind: sample.kind, text: sample.text, engine: backend.key, phase: phase,
            pass: pass, seconds: seconds, output: result, error: failure,
            availability: String(describing: availability))
    }

    struct KatResult: Codable {
        let code: Int
        let output: String
        let seconds: Double
        let load_seconds: Double
    }

    func kat(_ sample: Sample, backend: Backend) async throws -> KatResult {
        let root = try String(contentsOf: Bundle.main.url(forResource: "workspace", withExtension: "txt")!, encoding: .utf8)
        let child = Process()
        let input = Pipe(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: root + "/.build/mac-index-mlx-mtp/venv/bin/python")
        child.arguments = [root + "/scripts/research/macos-translation-lab/kat_runner.py", backend.key]
        child.currentDirectoryURL = URL(fileURLWithPath: root)
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        process = child
        let bytes = try JSONEncoder().encode(sample)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            child.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "Kat Lab", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Движок завершился с кодом \(process.terminationStatus)."]))
                }
            }
            do {
                try child.run()
                input.fileHandleForWriting.write(bytes)
                try input.fileHandleForWriting.close()
            } catch {
                child.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let result = try JSONDecoder().decode(KatResult.self, from: data)
        guard result.code == 0 else {
            throw NSError(domain: "Kat Lab", code: result.code,
                userInfo: [NSLocalizedDescriptionKey: "Движок не завершил перевод (\(result.code))."])
        }
        return result
    }

    func benchmark(to path: String) {
        guard !busy else { return }
        busy = true
        task = Task {
            defer { busy = false; task = nil }
            var rows: [Measurement] = []
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            do {
                for backend in [Backend.fast, .quality] {
                    var failedDirections = Set<String>()
                    for pass in 0...3 {
                        for sample in samples {
                            try Task.checkCancellation()
                            let direction = sample.source + sample.target
                            if failedDirections.contains(direction) { continue }
                            self.backend = backend
                            source = sample.source
                            text = sample.text
                            status = "\(backend.rawValue) · \(sample.id) · проход \(pass + 1)/4"
                            let row = await apple(sample, backend: backend, pass: pass,
                                phase: pass == 0 ? "first_pass" : "warm")
                            rows.append(row)
                            output = row.output
                            try encoder.encode(rows).write(to: URL(fileURLWithPath: path), options: .atomic)
                            if row.error != nil { failedDirections.insert(direction) }
                        }
                    }
                }
                status = "Apple: проверка завершена. Результат: \(path)"
            } catch { status = "Проверка остановлена: \(error.localizedDescription)" }
        }
    }

    func probeKat(to path: String) {
        guard !busy, let sample = samples.first(where: { $0.id == "en-gender-context" }) else { return }
        busy = true
        task = Task {
            defer { busy = false; task = nil; process = nil }
            do {
                var results: [String: KatResult] = [:]
                for backend in [Backend.small, .large] {
                    try Task.checkCancellation()
                    self.backend = backend
                    source = sample.source
                    text = sample.text
                    status = "Проверка запуска из приложения: \(backend.rawValue)"
                    let result = try await kat(sample, backend: backend)
                    results[backend.key] = result
                    output = result.output
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(results).write(to: URL(fileURLWithPath: path), options: .atomic)
                status = "Оба движка Kat запущены из тестового приложения."
            } catch { status = "Проверка запуска: \(error.localizedDescription)" }
        }
    }
}

struct LabView: View {
    @StateObject private var lab = Lab()
    private let lime = Color(red: 0.76, green: 0.95, blue: 0.12)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(nsImage: NSImage(named: NSImage.applicationIconName)!).resizable().frame(width: 46, height: 46)
                VStack(alignment: .leading) {
                    Text("Kat Translation Lab").font(.title.bold()).foregroundStyle(lime)
                    Text("Локальный перевод · Mac · эксперимент").foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Picker("Движок", selection: $lab.backend) {
                    ForEach(Backend.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Направление", selection: $lab.source) {
                    Text("Русский → English").tag("ru")
                    Text("English → Русский").tag("en")
                }.frame(width: 270)
            }.disabled(lab.busy)
            Menu("Примеры") {
                ForEach(lab.samples, id: \.id) { sample in
                    Button(sample.id) { lab.source = sample.source; lab.text = sample.text }
                }
            }.disabled(lab.busy)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading) {
                    Text("Исходный текст").font(.headline)
                    TextEditor(text: $lab.text).font(.system(size: 17)).disabled(lab.busy)
                }
                VStack(alignment: .leading) {
                    Text("Перевод").font(.headline)
                    ScrollView { Text(lab.output.isEmpty ? "Здесь появится перевод" : lab.output)
                        .font(.system(size: 17)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                }
            }.frame(minHeight: 230)
            HStack {
                Button("Перевести") { lab.translate() }.buttonStyle(.borderedProminent).tint(lime)
                    .disabled(lab.busy || lab.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Подготовить языки Apple") { lab.prepare() }.disabled(lab.busy || !lab.backend.apple)
                if lab.busy { ProgressView().controlSize(.small); Button("Стоп") { lab.cancel() } }
                Spacer()
            }
            Text(lab.status).font(.callout).textSelection(.enabled)
            Text("Apple «качество» — предпочтение: система может использовать обычную модель. В этой лаборатории Kat загружает модель заново при каждом нажатии; это время показано отдельно. Ввод не сохраняется.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 850, minHeight: 530).preferredColorScheme(.dark)
        .translationTask(lab.configuration) { session in await lab.prepare(using: session) }
        .task {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--benchmark"), args.count > index + 1 {
                lab.benchmark(to: args[index + 1])
            } else if let index = args.firstIndex(of: "--probe-kat"), args.count > index + 1 {
                lab.probeKat(to: args[index + 1])
            }
        }
        .onDisappear { if lab.busy { lab.cancel() } }
    }
}

@main struct TranslationLabApp: App {
    var body: some Scene { Window("Kat Translation Lab", id: "main") { LabView() } }
}
