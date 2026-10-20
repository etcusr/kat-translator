import SwiftUI
import OfflineCore

/// Processing covers the workspace; playback leaves the completed text readable.
struct ProcessingOverlay: View {
    let status: String
    let progress: TranslationProgress?
    let cancel: () -> Void

    var body: some View {
        GeometryReader { area in
            ZStack {
                Color.black.opacity(0.78).ignoresSafeArea()
                    .contentShape(Rectangle())
                ScrollView {
                    VStack(spacing: 20) {
                        ProgressView().controlSize(.large).tint(KatTheme.accent)
                        Text(status)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("processing.status")
                        if let progress {
                            VStack(spacing: 8) {
                                HStack {
                                    Text(L10n.text("Перевожу часть \(min(progress.completedParts + 1, progress.totalParts)) из \(progress.totalParts)"))
                                    Spacer(minLength: 12)
                                    Text("\(Int(progress.fraction * 100)) %").monospacedDigit()
                                }.font(.callout)
                                ProgressView(value: progress.fraction).tint(KatTheme.accent)
                                    .accessibilityLabel(L10n.text("Прогресс перевода"))
                                    .accessibilityValue(L10n.text("\(Int(progress.fraction * 100)) процентов"))
                                    .accessibilityIdentifier("translation.progress")
                                Text(L10n.text("Обработано \(progress.completedCharacters) из \(progress.totalCharacters) символов оригинала"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.foregroundStyle(.white)
                        }
                        Button(L10n.text("Отменить"), role: .cancel, action: cancel)
                            .font(.system(size: 17, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(KatTheme.accent)
                            .padding(.horizontal, 28).frame(minHeight: 44)
                            .background(KatTheme.accent.opacity(0.12), in: Capsule())
                            .contentShape(Capsule())
                            .katCancelShortcut()
                            .accessibilityIdentifier("processing.cancel")
                    }.multilineTextAlignment(.center)
                        .frame(maxWidth: min(640, max(0, area.size.width - 48)))
                        .padding(24)
                        .frame(width: area.size.width)
                        .frame(minHeight: area.size.height)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }.accessibilityIdentifier("processing.overlay")
            .preferredColorScheme(.dark)
    }
}
