import SwiftUI
import OfflineCore

/// Real byte progress below; the cat takes short walks between received updates.
struct CatDownloadProgressView: View {
    var value: Double
    var total: Double
    var isActive = true
    var label: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = CatProgressMotion(progress: 0, now: 0)
    // The long-lived animation task must read State, not its initial View snapshot.
    @State private var latestFraction = 0.0
    @State private var coat = CatCoat.neon
    private var fraction: Double {
        guard total.isFinite, total > 0, value.isFinite else { return 0 }
        return min(1, max(0, value / total))
    }
    private var animating: Bool { isActive && !reduceMotion && scenePhase == .active }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
            GeometryReader { geometry in
                CatProgressDrawing(motion: motion, coat: coat)
                    .frame(width: 68, height: 54)
                    .offset(x: max(0, geometry.size.width - 68) * motion.position)
            }.frame(height: 54).accessibilityHidden(true)
            CatProgressTrack(fraction: fraction)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label ?? L10n.text("Загрузка"))
                .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        }
        .onAppear {
            latestFraction = fraction
            motion = CatProgressMotion(progress: fraction, now: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: fraction) { _, _ in
            latestFraction = fraction
            if !animating { motion = CatProgressMotion(progress: fraction, now: ProcessInfo.processInfo.systemUptime) }
        }
        .task(id: animating) {
            guard animating else {
                motion = CatProgressMotion(progress: fraction, now: ProcessInfo.processInfo.systemUptime)
                return
            }
            while !Task.isCancelled {
                var next = motion
                next.advance(progress: latestFraction, active: true, now: ProcessInfo.processInfo.systemUptime)
                if next != motion { motion = next }
                do { try await Task.sleep(for: .milliseconds(motion.phase == .sitting ? 66 : 33)) }
                catch { return }
            }
        }
    }
}

/// Indeterminate preparation: the same cat walks back and forth, without claiming a percentage.
struct CatPreparationProgressView: View {
    var label: String
    var catWidth: CGFloat = 68
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = CatProgressMotion(progress: 0.08, now: 0)
    @State private var forward = true
    @State private var coat = CatCoat.neon
    @State private var play = CatLoadingPlay(now: ProcessInfo.processInfo.systemUptime)
    @State private var trackTravel: CGFloat = 1
    private var animating: Bool { !reduceMotion && scenePhase == .active }
    private var catHeight: CGFloat { catWidth * 0.8 }
    private var headroom: CGFloat { prominent ? catWidth * 0.60 : 0 }
    private var position: Double {
        let base = forward ? motion.position : 1 - motion.position
        return min(1, max(0, base + (forward ? play.travel - play.retreat : play.retreat - play.travel)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(prominent ? .system(size: max(15, min(19, catWidth * 0.12))) : .subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: prominent ? .center : .leading)
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    if prominent, let mark = play.markPosition {
                        CatGroundMark(kind: play.markKind, cover: play.markCover)
                            .frame(width: catWidth * 0.28, height: catWidth * 0.2)
                            .offset(x: max(0, geometry.size.width - catWidth) * mark + catWidth * (play.markKind == .pile ? (play.markFacingRight ? 0.16 : 0.56) : (play.markFacingRight ? 0.74 : -0.02)), y: -2)
                            .opacity(play.markOpacity)
                    }
                    CatProgressDrawing(motion: motion, coat: coat, playfulLeap: play.leap, crouch: play.crouch, playfulRotation: play.rotation, digging: play.digging, retching: play.retching, spill: play.spill, heave: play.heave, turning: play.turn, wallSpring: play.trick == .wallKick, preserveMischief: play.trick == .mischief, headroom: headroom)
                        .frame(width: catWidth, height: catHeight + headroom)
                        .scaleEffect(x: (forward ? 1 : -1) * (play.turn < 0.5 ? 1 : -1), y: 1)
                        .offset(x: max(0, geometry.size.width - catWidth) * position)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }.frame(height: catHeight + headroom).accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { max(1, $0.size.width - catWidth) } action: { trackTravel = $0 }
            // Preparation has no measurable byte total: a traveling segment is
            // deliberately different from a download's determinate fill.
            CatProgressTrack(position: reduceMotion ? 0.5 : position, thickness: max(4, min(8, catWidth / 20)))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .task(id: animating) {
            guard animating else {
                motion = CatProgressMotion(progress: motion.position, now: ProcessInfo.processInfo.systemUptime)
                play = CatLoadingPlay(now: ProcessInfo.processInfo.systemUptime)
                return
            }
            var began = ProcessInfo.processInfo.systemUptime
            motion = CatProgressMotion(progress: 0.08, now: began)
            play = CatLoadingPlay(now: began)
            var previousTick = began
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                var next = motion
                var nextPlay = play
                let wasAtWall = play.trick == .wallKick
                if play.isPosing { began += max(0, now - previousTick) }
                previousTick = now
                if prominent { nextPlay.advance(now: now, position: forward ? motion.position : 1 - motion.position, facingRight: forward, stepLength: Double(catWidth / trackTravel)) }
                if play.trick != nil && nextPlay.trick == nil && nextPlay.travel > 0 {
                    let landing = min(1, motion.position + nextPlay.travel)
                    next = CatProgressMotion(progress: landing, now: now)
                    began = now - (landing - 0.08) / 0.08
                    nextPlay.settleTravel()
                }
                if wasAtWall && nextPlay.trick == nil {
                    // Continue from the landing point, with no teleport when direction changes.
                    let landing = CatLoadingPlay.wallLanding(from: motion.position)
                    forward.toggle()
                    next = CatProgressMotion(progress: landing, now: now)
                    began = now - (landing - 0.08) / 0.08
                }
                // Animation phase only; never displayed as measured loading progress.
                let edge = prominent ? CatLoadingPlay.wallTakeoff(stepLength: Double(catWidth / trackTravel)) : 0.92
                if !nextPlay.isPosing { next.advance(progress: min(edge, 0.08 + (now - began) * 0.08), active: true, now: now) }
                if next.position >= edge && (prominent || next.phase == .sitting) {
                    if prominent {
                        nextPlay.beginWallKick(now: now)
                    } else {
                        forward.toggle()
                        began = now
                        next = CatProgressMotion(progress: 0.08, now: now)
                    }
                }
                if next != motion { motion = next }
                if nextPlay != play { play = nextPlay }
                do { try await Task.sleep(for: .milliseconds(motion.phase == .sitting && play.trick == nil ? 66 : 33)) }
                catch { return }
            }
        }
    }
}

/// A tiny cartoon keepsake, intentionally abstract and in the app's palette.
private struct CatKeepsake: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.12, y: 0.98))
        path.addCurve(to: CGPoint(x: 0.20, y: 0.60), control1: CGPoint(x: -0.10, y: 0.80), control2: CGPoint(x: 0.05, y: 0.65))
        path.addCurve(to: CGPoint(x: 0.38, y: 0.32), control1: CGPoint(x: 0.12, y: 0.40), control2: CGPoint(x: 0.28, y: 0.30))
        path.addQuadCurve(to: CGPoint(x: 0.56, y: 0), control: CGPoint(x: 0.58, y: 0.20))
        path.addQuadCurve(to: CGPoint(x: 0.72, y: 0.35), control: CGPoint(x: 0.91, y: 0.17))
        path.addQuadCurve(to: CGPoint(x: 0.82, y: 0.62), control: CGPoint(x: 0.94, y: 0.40))
        path.addQuadCurve(to: CGPoint(x: 0.91, y: 0.98), control: CGPoint(x: 1.12, y: 0.85))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

/// Ground props are outside the cat canvas so they remain fixed while it walks away.
struct CatGroundMark: View {
    var kind: CatLoadingPlay.Mark
    var cover: Double
    var body: some View {
        ZStack(alignment: .bottom) {
            if kind == .pile {
                CatKeepsake().fill(KatTheme.accent.opacity(0.8))
                    .scaleEffect(x: 1, y: 1 - cover * 0.85, anchor: .bottom)
                    .opacity(1 - cover)
                Capsule().fill(KatTheme.accent.opacity(0.35 * sin(.pi * cover)))
                    .frame(height: 3)
            } else {
                Ellipse().fill(KatTheme.accent.opacity(0.7)).frame(height: 5)
                Ellipse().fill(KatTheme.accent.opacity(0.5)).frame(width: 5, height: 3).offset(x: 9, y: -4)
            }
        }
    }
}

/// Draw the brand color ourselves: native macOS progress tracks can ignore tint.
private struct CatProgressTrack: View {
    var fraction: Double? = nil
    var position: Double = 0
    var thickness: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width)
            let fillWidth = fraction.map { width * min(1, max(0, $0)) } ?? width * 0.22
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(KatTheme.accent)
                    .frame(width: fillWidth)
                    .offset(x: fraction == nil ? (width - fillWidth) * min(1, max(0, position)) : 0)
            }
        }.frame(height: thickness)
    }
}
