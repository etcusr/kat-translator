import SwiftUI
import OfflineCore

struct ModelPreparationView: View {
    let checking: Bool
    let status: String
    let canCancel: Bool
    let cancel: () -> Void
    var availableSize = CGSize(width: 420, height: 360)
    @ObservedObject private var verification = ModelVerificationStatus.shared

    private var panelWidth: CGFloat {
        if availableSize.width < 600 { return max(0, availableSize.width - 48) }
        return min(max(0, availableSize.width - 48), max(300, availableSize.width * 0.62), 900)
    }
    private var catWidth: CGFloat {
        min(160, max(72, min(panelWidth * 0.18, availableSize.height * 0.25)))
    }

    var body: some View {
        VStack(spacing: max(18, catWidth * 0.16)) {
            Text(checking ? L10n.text("Проверка моделей") : L10n.text("Подготовка моделей"))
                .font(.system(size: max(20, min(26, catWidth * 0.17)), weight: .semibold))
            CatPreparationProgressView(label: status, catWidth: catWidth, prominent: true)
                .accessibilityIdentifier("models.preparation")
            if checking && verification.active {
                Text(L10n.text("Проверка моделей обычно занимает около 30 секунд. При следующих запусках неизменённые файлы будут проверяться быстрее."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("models.firstVerificationHint")
            }
            if canCancel {
                Button(role: .cancel, action: cancel) {
                    Text(L10n.text("Отменить")).font(.system(size: 16))
                        .frame(minWidth: 88, minHeight: 30)
                }.buttonStyle(.bordered).controlSize(.large)
            }
        }.multilineTextAlignment(.center).frame(width: panelWidth).padding(24)
            .background(KatTheme.background)
    }
}
