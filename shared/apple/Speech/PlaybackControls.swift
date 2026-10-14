import SwiftUI
import OfflineCore

struct PlaybackSpeedButton: View {
    let speed: PlaybackSpeed
    let select: (PlaybackSpeed) -> Void
    let identifier: String
    @State private var choosing = false
    @State private var dragStart: Int?
    @State private var moved = false
    @State private var holdTask: Task<Void, Never>?
    @State private var frame = CGRect.zero
    @Environment(\.scenePhase) private var scenePhase
    private func beginChoice() {
        if dragStart == nil { dragStart = PlaybackSpeed.allCases.firstIndex(of: speed) ?? 0; moved = false }
        choosing = true
    }
    private func slide(_ translation: CGFloat) {
        beginChoice()
        guard abs(translation) >= 12 else { return }
        moved = true
        let index = min(3, max(0, (dragStart ?? 0) - Int((translation / 56).rounded())))
        let value = PlaybackSpeed.allCases[index]
        if value != speed { select(value) }
    }
    private var choices: some View {
        HStack(spacing: 4) {
            ForEach(Array(PlaybackSpeed.allCases.reversed()), id: \.self) { value in
                Button { select(value); choosing = false; dragStart = nil } label: {
                    Text(value.label).font(AppPlatform.controlFont.weight(.semibold))
                        .frame(width: 52, height: 44)
                        .background(speed == value ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("Скорость ") + value.label)
                    .accessibilityIdentifier(identifier + ".option." + String(value.rawValue))
            }
        }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))
            .shadow(radius: 8)
    }
    var body: some View {
        Button { choosing = false; select(speed.next) } label: {
            Text(speed.label).font(AppPlatform.controlFont.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 48, minHeight: 44).contentShape(Rectangle())
        }
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart == nil {
                    dragStart = PlaybackSpeed.allCases.firstIndex(of: speed) ?? 0
                    moved = false; choosing = false
                    holdTask?.cancel()
                    holdTask = Task { @MainActor in
                        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                        choosing = true
                    }
                }
                if choosing { slide(drag.translation.width) }
            }
            .onEnded { drag in
                holdTask?.cancel(); holdTask = nil
                if choosing {
                    slide(drag.translation.width)
                    choosing = !moved
                } else if abs(drag.translation.width) < 12 && abs(drag.translation.height) < 12 {
                    select(speed.next)
                }
                dragStart = nil; moved = false
            })
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .accessibilityLabel(L10n.text("Скорость озвучки")).accessibilityValue(speed.label)
        .accessibilityHint(L10n.text("Нажмите для следующей скорости. Удерживайте: влево — быстрее, вправо — медленнее."))
        .accessibilityAction(named: L10n.text("Выбрать скорость")) { choosing.toggle() }
        .accessibilityIdentifier(identifier)
        .overlay(alignment: .bottomTrailing) {
            if choosing {
                choices.fixedSize().offset(x: max(0, 248 - frame.maxX), y: -50)
            }
        }
        .zIndex(choosing ? 10 : 0)
        .onDisappear { holdTask?.cancel(); choosing = false; dragStart = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { choosing = false; dragStart = nil; holdTask?.cancel() } }
    }
}

struct PlaybackControls: View {
    let active: Bool
    let paused: Bool
    let disabled: Bool
    let speed: PlaybackSpeed
    let startLabel: String
    let identifier: String
    let start: () -> Void
    let stop: () -> Void
    let pauseResume: () -> Void
    let selectSpeed: (PlaybackSpeed) -> Void
    var unavailableHint: String? = nil
    var body: some View {
        HStack(spacing: 2) {
            PlaybackSpeedButton(speed: speed, select: selectSpeed, identifier: identifier + ".speed")
            if active {
                Button(action: pauseResume) {
                    Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                }.accessibilityLabel(paused ? L10n.text("Продолжить озвучку") : L10n.text("Приостановить озвучку"))
                    .accessibilityIdentifier(identifier + ".pauseResume")
            }
            Button(action: active ? stop : start) {
                Image(systemName: active ? "speaker.slash.fill" : "speaker.wave.2").frame(width: 44, height: 44)
            }.disabled(!active && disabled)
                .accessibilityLabel(active ? L10n.text("Остановить озвучку") : startLabel)
                .accessibilityIdentifier(identifier + ".startStop")
                .help(!active && disabled ? unavailableHint ?? startLabel : (active ? L10n.text("Остановить озвучку") : startLabel))
        }
    }
}
