import SwiftUI
import AppKit
import OfflineCore

// Lock Screen Live Activities are iOS-only. Desktop downloads use the model window
// and the shared completion notification service.
@MainActor enum DownloadLiveActivity {
    static func started(_ id: String) {}
    static func changed() {}
    static func flush() async {}
}

struct AudioShareSheet: View {
    let item: SharedAudio
    let done: () -> Void
    @State private var error: String?
    var body: some View {
        NavigationStack {
        VStack(spacing: 20) {
            Text(item.url.lastPathComponent).font(.headline)
            MacShareButton(file: item.url, showsTitle: true)
            Button(L10n.text("Сохранить файл…")) {
                let panel = NSSavePanel(); panel.nameFieldStringValue = item.url.lastPathComponent
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do { try Data(contentsOf: item.url).write(to: url, options: .atomic); done() }
                catch { self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(L10n.text("Поделиться"))
            .katPanelTypography()
        }.katSheetClose(identifier: "share.close", maxWidth: 520, maxHeight: 240, action: done)
    }
}
