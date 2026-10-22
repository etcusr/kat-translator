import SwiftUI
import OfflineCore
struct RecordButton: View {
    let mode: RecordingMode
    let enabled: Bool
    let recording: Bool
    let starting: Bool
    let processing: Bool
    var paused = false
    var speaking = false
    var diameter: CGFloat = 132
    var stopSpeech: () -> Void = {}
    let start: () -> Void
    let stop: () -> Void
    @State private var input = RecordingInputState(mode: .hold)
    private let accent = KatTheme.accent
    private var ringInset: CGFloat {
        #if os(macOS)
        max(4, diameter / 18)
        #else
        8
        #endif
    }
    private var face: some View {
        ZStack {
            Circle().fill(.black)
            Circle().fill(accent.opacity(0.12))
            Circle().stroke(accent, lineWidth: 2).padding(ringInset)
            if speaking { Image(systemName: "stop.fill").font(.system(size: diameter * 0.32)).foregroundStyle(accent) }
            else if processing || starting { ProgressView().scaleEffect(1.5) }
            else { Image(systemName: recording ? "stop.fill" : "mic.fill").font(.system(size: diameter * 0.32)).foregroundStyle(accent) }
        }.frame(width: diameter, height: diameter).contentShape(Circle())
    }
    private func handle(_ event: RecordingInputEvent) {
        RecordingStopTrace.mark("button.\(event).recording=\(recording).active=\(input.active)")
        // Recorder state is authoritative, even if SwiftUI recreated this view.
        if case .tap = event, recording || starting {
            _ = input.handle(.stopped)
            stop()
            return
        }
        if paused { input.latchForPause() }
        if !input.active && !enabled { return }
        switch input.handle(event) {
        case .start: start()
        case .stop, .cancel: stop()
        case nil: break
        }
    }
    var body: some View {
        Group {
            if speaking {
                Button(action: stopSpeech) { face }.buttonStyle(.plain)
            } else if mode == .toggle || input.latched {
                Button { handle(.tap) } label: { face }.buttonStyle(.plain)
            } else {
                face.gesture(DragGesture(minimumDistance: 0).onChanged { _ in handle(.press) }.onEnded { _ in handle(.release) })
                    .accessibilityElement().accessibilityAddTraits(.isButton)
                    .accessibilityAction { handle(.tap) }
            }
        }
        .accessibilityLabel(speaking ? L10n.text("Остановить озвучку") : recording || starting ? L10n.text("Завершить запись") : L10n.text("Начать запись"))
        .onChange(of: paused) { _, value in if value { input.latchForPause() } }
        .onAppear { if !recording && !starting { input = RecordingInputState(mode: mode) } }
        .onChange(of: mode) { _, value in input = RecordingInputState(mode: value) }
        .onChange(of: recording) { _, value in if !value && !starting { _ = input.handle(.stopped) } }
        .onChange(of: starting) { _, value in if !value && !recording { _ = input.handle(.stopped) } }
    }
}
