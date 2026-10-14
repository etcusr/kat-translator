import SwiftUI
import Combine
import Network
import OfflineCore

@MainActor final class DownloadAccessSettings: ObservableObject {
    static let shared = DownloadAccessSettings()
    private let defaults: UserDefaults
    @Published var allowCellular: Bool {
        didSet { defaults.set(allowCellular, forKey: "allowCellularDownloads") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; allowCellular = defaults.bool(forKey: "allowCellularDownloads")
    }
}

@MainActor final class DownloadNetworkMonitor: ObservableObject {
    static let shared = DownloadNetworkMonitor()
    @Published private(set) var state: DownloadNetworkState = .unknown
    private var monitor: NWPathMonitor?
    /// A fixed state is used only by in-process UI tests; normal apps observe NWPath.
    init(fixedState: DownloadNetworkState? = nil) {
        if let fixedState { state = fixedState; return }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let value: DownloadNetworkState
            if path.status != .satisfied { value = .offline }
            else if path.usesInterfaceType(.cellular) { value = .cellular }
            else if path.isExpensive { value = .expensive }
            else if path.usesInterfaceType(.wifi) { value = .wifi }
            else if path.usesInterfaceType(.wiredEthernet) { value = .wired }
            else { value = .expensive } // Unknown/VPN transport: do not assume free Wi-Fi.
            Task { @MainActor [weak self] in self?.state = value }
        }
        monitor.start(queue: DispatchQueue(label: "org.openoffline.download-network"))
    }
    deinit { monitor?.cancel() }
    func currentState() async -> DownloadNetworkState {
        for _ in 0..<20 where state == .unknown {
            if Task.isCancelled { return .unknown }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return state
    }
}

@MainActor final class DownloadRequest: ObservableObject {
    struct Prompt: Identifiable {
        let id = UUID()
        let maximumBytes: Int64
    }
    @Published private(set) var prompt: Prompt?
    @Published private(set) var checking = false
    let network: DownloadNetworkMonitor
    let settings: DownloadAccessSettings
    private var pendingAction: (() -> Void)?
    private var approvedAction: (() -> Void)?
    init(network: DownloadNetworkMonitor? = nil, settings: DownloadAccessSettings? = nil) {
        self.network = network ?? .shared; self.settings = settings ?? .shared
    }
    func request(_ items: [DownloadAccessItem], action: @escaping () -> Void) async {
        guard !checking, prompt == nil, approvedAction == nil else { return }
        let bytes = DownloadAccessItem.maximumDownloadBytes(items)
        guard bytes > 0 else { action(); return }
        checking = true
        let state = await network.currentState()
        checking = false
        guard !Task.isCancelled else { return }
        if !state.requiresConfirmation { action(); return }
        pendingAction = action; prompt = Prompt(maximumBytes: bytes)
    }
    func confirm(allowCellular: Bool) {
        guard prompt != nil, network.state.canDownload(allowCellular: allowCellular) else { return }
        settings.allowCellular = allowCellular
        approvedAction = pendingAction; pendingAction = nil; prompt = nil
    }
    func cancel() { prompt = nil; pendingAction = nil; approvedAction = nil }
    func didDismiss() {
        let action = approvedAction
        approvedAction = nil; pendingAction = nil; prompt = nil
        action?() // Start only after the sheet closes, including a navigation action.
    }
}

/// Own the sheet at the pressed button so it also works in nested Models/Voices/OCR sheets.
struct DownloadButton<Label: View>: View {
    let items: [ModelDownloader]
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @StateObject private var request = DownloadRequest()
    init(items: [ModelDownloader], action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.items = items; self.action = action; self.label = label
    }
    init(_ title: String, items: [ModelDownloader], action: @escaping () -> Void) where Label == Text {
        self.init(items: items, action: action) { Text(verbatim: title) }
    }
    var body: some View {
        Button {
            Task { await request.request(items.map(\.downloadAccessItem), action: action) }
        } label: { label() }
            .disabled(request.checking)
            .sheet(item: Binding(get: { request.prompt }, set: { if $0 == nil && request.prompt != nil { request.cancel() } }), onDismiss: request.didDismiss) { prompt in
                DownloadAccessPrompt(request: request, maximumBytes: prompt.maximumBytes)
            }
    }
}

struct DownloadAccessPrompt: View {
    @ObservedObject var request: DownloadRequest
    @ObservedObject private var network: DownloadNetworkMonitor
    @State private var allowCellular: Bool
    let maximumBytes: Int64
    init(request: DownloadRequest, maximumBytes: Int64) {
        self.request = request; self.network = request.network; self.maximumBytes = maximumBytes
        _allowCellular = State(initialValue: request.settings.allowCellular)
    }
    private var unavailable: Bool { network.state == .offline || network.state == .unknown }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Label(unavailable ? L10n.text("Нет подключения к интернету") : L10n.text("Загрузка без обычного Wi-Fi"), systemImage: "exclamationmark.triangle")
                .font(.title3.weight(.semibold)).foregroundStyle(KatTheme.accent)
            Text(L10n.text("Будет скачано до \(L10n.bytes(maximumBytes))."))
                .font(.headline).accessibilityIdentifier("download.confirm.bytes")
            Text(unavailable
                ? L10n.text("Подключитесь к Wi-Fi или включите мобильный интернет. Одного разрешения в приложении недостаточно, если сети нет.")
                : L10n.text("Подключение может использовать мобильный трафик. Чтобы скачать модели через него, разрешите мобильный интернет."))
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L10n.text("Разрешить мобильный интернет"), isOn: $allowCellular)
                .accessibilityIdentifier("download.confirm.cellular")
            Text(L10n.text("Установленные пакеты не скачиваются повторно. При продолжении прерванной загрузки может потребоваться скачать файл заново."))
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.text("Отмена"), action: request.cancel).katCancelShortcut()
                    .accessibilityIdentifier("download.confirm.cancel")
                Spacer()
                Button(L10n.text("Скачать")) { request.confirm(allowCellular: allowCellular) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!network.state.canDownload(allowCellular: allowCellular))
                    .accessibilityIdentifier("download.confirm.start")
            }
        }.padding(24)
        }.scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: 480).background(.background)
            .tint(KatTheme.accent).preferredColorScheme(.dark)
            #if os(macOS)
            .frame(width: 480, height: 360)
            #else
            .presentationDetents([.height(520), .large]).presentationDragIndicator(.visible)
            #endif
    }
}

extension ModelDownloader {
    var downloadAccessItem: DownloadAccessItem {
        DownloadAccessItem(id: model.id, bytes: model.byteCount, phase: state.phase, installed: installedURL != nil)
    }
}
