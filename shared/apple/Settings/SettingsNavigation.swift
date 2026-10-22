import SwiftUI
import OfflineCore

/// One hierarchy for Settings, package hints, camera options and download activities.
enum SettingsPage: String, Hashable {
    case models, translationModels, recognitionModels, ocr, voices, downloads
    case recording, interface, memory, history, experimental, about
    #if os(macOS)
    case shortcuts
    #endif

    var title: String {
        switch self {
        case .models: L10n.text("Модели и голоса")
        case .translationModels: L10n.text("Перевод")
        case .recognitionModels: L10n.text("Распознавание речи")
        case .ocr: L10n.text("Распознавание текста")
        case .voices: L10n.text("Голоса и образцы")
        case .downloads: L10n.text("Загрузки")
        case .recording: L10n.text("Запись речи")
        case .interface: L10n.text("Интерфейс")
        case .memory: L10n.text("Память")
        case .history: L10n.text("История переводов")
        case .experimental: L10n.text("Экспериментально")
        case .about: L10n.text("О приложении")
        #if os(macOS)
        case .shortcuts: L10n.text("Горячие клавиши")
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .models: "square.stack.3d.up.fill"
        case .translationModels: "character.bubble.fill"
        case .recognitionModels: "waveform"
        case .ocr: "text.viewfinder"
        case .voices: "speaker.wave.2.fill"
        case .downloads: "arrow.down.circle.fill"
        case .recording: "mic.fill"
        case .interface: "paintpalette.fill"
        case .memory: "internaldrive.fill"
        case .history: "clock.fill"
        case .experimental: "flask.fill"
        case .about: "info.circle.fill"
        #if os(macOS)
        case .shortcuts: "keyboard.fill"
        #endif
        }
    }

    var color: Color {
        switch self {
        case .models, .translationModels, .downloads: .blue
        case .recognitionModels, .recording: .red
        case .voices, .interface: .purple
        case .ocr, .memory: .teal
        case .history, .experimental: .orange
        default: .gray
        }
    }

    static func initialPath(page: SettingsPage?, focus: PackageShortcut?) -> [SettingsPage] {
        let destination: SettingsPage?
        switch focus {
        case .translation: destination = .translationModels
        case .recognition: destination = .recognitionModels
        case .voice: destination = .voices
        case .ocr: destination = .ocr
        case nil: destination = page
        }
        guard let destination else { return [] }
        switch destination {
        case .translationModels, .recognitionModels, .ocr, .voices, .downloads:
            return [.models, destination]
        default: return [destination]
        }
    }
}

struct SettingsCategoryLabel: View {
    let title: String
    let symbol: String
    let color: Color
    init(page: SettingsPage) { title = page.title; symbol = page.symbol; color = page.color }
    init(title: String, symbol: String, color: Color) { self.title = title; self.symbol = symbol; self.color = color }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white).frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

extension View {
    @ViewBuilder func katSettingsList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped).katSettingsBackground()
        #else
        self.listStyle(.inset).katSettingsBackground()
        #endif
    }
    func katSettingsBackground() -> some View {
        self.scrollContentBackground(.hidden)
            #if os(iOS)
            .background(Color(uiColor: .systemGroupedBackground))
            #else
            .background(Color(nsColor: .windowBackgroundColor))
            #endif
    }
}
