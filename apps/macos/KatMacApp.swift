import SwiftUI
import AppKit
import OfflineCore

@MainActor final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private let termination = MacTerminationCoordinator()
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        return termination.request(cleanup: { await model.shutdown() }) {
            sender.reply(toApplicationShouldTerminate: true)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        model?.integration.start()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
/// Coalesce repeated Quit events and reply only after asynchronous cleanup finishes.
@MainActor final class MacTerminationCoordinator {
    private var task: Task<Void, Never>?
    private var finished = false
    func request(cleanup: @escaping @MainActor () async -> Void,
                 reply: @escaping @MainActor () -> Void) -> NSApplication.TerminateReply {
        if finished { return .terminateNow }
        if task == nil {
            task = Task {
                await cleanup()
                finished = true
                reply()
            }
        }
        return .terminateLater
    }
}
@main struct KatMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var delegate
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    private static let menuBarIcon: NSImage = {
        let icon = Bundle.main.url(forResource: "KatIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage(size: NSSize(width: 20, height: 20))
        // MenuBarExtra uses the image's intrinsic size; keep the original logo colors.
        icon.size = NSSize(width: 20, height: 20)
        icon.isTemplate = false
        return icon
    }()
    init() {
        UserDefaults.standard.register(defaults: ["recordingMode": "toggle"])
        let appModel = AppModel()
        _model = StateObject(wrappedValue: appModel)
        delegate.model = appModel
    }
    var body: some Scene {
        Window("Kat translator", id: "main") {
            ConversationView(model: model)
                .frame(minWidth: 780, minHeight: 680)
                .katPanelHost()
                .background(MacTitleBarZoom().frame(width: 0, height: 0))
                .disabled(model.isShuttingDown)
                .overlay {
                    if model.isShuttingDown {
                        ProgressView(L10n.text("Завершаю работу…"))
                            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .onAppear {
                    model.integration.showMain = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                    model.integration.showSettings = { openSettings(); NSApp.activate(ignoringOtherApps: true) }
                }
                .task { await model.prepare() }
        }
        .defaultSize(width: 1040, height: 820)
        .windowIdealSize(.maximum)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L10n.text("Быстрый перевод")) {
                integrationCommands
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.text("Папка моделей")) { NSWorkspace.shared.open(ModelDownloader.root) }
            }
        }
        Settings { SettingsView(model: model).disabled(model.isShuttingDown || model.externalOperation).preferredColorScheme(.dark).tint(KatTheme.accent) }
        MenuBarExtra {
            integrationCommands
            Divider()
            Button(L10n.text("Главное окно")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button(L10n.text("Настройки")) { openSettings(); NSApp.activate(ignoringOtherApps: true) }
        } label: {
            Image(nsImage: Self.menuBarIcon)
                .renderingMode(.original)
                .accessibilityLabel("Kat translator")
        }
    }
    @ViewBuilder private var integrationCommands: some View {
        Button(L10n.text("Перевести выделенный текст")) { model.integration.selectedText() }
            .macShortcut(.selectedText)
        Button(L10n.text("Перевести область экрана")) { model.integration.captureRegion() }
            .macShortcut(.screenRegion)
        Button(L10n.text("Перевести текст из буфера")) { model.integration.clipboardText() }
            .macShortcut(.clipboardText)
    }
}

/// Handle only this window's empty title-bar area; toolbar controls keep their clicks.
private struct MacTitleBarZoom: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ nsView: Anchor, context: Context) {}
    static func dismantleNSView(_ nsView: Anchor, coordinator: ()) { nsView.stopMonitoring() }

    final class Anchor: NSView {
        private var monitor: Any?
        private var restoreFrame: NSRect?
        private var filledFrame: NSRect?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            // Intercept the second mouse-down before AppKit starts title-bar drag tracking.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      event.clickCount == 2, window.styleMask.contains(.resizable),
                      !window.styleMask.contains(.fullScreen), window.attachedSheet == nil,
                      let screen = window.screen else { return event }
                let point = event.locationInWindow
                guard point.y > window.contentLayoutRect.maxY, point.y <= window.frame.height else { return event }
                for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                    if let button = window.standardWindowButton(kind), button.convert(button.bounds, to: nil).contains(point) { return event }
                }
                for item in window.toolbar?.visibleItems ?? [] {
                    if let view = item.view, view.convert(view.bounds, to: nil).contains(point) { return event }
                }
                self.toggleFill(window, on: screen)
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func toggleFill(_ window: NSWindow, on screen: NSScreen) {
            let target = screen.visibleFrame
            if let restoreFrame, window.frame == filledFrame || window.frame == target {
                window.setFrame(window.constrainFrameRect(restoreFrame, to: screen), display: true)
                self.restoreFrame = nil
                filledFrame = nil
            } else {
                restoreFrame = window.frame
                filledFrame = target
                window.setFrame(target, display: true)
            }
        }
    }
}
