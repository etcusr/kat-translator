import SwiftUI
import OfflineCore

/// Manual choice of OPUS direction packages, as on Android: one row per language pair with a
/// checkbox per direction, the total to download and a single Download button. A group model
/// can serve several pairs, so the selection is a set of packages, not of pairs.
struct OpusDirectionsView: View {
    @ObservedObject var coordinator: PackageDownloadCoordinator
    @ObservedObject var directions: OpusDirectionPackages
    @State private var query = ""
    @State private var selected = Set<String>()

    struct Row: Identifiable {
        let a: String, b: String
        let forward: OpusDirectionPackage?, backward: OpusDirectionPackage?
        var id: String { a + "-" + b }
    }

    /// Russian pairs first, then English, then by language name.
    static func rows(_ directions: OpusDirectionPackages) -> [Row] {
        let languages = OpusDirectionRoutes.languages.filter { id in TranslationLanguage.catalog.contains { $0.id == id } }.sorted()
        func package(_ source: String, _ target: String) -> OpusDirectionPackage? {
            OpusDirectionRoutes.route(source, target).flatMap { directions.package($0.packageID) }
        }
        var rows = [Row]()
        for a in languages { for b in languages where a < b {
            let forward = package(a, b), backward = package(b, a)
            if forward != nil || backward != nil { rows.append(Row(a: a, b: b, forward: forward, backward: backward)) }
        } }
        func rank(_ row: Row) -> Int { [row.a, row.b].contains("ru") ? 0 : [row.a, row.b].contains("en") ? 1 : 2 }
        func other(_ row: Row) -> String { TranslationLanguage.name(["ru", "en"].contains(row.a) ? row.b : row.a) }
        return rows.sorted { (rank($0), other($0)) < (rank($1), other($1)) }
    }

    /// Selected packages that still need a download; manual-only packages are excluded.
    static func pending(_ selected: Set<String>, _ directions: OpusDirectionPackages) -> [OpusDirectionPackage] {
        directions.packages.filter { selected.contains($0.id) && $0.directory == nil && $0.route.hosted }
    }

    private var rows: [Row] {
        let all = Self.rows(directions)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { row in [row.a, row.b].contains { id in TranslationLanguage.catalog.first { $0.id == id }?.matches(q) == true } }
    }
    private var pending: [OpusDirectionPackage] { Self.pending(selected, directions) }
    private var busy: Bool { directions.packages.contains { $0.downloading || $0.installing } }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text(L10n.text("Отметьте нужные направления. Каждое направление — отдельная модель OPUS около 240 МБ; одна модель может обслуживать несколько пар."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                    TextField(L10n.text("Поиск языка"), text: $query)
                        .accessibilityIdentifier("opus.search")
                }
                ForEach(rows) { row in
                    Section(TranslationLanguage.name(row.a) + " ↔ " + TranslationLanguage.name(row.b)) {
                        direction(row.a, row.b, row.forward)
                        direction(row.b, row.a, row.backward)
                    }
                }
            }.accessibilityIdentifier("opus.directions")
            VStack(spacing: 8) {
                if busy { CatPreparationProgressView(label: L10n.text("Скачивание направлений…")) }
                Text(L10n.text("К загрузке: ") + L10n.bytes(pending.reduce(0) { $0 + $1.route.bytes })
                     + " · " + L10n.text("моделей: ") + String(pending.count))
                    .font(AppPlatform.panelBody).accessibilityIdentifier("opus.total")
                if selected.contains(where: { id in directions.package(id).map { !$0.route.hosted } ?? false }) {
                    Text(L10n.text("Часть направлений пока устанавливается только вручную."))
                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                }
                if let error = coordinator.errors["downloadSpace"] { Text(error).font(AppPlatform.panelCaption).foregroundStyle(.red) }
                DownloadButton(L10n.text("Скачать"), items: pending.flatMap(\.downloaders)) {
                    coordinator.startOpusDirections(pending); selected = []
                }.buttonStyle(.borderedProminent)
                    .disabled(!coordinator.restored || pending.isEmpty || busy)
                    .accessibilityIdentifier("opus.download")
            }.frame(maxWidth: .infinity).padding(16).background(AppPlatform.badgeBackground)
        }.navigationTitle(L10n.text("Направления OPUS"))
    }

    @ViewBuilder private func direction(_ from: String, _ to: String, _ package: OpusDirectionPackage?) -> some View {
        let label = TranslationLanguage.name(from) + " → " + TranslationLanguage.name(to)
        if let package {
            let done = package.directory != nil
            let checked = done || selected.contains(package.id)
            Button {
                if selected.contains(package.id) { selected.remove(package.id) } else { selected.insert(package.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? KatTheme.accent : .secondary)
                    Text(label).frame(maxWidth: .infinity, alignment: .leading)
                    Text(done ? L10n.text("установлено")
                         : package.downloading ? L10n.text("скачивается")
                         : !package.route.hosted ? L10n.text("вручную")
                         : L10n.bytes(package.route.bytes))
                        .font(AppPlatform.panelCaption).foregroundStyle(done ? KatTheme.accent : .secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(!coordinator.restored || done || package.downloading)
                .accessibilityIdentifier("opus.direction.\(from)-\(to)")
                .accessibilityValue(checked ? L10n.text("Выбрано") : L10n.text("Не выбрано"))
        } else {
            Text(label + " · " + L10n.text("нет модели")).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
        }
    }
}
