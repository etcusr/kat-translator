import AppKit
import SwiftUI

@MainActor final class LabModel: ObservableObject {
    @Published var source = ""
    @Published var glossary = ""
    @Published var automaticTerms = ""
    @Published var selected = "plain"
    @Published var outputs: [String: String] = [:]
    @Published var metrics: [String: String] = [:]
    @Published var status = "Отдельный эксперимент • Index 9B MLX + MTP2 • RU → EN"
    @Published var busy = false
    @Published var fraction = 0.0
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var request: [String: Any]?
    private var generation = UUID()
    private var probeStarted = false
    private var probeURL: URL?
    let root: String
    let fixture: URL
    init() {
        root = try! String(contentsOf: Bundle.main.url(forResource: "workspace", withExtension: "txt")!, encoding: .utf8)
        fixture = Bundle.main.url(forResource: "fixture", withExtension: "json")!
        if let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any] {
            source = (object["blocks"] as? [String] ?? []).joined(separator: "\n\n")
            if let terms = object["glossary"] as? [[String: Any]], let data = try? JSONSerialization.data(withJSONObject: terms, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { glossary = text }
        }
        if let url = Bundle.main.url(forResource: "comparison", withExtension: "json"), let report = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] {
            for row in report["results"] as? [[String: Any]] ?? [] { acceptResult(row) }
            status = "Сохранённые результаты сравнения. «Перевести» запускает новый опыт."
        }
    }
    func probeIfRequested() {
        let args = CommandLine.arguments
        guard !probeStarted, let index = args.firstIndex(of: "--probe"), index+1 < args.count else { return }
        probeStarted = true; probeURL = URL(fileURLWithPath: args[index+1]); selected = args.contains("--auto") ? "auto_terms" : "context_terms"
        translate()
    }
    private func acceptResult(_ row: [String: Any]) {
        guard let mode = row["mode"] as? String else { return }
        outputs[mode] = row["output"] as? String ?? ""
        if let automatic = row["glossary"] as? [String: Any], let terms = automatic["terms"] as? [[String: Any]] { showTerms(terms) }
        metrics[mode] = String(format: "Первая содержательная часть: %.2f с • Всё: %.2f с", row["first_body_part_seconds"] as? Double ?? 0, row["seconds"] as? Double ?? 0)
        if mode == "auto_terms" { metrics[mode, default: ""] += String(format: " • Сбор словаря: %.2f с (включён)", row["glossary_seconds"] as? Double ?? 0) }
    }
    private func showTerms(_ terms: [[String: Any]]) {
        automaticTerms = terms.map { "\($0["source"] as? String ?? "") → \($0["target"] as? String ?? "")" }.joined(separator: "\n")
    }
    func stop() {
        generation = UUID()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; request = nil; buffer.removeAll()
        busy = false; status = "Остановлено. Показанный текст может быть неполным."
    }
    func translate() {
        guard !busy else { return }
        do {
            var terms: [[String: Any]] = []
            if selected == "terms" || selected == "context_terms" {
                guard let parsed = try JSONSerialization.jsonObject(with: Data(glossary.utf8)) as? [[String: Any]] else { throw NSError(domain: "Словарь должен быть массивом JSON", code: 1) }
                terms = parsed
            }
            let blocks = source.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !blocks.isEmpty else { return }
            let payload: [String: Any] = ["mode": selected, "case": ["blocks": blocks, "glossary": terms]]
            busy = true; fraction = 0; outputs[selected] = ""; metrics[selected] = ""; status = "Перевожу…"
            if selected == "auto_terms" { automaticTerms = "" }
            if process?.isRunning == true { try send(payload); return }
            request = payload; status = "Загружаю модель…"
            let child = Process(), stdin = Pipe(), stdout = Pipe()
            let id = UUID(); generation = id; buffer.removeAll()
            child.executableURL = URL(fileURLWithPath: root + "/.build/mac-index-mlx-mtp/venv/bin/python")
            child.arguments = [root + "/scripts/research/mac-context-terms/runner.py", "--fixture", fixture.path, "--serve"]
            child.standardInput = stdin; child.standardOutput = stdout
            child.standardError = FileHandle.nullDevice
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.receive(data, id: id) }
            }
            child.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == id else { return }
                    self.process = nil; self.input = nil
                    if self.busy { self.busy = false; self.status = "Процесс перевода завершился. Нажмите Перевести для повторного запуска." }
                }
            }
            process = child; input = stdin; try child.run()
        } catch { busy = false; status = error.localizedDescription }
    }
    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        try input?.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ data: Data, id: UUID) {
        guard generation == id else { return }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            switch event["event"] as? String {
            case "ready":
                if let request { do { try send(request); self.request = nil; status = "Перевожу…" } catch { busy = false; status = error.localizedDescription } }
            case "glossary_start": status = "Собираю словарь из исходного текста…"
            case "glossary":
                if let terms = event["terms"] as? [[String: Any]] { showTerms(terms); status = "Найдено терминов: \(terms.count). Перевожу…" }
            case "partial":
                outputs[selected] = event["output"] as? String ?? ""
                fraction = (event["completed"] as? Double ?? 0) / max(1, event["total"] as? Double ?? 1)
                status = "Перевод не завершён • \(Int(fraction*100)) %"
            case "done":
                acceptResult(event); busy = false; fraction = 1; status = "Готово • Модель остаётся в памяти до 5 минут"
                if let probeURL {
                    do {
                        try JSONSerialization.data(withJSONObject: event, options: [.prettyPrinted, .sortedKeys]).write(to: probeURL)
                        NSApplication.shared.terminate(nil)
                    } catch { status = error.localizedDescription }
                }
            case "error": busy = false; status = event["error"] as? String ?? "Ошибка"
            default: break
            }
        }
    }
}

struct LabView: View {
    @ObservedObject var model: LabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kat · Context Lab").font(.title.bold())
                Spacer()
                Picker("Режим", selection: $model.selected) {
                    Text("Текущий").tag("plain")
                    Text("Контекст").tag("context")
                    Text("Контекст + термины").tag("context_terms")
                    Text("Ручной словарь").tag("terms")
                    Text("Автословарь").tag("auto_terms")
                }.pickerStyle(.segmented).frame(width: 800).disabled(model.busy)
            }
            Text("Исследовательская сборка. Автословарь создаётся из исходника заново; его подготовка включена во время. Ошибки терминов возможны.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Перевести") { model.translate() }.disabled(model.busy)
                Button("Отмена / выгрузить") { model.stop() }
                Text(model.status).font(.caption)
                Spacer()
            }
            ProgressView(value: model.fraction).tint(Color(red: 0.76, green: 0.96, blue: 0.06))
            Text(model.metrics[model.selected] ?? "").font(.caption.monospacedDigit())
            HSplitView {
                VStack(alignment: .leading) { Text("Исходник • пустая строка разделяет OCR-блоки").font(.caption); TextEditor(text: $model.source).disabled(model.busy) }
                VStack(alignment: .leading) { Text("Перевод • сравните режимы переключателем").font(.caption); TextEditor(text: Binding(get: {model.outputs[model.selected] ?? ""}, set: {_ in})) }
            }
            if model.selected == "auto_terms" {
                DisclosureGroup("Автоматически найденные термины") { ScrollView { Text(model.automaticTerms.isEmpty ? "Словарь появится после анализа текста" : model.automaticTerms).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 150) }
            } else if model.selected == "terms" || model.selected == "context_terms" {
                DisclosureGroup("Ручной словарь — JSON, редактируемый") { TextEditor(text: $model.glossary).font(.system(size: 12, design: .monospaced)).frame(height: 170).disabled(model.busy) }
            }
        }.padding(18).frame(minWidth: 1200, minHeight: 650).preferredColorScheme(.dark)
        .onAppear { model.probeIfRequested() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
    }
}
@main struct ContextLab: App {
    @StateObject private var model = LabModel()
    var body: some Scene { WindowGroup { LabView(model: model) }.defaultSize(width: 1400, height: 850) }
}
