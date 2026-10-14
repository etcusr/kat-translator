import SwiftUI
import OfflineCore

struct ExpandTextButton: View {
    let enabled: Bool
    let identifier: String
    var iconSize: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: iconSize, height: iconSize)
        }.disabled(!enabled).accessibilityLabel(L10n.text("Читать на весь экран"))
            .accessibilityIdentifier(identifier).help(L10n.text("Читать на весь экран"))
    }
}

/// Reading never starts or stops playback, and receives live text from the parent.
struct TextReadingView: View {
    let text: String
    let original: Bool
    let close: () -> Void
    private var readingFont: Font {
        #if os(macOS)
        .system(size: 24)
        #else
        .title2
        #endif
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(original ? L10n.text("Оригинал") : L10n.text("Перевод"))
                    .font(AppPlatform.panelHeading).frame(maxWidth: .infinity, alignment: .leading)
                CopyTextButton(text: text, title: original ? L10n.text("Скопировать оригинал") : L10n.text("Скопировать перевод"))
                Button(action: close) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44)
                }.accessibilityLabel(L10n.text("Свернуть"))
                    .accessibilityIdentifier("reader.close").katCancelShortcut()
            }.buttonStyle(.plain).foregroundStyle(KatTheme.accent)
                .padding(.horizontal, 20).padding(.vertical, 6)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(text).font(readingFont).lineSpacing(6).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("reader.text")
                    TextCharacterCount(text: text, identifier: "reader.count")
                }.frame(maxWidth: 960, alignment: .leading)
                    .padding(24).frame(maxWidth: .infinity, alignment: .top)
            }.accessibilityIdentifier("reader.scroll")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KatTheme.background).preferredColorScheme(.dark).tint(KatTheme.accent)
    }
}

extension View {
    /// iOS uses the entire screen; Mac uses all of the current window, including
    /// a window already placed in native fullscreen, without creating a small sheet.
    @ViewBuilder func katTextReader<Reader: View>(isPresented: Binding<Bool>, @ViewBuilder reader: @escaping () -> Reader) -> some View {
        #if os(macOS)
        accessibilityHidden(isPresented.wrappedValue).allowsHitTesting(!isPresented.wrappedValue)
            // Hidden controls must not receive shortcuts such as Image's Clear.
            .disabled(isPresented.wrappedValue)
            .overlay { if isPresented.wrappedValue { reader() } }
        #else
        fullScreenCover(isPresented: isPresented, content: reader)
        #endif
    }
}

struct TextCharacterCount: View {
    let text: String
    let identifier: String
    var body: some View {
        Text(L10n.text("Символов: \(text.count)"))
            .font(AppPlatform.panelCaption).foregroundStyle(.secondary).monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier(identifier)
    }
}
