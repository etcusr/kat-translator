import SwiftUI
import AppKit
import OfflineCore

/// Use installed sharing extensions first; add local-app handoffs when a messenger
/// (notably Telegram Desktop) does not ship a macOS sharing extension.
struct MacShareButton: View {
    var text: String?
    var file: URL?
    var prepareFile: (() async throws -> URL?)? = nil
    var title = L10n.text("Поделиться")
    var showsTitle = false
    var iconSize = CGSize(width: 36, height: 44)
    @StateObject private var presenter = MacSharePresenter()
    @State private var preparing = false
    var body: some View {
        Button {
            guard !preparing else { return }
            if let prepareFile {
                let selectedText = text
                preparing = true
                Task {
                    defer { preparing = false }
                    do { presenter.show(text: selectedText, file: try await prepareFile()) }
                    catch { MacSharePresenter.report(error) }
                }
            } else { presenter.show(text: text, file: file) }
        } label: {
            if showsTitle { Label(title, systemImage: "square.and.arrow.up") }
            else { Image(systemName: "square.and.arrow.up").frame(width: iconSize.width, height: iconSize.height) }
        }.accessibilityLabel(title).disabled(preparing)
            .background(MacShareAnchor(view: presenter.anchor))
    }
}
private struct MacShareAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor enum MacMessenger: CaseIterable {
    case telegram, whatsapp
    var name: String { self == .telegram ? "Telegram" : "WhatsApp" }
    var scheme: String { self == .telegram ? "tg" : "whatsapp" }
    var applicationURL: URL? { NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://")!) }
    func textURL(_ text: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme; components.host = self == .telegram ? "msg_url" : "send"
        // Telegram accepts a text-only share in the URL field and opens its chat picker.
        components.queryItems = [URLQueryItem(name: self == .telegram ? "url" : "text", value: text)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}

@MainActor final class MacSharePresenter: NSObject, ObservableObject, NSSharingServicePickerDelegate {
    let anchor = NSView()
    private var picker: NSSharingServicePicker?
    private var text: String?
    private var file: URL?
    func show(text: String?, file: URL?) {
        self.text = text; self.file = file
        let items = Self.items(text: text, file: file)
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        self.picker = picker; picker.delegate = self
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }
    static func items(text: String?, file: URL?) -> [Any] {
        var result: [Any] = []
        if let text, !text.isEmpty { result.append(text) }
        if let file { result.append(file) }
        return result
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        var services = proposed
        for messenger in MacMessenger.allCases {
            guard let appURL = messenger.applicationURL,
                  !proposed.contains(where: { $0.title.localizedCaseInsensitiveContains(messenger.name) }) else { continue }
            let image = NSWorkspace.shared.icon(forFile: appURL.path)
            let service = NSSharingService(title: messenger.name, image: image, alternateImage: nil) { [weak self] in
                self?.handoff(to: messenger, application: appURL)
            }
            services.append(service)
        }
        return services
    }
    private func handoff(to messenger: MacMessenger, application: URL) {
        if let file {
            // Copy audio to a handoff-owned location: dismissing the share sheet removes
            // the History export, while the receiving app may still be reading the file.
            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("KatShare", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                // Bound these disposable handoffs to 24 hours, without touching user files.
                for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                    if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: url) }
                }
                let copy = root.appendingPathComponent(UUID().uuidString + "-" + file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: copy)
                var attachments = [copy]
                if let text, !text.isEmpty {
                    let textFile = root.appendingPathComponent(UUID().uuidString + "-Kat-text.txt")
                    try text.write(to: textFile, atomically: true, encoding: .utf8)
                    attachments.append(textFile)
                }
                if messenger == .telegram, Bundle(url: application)?.bundleIdentifier == "com.tdesktop.Telegram" {
                    open(attachments, application: application)
                } else {
                    // WhatsApp has no public file-sharing URL scheme. Its extension,
                    // if installed, is already offered above. Preserve a clipboard fallback.
                    let board = NSPasteboard.general; board.clearContents(); board.writeObjects(attachments.map { $0 as NSURL })
                    let alert = NSAlert()
                    alert.messageText = L10n.text("Файл готов к отправке")
                    alert.informativeText = text == nil ? L10n.text("В открывшемся мессенджере выберите чат и вставьте файл сочетанием ⌘V.") : L10n.text("Аудио и текстовый файл готовы. В открывшемся мессенджере выберите чат и вставьте их сочетанием ⌘V.")
                    alert.addButton(withTitle: L10n.text("Открыть") + " " + messenger.name)
                    alert.runModal()
                    NSWorkspace.shared.openApplication(at: application, configuration: .init()) { _, error in
                        if let error { Task { @MainActor in Self.report(error) } }
                    }
                }
            } catch { Self.report(error) }
        } else if let text, let url = messenger.textURL(text) {
            if text.utf16.count > 4000 || (messenger == .telegram && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")) {
                // Avoid truncating long translations or interpreting leading @ as a bot query.
                let board = NSPasteboard.general; board.clearContents(); board.setString(text, forType: .string)
                let alert = NSAlert()
                alert.messageText = L10n.text("Текст скопирован целиком")
                alert.informativeText = L10n.text("В открывшемся мессенджере выберите чат и вставьте текст сочетанием ⌘V.")
                alert.addButton(withTitle: L10n.text("Открыть") + " " + messenger.name)
                alert.runModal()
                NSWorkspace.shared.openApplication(at: application, configuration: .init()) { _, error in
                    if let error { Task { @MainActor in Self.report(error) } }
                }
            } else { open([url], application: application) }
        }
    }
    private func open(_ urls: [URL], application: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: .init()) { _, error in
            if let error { Task { @MainActor in Self.report(error) } }
        }
    }
    static func report(_ error: Error) {
        let alert = NSAlert(error: error); alert.runModal()
    }
}
