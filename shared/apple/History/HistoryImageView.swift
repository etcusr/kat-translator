import SwiftUI
import ImageIO
import OfflineCore

struct HistoryImageThumbnail: View {
    let id: UUID
    let store: TranslationHistory
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
        }.frame(maxWidth: 360, minHeight: 100, maxHeight: 180)
            .task(id: id) {
                guard let data = try? await store.imageData(id), !Task.isCancelled else { return }
                image = await Task.detached(priority: .utility) { downsampleHistoryImage(data, size: 720) }.value
            }
    }
}

struct HistoryImageReader: View {
    let url: URL
    @State private var sharedImage: SharedAudio?
    @State private var error: String?
    let close: () -> Void
    @State private var image: CGImage?
    @State private var zoom: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("Изображение с переводом")).font(AppPlatform.panelHeading)
                Spacer(minLength: 4)
                Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44) }
                    .disabled(zoom <= 1).accessibilityLabel(L10n.text("Уменьшить"))
                Button { zoom = min(4, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44) }
                    .disabled(zoom >= 4).accessibilityLabel(L10n.text("Увеличить"))
                Button {
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Translated-image-" + UUID().uuidString + "." + url.pathExtension)
                    do { try FileManager.default.copyItem(at: url, to: copy); sharedImage = SharedAudio(url: copy) }
                    catch { self.error = error.localizedDescription }
                } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("Поделиться изображением"))
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("Закрыть изображение")).accessibilityIdentifier("history.image.close")
                    .katCancelShortcut()
            }.buttonStyle(.plain).foregroundStyle(KatTheme.accent).padding(.horizontal, 12)
            if let error { Text(error).foregroundStyle(.orange) }
            GeometryReader { area in
                ScrollView([.horizontal, .vertical]) {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                            .frame(width: area.size.width * zoom, height: area.size.height * zoom)
                            .accessibilityIdentifier("history.image.fullscreen")
                    } else { ProgressView().frame(width: area.size.width, height: area.size.height) }
                }
            }
        }.background(KatTheme.background).preferredColorScheme(.dark).tint(KatTheme.accent)
            .sheet(item: Binding(get: { sharedImage }, set: { if $0 == nil { clearShare() } })) { item in
                AudioShareSheet(item: item, done: clearShare)
            }
            .task(id: url) {
                image = await Task.detached(priority: .userInitiated) {
                    guard let data = try? Data(contentsOf: url) else { return nil as CGImage? }
                    return downsampleHistoryImage(data, size: 3072)
                }.value
            }
    }
    private func clearShare() {
        if let sharedImage { try? FileManager.default.removeItem(at: sharedImage.url) }
        sharedImage = nil
    }
}

private func downsampleHistoryImage(_ data: Data, size: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary)
}
