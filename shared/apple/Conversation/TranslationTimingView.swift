import SwiftUI
import OfflineCore

/// One wrapping line: visible only alongside its result when diagnostics is enabled.
struct TranslationTimingView: View {
    let timing: TranslationTiming
    let identifier: String
    private func seconds(_ value: Double) -> String {
        String(format: L10n.text("%.2f с"), locale: L10n.locale, value)
    }
    private var summary: String {
        if let recognition = timing.recognitionSeconds {
            return L10n.text("Распознавание: \(seconds(recognition)) · Перевод: \(seconds(timing.translationSeconds)) · Всего: \(seconds(timing.totalSeconds))")
        }
        return L10n.text("Перевод: \(seconds(timing.translationSeconds))")
    }
    var body: some View {
        Text(summary).font(AppPlatform.panelBody).monospacedDigit().foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
            .help(L10n.text("Время работы распознавания и перевода, без загрузки моделей и озвучки."))
    }
}
