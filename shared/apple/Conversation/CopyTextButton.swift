import OfflineCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import UniformTypeIdentifiers

enum AppClipboard {
    @MainActor static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: false])
        #endif
    }
}

struct CopyTextButton: View {
    let text: String
    let title: String
    var showsTitle = false
    var iconSize: CGFloat = 44
    @State private var copied = false
    @State private var copyID = UUID()

    var body: some View {
        Button {
            // Rewrite even identical text; the checkmark is feedback, never a one-shot guard.
            AppClipboard.copy(text)
            copied = true
            copyID = UUID()
        } label: {
            if showsTitle {
                Label(copied ? L10n.text("Скопировано") : title, systemImage: copied ? "checkmark" : "doc.on.doc")
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: iconSize, height: iconSize)
            }
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(copied ? L10n.text("Скопировано") : "")
        .task(id: copyID) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.2)); copied = false }
            catch { } // A new tap restarts the feedback interval.
        }
        .onChange(of: text) { _, _ in copied = false }
    }
}
