import SwiftUI
import OfflineCore

struct LanguagePairPicker: View {
    @Binding var selection: LanguageSelection
    let mode: TranslationInput
    let model: TranslationModel
    let app: AppModel
    @ObservedObject var packages: PackageDownloadCoordinator
    @State private var side: LanguageSide?
    var compact = false
    var showsDetails = true
    var singleLine = false
    var detectedSource: SpeechLanguage? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                languageMenu(source: true)
                Button { selection.reverse() } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.title3).padding(8)
                }.accessibilityLabel(L10n.text("Поменять языки местами"))
                languageMenu(source: false)
            }

        }
        .sheet(item: $side) { side in
            LanguageSearchSheet(selection: $selection, side: side, mode: mode, model: model, app: app, packages: packages)
        }
    }
    private func languageMenu(source: Bool) -> some View {
        let automatic = source && selection.automaticActive(in: mode)
        let detected = automatic ? detectedSource : nil
        return Button { side = source ? .source : .target } label: {
            VStack(alignment: .leading, spacing: 4) {
                if !singleLine { Text(source ? L10n.text("С языка") : L10n.text("На язык")).font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    if let detected { LanguageFlagBadge(languageID: detected.rawValue, compact: true) }
                    else if automatic { Image(systemName: "globe") }
                    else { LanguageFlagBadge(languageID: source ? selection.sourceID : selection.targetID, compact: true) }
                    Text(detected.map { TranslationLanguage.name($0.rawValue) + " · " + L10n.text("Авто") } ?? (automatic ? L10n.text("Авто") : TranslationLanguage.name(source ? selection.sourceID : selection.targetID))).font(AppPlatform.languageFont).lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(singleLine ? 8 : 12)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }.accessibilityLabel(source ? L10n.text("Выбрать исходный язык") : L10n.text("Выбрать язык перевода"))
            .accessibilityIdentifier(source ? "language.source" : "language.target")
            .accessibilityValue(detected.map { "auto:" + $0.rawValue } ?? (automatic ? "auto" : source ? selection.sourceID : selection.targetID))
    }
}

enum LanguageSide: String, Identifiable {
    case source, target
    var id: String { rawValue }
}

struct LanguageSearchSheet: View {
    @Binding var selection: LanguageSelection
    let side: LanguageSide
    let mode: TranslationInput
    let model: TranslationModel
    let app: AppModel
    @ObservedObject var packages: PackageDownloadCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var voiceLanguage: SpeechLanguage?
    @State private var showIconLegend = false
    #if os(macOS)
    @FocusState private var searchFocused: Bool
    #endif
    @AppStorage("favoriteTranslationLanguages") private var favoriteIDs = ""
    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }
    private func toggleFavorite(_ id: String) {
        var next = favorites
        if !next.insert(id).inserted { next.remove(id) }
        favoriteIDs = next.sorted().joined(separator: ",")
    }
    private var matches: [TranslationLanguage] {
        TranslationLanguage.selectable(for: model, automatic: packages.autoTranslation).filter { $0.matches(query) }.sorted {
            $0.displayName.compare($1.displayName, options: [.caseInsensitive], locale: L10n.locale) == .orderedAscending
        }
    }
    private var currentID: String { side == .source && selection.automaticActive(in: mode) ? "auto" : side == .source ? selection.sourceID : selection.targetID }
    private func resultingSource(_ language: TranslationLanguage) -> SpeechLanguage? {
        var pair = selection
        if side == .source { pair.selectSource(language.id) } else { pair.selectTarget(language.id) }
        return pair.runtimeSource
    }
    private func limitation(_ language: TranslationLanguage) -> String? {
        guard packages.autoTranslation || language.connected(to: model) else { return L10n.text("Не подключён для этой модели") }
        var candidate = selection
        if side == .source { candidate.selectSource(language.id) } else { candidate.selectTarget(language.id) }
        if !packages.autoTranslation && model == .opusBig && !candidate.automaticRequested && !candidate.connected(to: model) {
            return L10n.text("Для OPUS выберите английский на одной из сторон")
        }
        guard let source = resultingSource(language) else { return nil }
        if mode == .voice && !source.supportsRecognition { return L10n.text("Голосовой ввод недоступен · используйте текст") }
        if mode == .camera && !HybridOCR.supports(source) && source != .russian && source != .english { return L10n.text("Камера не распознаёт · используйте текст") }
        return nil
    }
    private var rowTitleFont: Font {
        #if os(macOS)
        .system(size: 18)
        #else
        .body
        #endif
    }
    private var symbolFont: Font {
        #if os(macOS)
        .system(size: 20)
        #else
        .body
        #endif
    }
    private func voiceSymbol(available: Bool = true, badge: String? = nil) -> some View {
        Image(systemName: available ? "speaker.wave.2.fill" : "speaker.slash")
            .font(symbolFont)
            .foregroundStyle(available ? Color.accentColor : Color.secondary)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary, AppPlatform.badgeBackground)
                        .offset(x: 5, y: 6)
                }
            }
    }
    private var iconLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill").font(symbolFont).foregroundStyle(.tint).frame(width: 32, height: 28)
                Text(L10n.text("Распознавание речи поддерживается"))
            }
            HStack(spacing: 12) {
                voiceSymbol().frame(width: 32, height: 28)
                Text(L10n.text("Озвучка готова"))
            }
            HStack(spacing: 12) {
                voiceSymbol(badge: "arrow.down.circle.fill").frame(width: 32, height: 28)
                Text(L10n.text("Озвучка доступна — голос нужно скачать"))
            }
            HStack(spacing: 12) {
                voiceSymbol(badge: "clock.fill").frame(width: 32, height: 28)
                Text(L10n.text("Проверяем скачанные файлы озвучки"))
            }
            HStack(spacing: 12) {
                voiceSymbol(available: false).frame(width: 32, height: 28)
                Text(L10n.text("Озвучка недоступна"))
            }
            Text(L10n.text("Нажмите на динамик, чтобы скачать голос и открыть его настройки."))
                .fixedSize(horizontal: false, vertical: true)
        }.font(AppPlatform.panelCaption).foregroundStyle(.secondary)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(macOS)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n.text("Название или код языка"), text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityIdentifier("language.search")
                }.font(.system(size: 16))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                    .onAppear { searchFocused = true }
                #endif
            List {
                if side == .source {
                    Section {
                        Button {
                            selection.automaticRequested = true
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "globe").font(symbolFont).frame(width: 34, height: 34)
                                Text(L10n.text("Авто")).font(rowTitleFont)
                                Spacer()
                                if selection.automaticActive(in: mode) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!selection.supportsAutomatic)
                            .accessibilityIdentifier("language.option.auto")
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.title + L10n.text(" · в текстовом режиме: \(TranslationLanguage.supported(by: model).count)")).font(AppPlatform.panelFootnote)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showIconLegend.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: showIconLegend ? "chevron.down" : "chevron.right").foregroundStyle(.tint)
                                Text(L10n.text("О значках и поддержке языков"))
                                Spacer(minLength: 0)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).font(AppPlatform.panelCaption)
                            .accessibilityIdentifier("language.legend")
                        if showIconLegend {
                            VStack(alignment: .leading, spacing: 8) {
                                iconLegend
                                Text(model == .qwen9B ? L10n.text("Расширенный список для пробного перевода. Качество новых языков на телефоне ещё не проверено, включая балийский.") : L10n.text("Новые языки подключены по списку модели. Качество перевода на телефоне ещё не проверено для каждой пары."))
                            }.font(AppPlatform.panelCaption).foregroundStyle(.secondary).padding(.top, 6)
                        }
                    }
                }
                if matches.isEmpty { Text(L10n.text("Язык не найден")).foregroundStyle(.secondary) }
                if !matches.filter({ favorites.contains($0.id) }).isEmpty {
                    Section(L10n.text("Избранные")) {
                        ForEach(matches.filter { favorites.contains($0.id) }) { language in languageRow(language) }
                    }
                }
                Section(L10n.text("Все языки")) {
                    ForEach(matches.filter { !favorites.contains($0.id) }) { language in languageRow(language) }
                }
            }
            .katScreenSurface()
            }
            .navigationTitle(side == .source ? L10n.text("Исходный язык") : L10n.text("Язык перевода"))
            .katInlineTitle()
            #if os(iOS)
            .searchable(text: $query, placement: AppPlatform.searchPlacement, prompt: L10n.text("Название или код языка"))
            #endif
            .sheet(isPresented: Binding(get: { voiceLanguage != nil }, set: { if !$0 { voiceLanguage = nil } })) {
                SettingsView(model: app, initialPage: .voices, initialVoiceLanguage: voiceLanguage)
            }
            .katDoneToolbar(identifier: "language.close") { dismiss() }
        }.katSheetClose(identifier: "language.close", maxWidth: 560, maxHeight: 640) { dismiss() }
    }
    private func voiceReady(_ language: TranslationLanguage) -> Bool {
        guard let runtime = SpeechLanguage(rawValue: language.id) else { return false }
        return packages.canSpeak(runtime)
    }
    private func capabilityDescription(_ language: TranslationLanguage) -> String {
        let speech = SpeechLanguage(rawValue: language.id)?.supportsRecognition == true ? (language.whisperCode == nil && packages.omnilingualDirectory == nil ? L10n.text("Распознавание речи: скачайте пакет Meta") : L10n.text("Распознавание речи поддерживается")) : L10n.text("Распознавание речи недоступно")
        let voice: String
        if !language.hasVoice { voice = L10n.text("Озвучка недоступна") }
        else if !packages.restored { voice = L10n.text("Озвучка поддерживается, проверяю голос") }
        else { voice = voiceReady(language) ? L10n.text("Озвучка готова") : L10n.text("Озвучка: скачайте выбранный голос") }
        return speech + ". " + voice
    }
    private func voiceDownloadFiles(_ language: TranslationLanguage) -> [ModelDownloader] {
        guard let runtime = SpeechLanguage(rawValue: language.id), runtime.hasVoice, !packages.canSpeak(runtime) else { return [] }
        return packages.components(packages.selectedVoice(runtime))
    }
    private func voiceButton(_ language: TranslationLanguage) -> some View {
        DownloadButton(items: voiceDownloadFiles(language), action: {
            guard let runtime = SpeechLanguage(rawValue: language.id), runtime.hasVoice else { return }
            if !packages.canSpeak(runtime) { packages.downloadVoice(packages.selectedVoice(runtime)) }
            voiceLanguage = runtime
        }) {
            voiceSymbol(available: language.hasVoice,
                        badge: language.hasVoice && (!packages.restored || !voiceReady(language)) ? (packages.restored ? "arrow.down.circle.fill" : "clock.fill") : nil)
                .frame(width: 44, height: 44)
        }.buttonStyle(.borderless).disabled(!language.hasVoice || !packages.restored)
            .accessibilityIdentifier("language.voice." + language.id)
            .accessibilityLabel((voiceReady(language) ? L10n.text("Голоса: ") : L10n.text("Скачать голос: ")) + language.displayName)
            .accessibilityValue(!language.hasVoice ? L10n.text("Недоступно") : !packages.restored ? L10n.text("Проверка") : voiceReady(language) ? L10n.text("Готов") : L10n.text("Скачать"))
    }
    private func languageSelectionButton(_ language: TranslationLanguage) -> some View {
        Button {
            if side == .source { selection.selectSource(language.id) } else { selection.selectTarget(language.id) }
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                #if os(macOS)
                LanguageFlagBadge(languageID: language.id).scaleEffect(1.15).frame(width: 34, height: 34)
                #else
                LanguageFlagBadge(languageID: language.id)
                #endif
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.displayName).font(rowTitleFont).foregroundStyle(.primary)
                    Text(L10n.language == "ru" ? language.englishName : language.nativeName).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    if let reason = limitation(language) {
                        Text(reason).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if currentID == language.id { Image(systemName: "checkmark").font(symbolFont).foregroundStyle(.tint) }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(limitation(language) != nil)
            .accessibilityIdentifier("language.option." + language.id)
            .accessibilityValue(capabilityDescription(language))
    }
    private func languageActions(_ language: TranslationLanguage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: SpeechLanguage(rawValue: language.id)?.supportsRecognition == true ? "mic.fill" : "mic.slash")
                .foregroundStyle(SpeechLanguage(rawValue: language.id)?.supportsRecognition == true ? Color.accentColor : Color.secondary)
                .font(symbolFont).frame(width: 28, height: 44)
                .accessibilityLabel(L10n.text("Речь"))
                .accessibilityIdentifier("language.speech." + language.id)
            voiceButton(language)
            Button { toggleFavorite(language.id) } label: {
                Image(systemName: favorites.contains(language.id) ? "star.fill" : "star")
                    .font(symbolFont)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.borderless)
                .accessibilityLabel((favorites.contains(language.id) ? L10n.text("Убрать из избранных: ") : L10n.text("В избранные: ")) + language.displayName)
                .accessibilityIdentifier("language.favorite." + language.id)
                .accessibilityValue(favorites.contains(language.id) ? L10n.text("Избранный") : L10n.text("Не избранный"))
        }
    }
    private func languageRow(_ language: TranslationLanguage) -> some View {
        LanguageRowLayout {
            languageSelectionButton(language)
            languageActions(language).fixedSize()
        }
    }
}

/// Keep the title readable; move actions below it when their intrinsic widths do not fit.
/// A single set of controls also keeps accessibility and hit testing unambiguous.
private struct LanguageRowLayout: Layout {
    private struct Placement {
        let width: CGFloat
        let title: CGSize
        let actions: CGSize
        let inline: Bool
        var height: CGFloat { inline ? max(title.height, actions.height) : title.height + actions.height }
    }

    private func placement(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Placement {
        let idealTitle = subviews[0].sizeThatFits(.unspecified)
        let actions = subviews[1].sizeThatFits(.unspecified)
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = max(0, proposedWidth ?? (idealTitle.width + actions.width + 8))
        let inline = idealTitle.width + actions.width + 8 <= width
        let titleWidth = inline ? max(0, width - actions.width - 8) : width
        let title = subviews[0].sizeThatFits(ProposedViewSize(width: titleWidth, height: nil))
        return Placement(width: width, title: title, actions: actions, inline: inline)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let value = placement(proposal, subviews)
        return CGSize(width: value.width, height: value.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let value = placement(ProposedViewSize(width: bounds.width, height: nil), subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + (value.inline ? (value.height - value.title.height) / 2 : 0)),
                          anchor: .topLeading, proposal: ProposedViewSize(value.title))
        subviews[1].place(at: CGPoint(x: bounds.maxX - value.actions.width,
                                    y: bounds.minY + (value.inline ? (value.height - value.actions.height) / 2 : value.title.height)),
                          anchor: .topLeading, proposal: ProposedViewSize(value.actions))
    }
}
