import OfflineCore
import SwiftUI

struct ResourceDiagnosticsView: View {
    @StateObject private var monitor = ResourceMonitor()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 20) {
                DiagnosticsCard(L10n.text("Процессор")) {
                    DiagnosticsValueRow(L10n.text("CPU приложения"), value: percent(monitor.appCPU))
                    DiagnosticsValueRow(L10n.text("CPU всего Mac"), value: percent(monitor.systemCPU))
                        .accessibilityIdentifier("diagnostics.cpu.system")
                    Text(L10n.text("100% — суммарное время всех ядер CPU. GPU и Neural Engine сюда не входят."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                }
                DiagnosticsCard(L10n.text("Память")) {
                    DiagnosticsValueRow(L10n.text("Память приложения (footprint)"), value: bytes(monitor.footprint))
                        .accessibilityIdentifier("diagnostics.memory")
                    DiagnosticsValueRow(L10n.text("В RAM, включая файлы"), value: bytes(monitor.residentMemory))
                    DiagnosticsValueRow(L10n.text("Пик footprint за время просмотра"), value: monitor.peakFootprint == 0 ? "—" : bytes(monitor.peakFootprint))
                    DiagnosticsValueRow(L10n.text("Всего RAM на Mac"), value: bytes(monitor.physicalMemory))
                    Text(L10n.text("Footprint — память, которую macOS учитывает за приложением. Резидентная RAM также включает страницы файлов моделей; часть из них может быть общей или освобождаться системой. Эти значения не складываются. macOS не предоставляет приложению фиксированный лимит RAM."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                }
                DiagnosticsCard(L10n.text("Хранилище")) {
                    DiagnosticsValueRow(L10n.text("Хранилище: свободно"), value: storageBytes(monitor.storageFree))
                        .accessibilityIdentifier("diagnostics.storage.free")
                    DiagnosticsValueRow(L10n.text("Хранилище: всего"), value: storageBytes(monitor.storageTotal))
                }
                Text(L10n.text("Данные обновляются раз в секунду, пока открыт этот раздел. Пик памяти относится только к текущему просмотру."))
                    .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
            }
            #else
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Ресурсы сейчас")).font(.headline)
                LabeledContent(L10n.text("CPU приложения"), value: percent(monitor.appCPU))
                LabeledContent(L10n.text("CPU всего iPhone"), value: percent(monitor.systemCPU))
                Text(L10n.text("100% — суммарное время всех ядер CPU. GPU и Neural Engine сюда не входят.")).font(.caption).foregroundStyle(.secondary)
                LabeledContent(L10n.text("RAM: учёт iOS"), value: bytes(monitor.footprint)).accessibilityIdentifier("diagnostics.memory")
                LabeledContent(L10n.text("В RAM, включая файлы"), value: bytes(monitor.residentMemory))
                LabeledContent(L10n.text("Пик учёта iOS в просмотре"), value: monitor.peakFootprint == 0 ? "—" : bytes(monitor.peakFootprint))
                LabeledContent(L10n.text("Ещё доступно приложению"), value: bytes(monitor.availableToApp))
                LabeledContent(L10n.text("Всего RAM в iPhone"), value: bytes(monitor.physicalMemory))
                Divider()
                LabeledContent(L10n.text("Хранилище: свободно"), value: storageBytes(monitor.storageFree)).accessibilityIdentifier("diagnostics.storage.free")
                LabeledContent(L10n.text("Хранилище: всего"), value: storageBytes(monitor.storageTotal))
                Text(L10n.text("Запас до лимита приложения — не свободная RAM телефона. Строка «В RAM, включая файлы» также учитывает загруженные файловые страницы весов; они могут быть общими или вытесняться системой. Эти два показателя RAM не складываются. Пик измеряется только при открытом экране, данные обновляются раз в секунду.")).font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline).monospacedDigit()
            #endif
        }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                monitor.reset()
                while !Task.isCancelled {
                    monitor.sample()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f %%", locale: L10n.locale, $0) } ?? L10n.text("Нет данных") }
    private func storageBytes(_ value: UInt64?) -> String { value.map { L10n.bytes(Int64(clamping: $0)) } ?? L10n.text("Нет данных") }
    private func bytes(_ value: UInt64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? L10n.text("Нет данных") }
}

/// Desktop rows keep labels and live values in stable, readable columns.
struct DiagnosticsValueRow: View {
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    var body: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title)
            Spacer(minLength: 12)
            Text(value).fontWeight(.medium).monospacedDigit()
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 16)).frame(minHeight: 26)
            .accessibilityElement(children: .ignore).accessibilityLabel(title + ": " + value)
        #else
        LabeledContent(title, value: value)
        #endif
    }
}

struct DiagnosticsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(AppPlatform.panelHeading)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
