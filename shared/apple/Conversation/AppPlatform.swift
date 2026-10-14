import SwiftUI
import OfflineCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum AppPlatform {
    #if os(macOS)
    static var panelBackground: Color { Color(nsColor: .windowBackgroundColor) }
    #endif
    static var panelBody: Font {
        #if os(macOS)
        .system(size: 16)
        #else
        .subheadline
        #endif
    }
    static var panelHeading: Font {
        #if os(macOS)
        .system(size: 17, weight: .semibold)
        #else
        .headline
        #endif
    }
    static var panelCaption: Font {
        #if os(macOS)
        .system(size: 14)
        #else
        .caption
        #endif
    }
    static var panelFootnote: Font {
        #if os(macOS)
        .system(size: 14)
        #else
        .footnote
        #endif
    }
    static var clearControlSize: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }
    static var clearSymbol: String {
        #if os(macOS)
        "xmark"
        #else
        "xmark.circle.fill"
        #endif
    }
    static var expandOriginal: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
    static var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        return .toolbar
        #else
        return .navigationBarDrawer(displayMode: .always)
        #endif
    }
    static var trailingToolbar: ToolbarItemPlacement {
        #if os(macOS)
        return .confirmationAction
        #else
        return .topBarTrailing
        #endif
    }
    static var badgeBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    static var translationFont: Font {
        #if os(macOS)
        return .system(size: 22)
        #else
        return .body
        #endif
    }
    /// Original and translation on the Voice screen share one size.
    static var voiceTextFont: Font {
        #if os(macOS)
        return .system(size: 22)
        #else
        return .title3
        #endif
    }
    static var languageFont: Font {
        #if os(macOS)
        return .system(size: 18, weight: .semibold)
        #else
        return .subheadline.weight(.semibold)
        #endif
    }
    static var controlFont: Font {
        #if os(macOS)
        return .system(size: 18)
        #else
        return .subheadline
        #endif
    }
    static var secondaryFont: Font {
        #if os(macOS)
        return .system(size: 13)
        #else
        return .caption
        #endif
    }
    static var voiceResultMinimumHeight: CGFloat {
        #if os(macOS)
        return 150
        #else
        return 0
        #endif
    }
    static var editorHeight: CGFloat {
        #if os(macOS)
        return 280
        #else
        return 100
        #endif
    }
    static var isActive: Bool {
        #if os(macOS)
        return NSApp.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }
    static var imageModeTitle: String {
        #if os(macOS)
        return L10n.text("Изображение")
        #else
        return L10n.text("Камера")
        #endif
    }
}
struct KatPanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        #if os(macOS)
        Section { content() } header: { Text(title).font(AppPlatform.panelHeading).textCase(nil) }
        #else
        Section(title, content: content)
        #endif
    }
}
extension View {
    @ViewBuilder func katDesktopPanelSurface() -> some View {
        #if os(macOS)
        scrollContentBackground(.hidden).background(AppPlatform.panelBackground)
        #else
        self
        #endif
    }

    @ViewBuilder func katToolbarIcon() -> some View {
        #if os(macOS)
        font(.system(size: 21, weight: .medium)).foregroundStyle(KatTheme.accent).frame(width: 34, height: 32)
        #else
        self
        #endif
    }
    @ViewBuilder func katStableAction() -> some View {
        #if os(macOS)
        buttonStyle(.bordered).controlSize(.large).fixedSize(horizontal: true, vertical: false)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        #else
        self
        #endif
    }

    /// Align a native close button with the existing navigation header. macOS sheet
    /// confirmation toolbars create a separate footer, while primary actions can disappear.
    @ViewBuilder func katSheetClose(enabled: Bool = true, identifier: String = "sheet.close", maxWidth: CGFloat = 980, maxHeight: CGFloat = 960, action: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay(alignment: .topTrailing) {
            Button(action: action) { Image(systemName: "xmark") }
                .katCloseControl().disabled(!enabled)
                .accessibilityLabel(L10n.text("Закрыть"))
                .accessibilityIdentifier(identifier).help(L10n.text("Закрыть"))
                .katCancelShortcut()
                .padding(.top, 10).padding(.trailing, 16)
        }
        .modifier(KatAdaptivePanel(maxWidth: maxWidth, maxHeight: maxHeight))
        #else
        self
        #endif
    }
    @ViewBuilder func katCloseControl() -> some View {
        #if os(macOS)
        buttonStyle(.borderless).controlSize(.regular)
            .font(.system(size: 14, weight: .medium)).foregroundStyle(KatTheme.accent)
            .frame(width: 28, height: 28).contentShape(Rectangle())
        #else
        self
        #endif
    }
    @ViewBuilder func katPanelTypography() -> some View {
        #if os(macOS)
        font(.system(size: 16)).controlSize(.large).buttonStyle(.bordered)
            .environment(\.defaultMinListRowHeight, 36)
        #else
        self
        #endif
    }
    @ViewBuilder func katPanelHost() -> some View {
        #if os(macOS)
        modifier(KatPanelHost())
        #else
        self
        #endif
    }
    @ViewBuilder func katDoneToolbar(_ title: String = L10n.text("Готово"), enabled: Bool = true, identifier: String = "sheet.done", action: @escaping () -> Void) -> some View {
        #if os(iOS)
        toolbar { ToolbarItem(placement: AppPlatform.trailingToolbar) {
            Button(title, action: action).disabled(!enabled).accessibilityIdentifier(identifier)
        } }
        #else
        self
        #endif
    }
    @ViewBuilder func katRecordingPicker() -> some View {
        pickerStyle(.menu)
    }

    @ViewBuilder func katDesktopIconFont() -> some View {
        #if os(macOS)
        font(.system(size: 18)).buttonStyle(.plain).foregroundStyle(KatTheme.accent)
        #else
        self
        #endif
    }

    @ViewBuilder func katDesktopControls() -> some View {
        #if os(macOS)
        font(.system(size: 16)).controlSize(.large).buttonStyle(.bordered)
        #else
        self
        #endif
    }
    @ViewBuilder func katPrimaryAction() -> some View {
        #if os(macOS)
        buttonStyle(.borderedProminent).controlSize(.large)
        #else
        buttonStyle(.borderedProminent)
        #endif
    }
    @ViewBuilder func katModePicker() -> some View {
        #if os(macOS)
        labelsHidden().controlSize(.large).font(.system(size: 17, weight: .medium)).frame(width: 460)
        #else
        self
        #endif
    }

    @ViewBuilder func katSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(28)
        #else
        formStyle(.grouped)
        #endif
    }
    @ViewBuilder func katInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func katNumberInput() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
    @ViewBuilder func katFullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(macOS)
private struct KatPanelHostSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1040, height: 820)
}
extension EnvironmentValues {
    var katPanelHostSize: CGSize {
        get { self[KatPanelHostSizeKey.self] }
        set { self[KatPanelHostSizeKey.self] = newValue }
    }
}
private struct KatPanelHost: ViewModifier {
    @State private var size = KatPanelHostSizeKey.defaultValue
    func body(content: Content) -> some View {
        content.environment(\.katPanelHostSize, size)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }
}
/// Bounded by the presenting window, including when another panel opens this one.
struct KatPanelSize {
    static func fit(in host: CGSize, maxWidth: CGFloat, maxHeight: CGFloat = 960) -> CGSize {
        CGSize(width: min(maxWidth, max(360, host.width - 48)),
               height: min(maxHeight, max(240, host.height - 64)))
    }
}
private struct KatAdaptivePanel: ViewModifier {
    @Environment(\.katPanelHostSize) private var hostSize
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    func body(content: Content) -> some View {
        let size = KatPanelSize.fit(in: hostSize, maxWidth: maxWidth, maxHeight: maxHeight)
        content.frame(width: size.width, height: size.height)
            .environment(\.katPanelHostSize, size)
            .buttonStyle(.bordered).controlSize(.regular)
    }
}
#endif

extension View {
    @ViewBuilder func katCancelShortcut() -> some View {
        #if os(macOS)
        self.macShortcut(.cancel)
        #else
        self.keyboardShortcut(.cancelAction)
        #endif
    }
}
