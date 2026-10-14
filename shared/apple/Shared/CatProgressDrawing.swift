import SwiftUI
#if !CAT_WIDGET
import OfflineCore
#endif

/// Shared app/widget palette, derived from the neon app icon.
enum KatTheme {
    static let accent = Color(red: 0.79, green: 0.98, blue: 0.20)
    static let background = Color.black
    static let surface = Color(red: 0.105, green: 0.09, blue: 0.16)
    static let border = Color(red: 0.23, green: 0.20, blue: 0.31)
}
#if !CAT_WIDGET
extension View {
    @ViewBuilder func katScreenSurface() -> some View {
        #if os(macOS)
        self.katDesktopPanelSurface().tint(KatTheme.accent)
        #else
        self.scrollContentBackground(.hidden)
            .background(KatTheme.background)
            .toolbarBackground(KatTheme.background, for: .navigationBar)
            .tint(KatTheme.accent)
        #endif
    }
}
#endif

/// Small vector character: all gestures are decorative and never change byte progress.
enum CatCoat: CaseIterable {
    case tuxedo, ginger, silver, black, neon
}

struct CatProgressDrawing: View {
    var motion: CatProgressMotion
    var coat: CatCoat = .neon
    var playfulLeap = 0.0
    var crouch = 0.0
    var playfulRotation = 0.0
    var digging = 0.0
    var retching = 0.0
    var spill = 0.0
    var heave = 0.0
    var turning = 0.0
    var wallSpring = false
    var preserveMischief = false
    /// Real drawing space above the feet, so airborne paws are not clipped by Canvas.
    var headroom: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            context.translateBy(x: 0, y: headroom)
            context.scaleBy(x: size.width / 80, y: max(0, size.height - headroom) / 64)
            if coat == .neon {
                drawNeonCat(context: &context, motion: motion, playfulLeap: playfulLeap, crouch: crouch, rotation: playfulRotation, digging: digging, retching: retching, spill: spill, heave: heave, turning: turning, wallSpring: wallSpring, preserveMischief: preserveMischief)
                return
            }
            let fur: Color
            let shade: Color
            let patch: Color
            switch coat {
            case .tuxedo:
                fur = Color(red: 0.93, green: 0.91, blue: 0.83)
                shade = Color(red: 0.66, green: 0.65, blue: 0.59)
                patch = Color(red: 0.25, green: 0.28, blue: 0.28)
            case .ginger:
                fur = Color(red: 0.94, green: 0.64, blue: 0.30)
                shade = Color(red: 0.69, green: 0.41, blue: 0.19)
                patch = Color(red: 0.68, green: 0.33, blue: 0.12)
            case .silver:
                fur = Color(red: 0.70, green: 0.76, blue: 0.80)
                shade = Color(red: 0.43, green: 0.50, blue: 0.56)
                patch = Color(red: 0.29, green: 0.35, blue: 0.41)
            case .neon:
                fur = KatTheme.accent; shade = KatTheme.border; patch = KatTheme.surface
            case .black:
                fur = Color(red: 0.32, green: 0.34, blue: 0.38)
                shade = Color(red: 0.24, green: 0.26, blue: 0.30)
                patch = Color(red: 0.13, green: 0.15, blue: 0.18)
            }
            let detail = Color(red: 0.18, green: 0.21, blue: 0.21)
            let pink = Color(red: 0.76, green: 0.48, blue: 0.47)
            let s = motion.standing
            let t = motion.animationTime
            let cycle = t.truncatingRemainder(dividingBy: 18)
            // Smooth envelopes return to neutral before the next gesture.
            func gesture(_ start: Double, _ duration: Double) -> Double {
                guard cycle > start, cycle < start + duration else { return 0 }
                return pow(sin((cycle - start) / duration * .pi), 2) * pow(1 - s, 2)
            }
            let glance = gesture(2, 2.6)
            let stretch = gesture(6, 3)
            let paw = gesture(12, 2.8)
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.7)
            let blink = blinkPhase > 1.2 && blinkPhase < 1.58
                ? sin((blinkPhase - 1.2) / 0.38 * .pi) : 0
            let gait = motion.stride * s
            let bounce = motion.phase == .walking ? abs(gait) * (0.5 + motion.running * 1.8) : 0
            context.translateBy(x: 0, y: -bounce - motion.leap * 8)
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * s }
            func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            func stroke(_ points: [CGPoint], _ color: Color, _ width: Double) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func triangle(_ points: [CGPoint], _ color: Color) {
                var path = Path(); path.addLines(points); path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            // Curved tail swishes independently of the gait; tip remains inside the canvas.
            let swish = sin(t * 1.65) * (2.5 + 2 * (1 - s))
            var tail = Path()
            tail.move(to: CGPoint(x: mix(35, 25), y: mix(52, 39)))
            tail.addCurve(to: CGPoint(x: 12 + swish, y: mix(38, 20)),
                          control1: CGPoint(x: mix(13, 10), y: mix(60, 42)),
                          control2: CGPoint(x: 4 + swish, y: mix(55, 26)))
            context.stroke(tail, with: .color(patch), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            // Far legs are shaded, near paws have toes.
            stroke([CGPoint(x: mix(39, 29), y: 41), CGPoint(x: mix(38, 26) - gait * 5, y: 58)], shade, 5)
            stroke([CGPoint(x: 57, y: 40), CGPoint(x: 57 + gait * 5, y: 58)], shade, 4.5)
            ellipse(mix(30, 23), mix(28, 31) - stretch * 4, mix(27, 37), mix(30, 22) + stretch * 4, fur)
            ellipse(mix(41, 48), mix(20, 23) - stretch * 5, 17, 29, fur)
            // Dark saddle patch, chest and haunch give shape at small sizes.
            ellipse(mix(31, 25), mix(32, 32) - stretch * 3, mix(13, 21), mix(19, 12), patch)
            ellipse(mix(43, 50), mix(27, 31) - stretch * 3, 10, 18, Color.white.opacity(0.4))
            let backFoot = mix(42, 30) + gait * 5
            let frontFoot = 59 - gait * 5
            stroke([CGPoint(x: mix(45, 31), y: mix(45, 43)), CGPoint(x: backFoot, y: 58)], fur, 6)
            ellipse(backFoot - 3, 55, 9, 5, fur)
            let lift = paw * 13 + motion.leap * 5
            stroke([CGPoint(x: 56, y: 41 - stretch * 3), CGPoint(x: frontFoot - paw * 3, y: 56 - lift)], fur, 5)
            ellipse(frontFoot - 3 - paw * 3, 54 - lift, 9, 5, fur)
            for x in [backFoot, backFoot + 3] {
                stroke([CGPoint(x: x, y: 57), CGPoint(x: x, y: 59)], shade, 0.65)
            }
            for x in [frontFoot, frontFoot + 3] {
                stroke([CGPoint(x: x - paw * 3, y: 56 - lift), CGPoint(x: x - paw * 3, y: 58 - lift)], shade, 0.65)
            }
            // Short cat muzzle, two sharp ears and a mildly unimpressed expression.
            let hx = mix(45, 52) - glance * 3 - paw * 1.5
            let hy = mix(11, 20) - stretch * 7 + paw * 2
            triangle([CGPoint(x: hx, y: hy + 7), CGPoint(x: hx - 1, y: hy - 6), CGPoint(x: hx + 10, y: hy + 2)], patch)
            triangle([CGPoint(x: hx + 11, y: hy + 3), CGPoint(x: hx + 19, y: hy - 5), CGPoint(x: hx + 20, y: hy + 11)], fur)
            triangle([CGPoint(x: hx + 13, y: hy + 3), CGPoint(x: hx + 17.5, y: hy - 1.5), CGPoint(x: hx + 18, y: hy + 7)], pink)
            ellipse(hx - 1, hy, 23, 21, fur)
            ellipse(hx - 1, hy + 1, 12, 12, patch)
            ellipse(hx + 12, hy + 12, 10, 7, fur)
            let eyeHeight = max(0.65, 3.6 * (1 - blink))
            ellipse(hx + 4 + glance * 1.5, hy + 8, 5, eyeHeight, Color(red: 0.81, green: 0.84, blue: 0.28))
            ellipse(hx + 15 - glance, hy + 8, 4, eyeHeight, coat == .black ? Color(red: 0.81, green: 0.84, blue: 0.28) : detail)
            if blink < 0.8 {
                stroke([CGPoint(x: hx + 7 + glance, y: hy + 8.5), CGPoint(x: hx + 7 + glance, y: hy + eyeHeight + 7.5)], detail, 1)
            }
            // Flat upper lids make the expression dry rather than wide-eyed.
            stroke([CGPoint(x: hx + 3, y: hy + 8), CGPoint(x: hx + 9, y: hy + 8.5)], detail, 1)
            stroke([CGPoint(x: hx + 14, y: hy + 8.5), CGPoint(x: hx + 19, y: hy + 8)], detail, 1)
            triangle([CGPoint(x: hx + 17, y: hy + 13), CGPoint(x: hx + 21, y: hy + 13), CGPoint(x: hx + 19, y: hy + 15.5)], pink)
            stroke([CGPoint(x: hx + 19, y: hy + 15), CGPoint(x: hx + 19, y: hy + 17), CGPoint(x: hx + 16, y: hy + 18)], detail, 0.7)
            // Whiskers use a visible midtone on both dark and light surfaces.
            let whisker = scheme == .dark ? shade : detail
            stroke([CGPoint(x: hx + 10, y: hy + 15), CGPoint(x: hx + 2, y: hy + 13)], whisker, 0.7)
            stroke([CGPoint(x: hx + 10, y: hy + 17), CGPoint(x: hx + 2, y: hy + 19)], whisker, 0.7)
            stroke([CGPoint(x: hx + 21, y: hy + 15), CGPoint(x: min(78, hx + 27), y: hy + 13)], whisker, 0.7)
            stroke([CGPoint(x: hx + 21, y: hy + 17), CGPoint(x: min(78, hx + 27), y: hy + 19)], whisker, 0.7)
        }
    }
}

/// The logo's lime outline, pointed ears and tiny eyes, with articulated walking legs.
private func drawNeonCat(context: inout GraphicsContext, motion: CatProgressMotion, playfulLeap: Double, crouch: Double, rotation: Double, digging: Double, retching: Double, spill: Double, heave: Double, turning: Double, wallSpring: Bool, preserveMischief: Bool) {
    let s = max(motion.standing, digging > 0 || wallSpring ? 1 : max(retching * 0.95, playfulLeap)), t = motion.animationTime
    let natural = preserveMischief || digging > 0 ? 0 : s
    let tuck = preserveMischief ? 0 : max(playfulLeap, motion.leap) * natural
    let coil = wallSpring ? crouch : 0
    let twist = sin(.pi * turning)
    let gait = (digging > 0 || retching > 0 || crouch > 0 || wallSpring || tuck > 0.1) ? 0 : motion.stride * s
    func kick(_ phase: Double) -> Double { max(0, sin(digging * .pi * 8 + phase)) * (digging > 0 ? 1 : 0) }
    let bounce = motion.phase == .walking ? abs(gait) * (0.6 + motion.running) : 0
    context.translateBy(x: 0, y: -bounce - motion.leap * 8)
    context.translateBy(x: 40, y: 32 - playfulLeap * 30)
    context.rotate(by: .degrees(rotation))
    context.translateBy(x: -40, y: -32)
    context.translateBy(x: 0, y: 58)
    context.scaleBy(x: 1, y: 1 - (retching > 0 ? 0 : crouch) * 0.16)
    context.translateBy(x: 0, y: -58)
    func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * s }
    func line(_ points: [CGPoint], opacity: Double = 1, width: Double = 2.6) {
        var p = Path(); p.addLines(points)
        context.stroke(p, with: .color(KatTheme.accent.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    var tail = Path()
    tail.move(to: CGPoint(x: mix(34, 24), y: 44))
    tail.addCurve(to: CGPoint(x: 11 + sin(t * 1.6) * 2, y: mix(34, 24) + natural * 6 - tuck * 10), control1: CGPoint(x: 7, y: 61 - natural * 18 - tuck * 5), control2: CGPoint(x: 4, y: 40 - tuck * 7))
    context.stroke(tail, with: .color(KatTheme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    for (hip, foot, phase) in [(mix(34, 25), mix(32, 21), -1.0), (51.0, 50.0, 1.0)] {
        let sweep = phase < 0 ? kick(.pi) : 0
        if natural > 0 {
            let rear = phase < 0
            let fx = foot + gait * 6 * phase + (rear ? 9 : -7) * tuck + (rear ? 4 : -2) * coil
            let fy = 54 - tuck * 9 - max(0, gait * phase) * 3
            line([CGPoint(x: hip, y: 41), CGPoint(x: rear ? hip + 5 : hip - 2, y: 48 - tuck * 5), CGPoint(x: fx, y: fy), CGPoint(x: fx + 4, y: fy)], opacity: 0.65)
        } else {
        line([CGPoint(x: hip, y: 41), CGPoint(x: foot + gait * 6 * phase - sweep * 16, y: 54 - sweep * 5), CGPoint(x: foot + gait * 6 * phase + 4 - sweep * 16, y: 54 - sweep * 5)], opacity: 0.78)
        }
    }
    var body = Path(ellipseIn: CGRect(x: mix(29, 20), y: mix(29, 32), width: mix(29, 39), height: mix(29, 19)))
    if natural > 0.05 {
        // A haunch, lifted spine and narrower belly instead of a rigid oval.
        let arch = heave * 7 + tuck * 2
        let rear = mix(29, 20), shoulder = mix(54, 58)
        body = Path()
        body.move(to: CGPoint(x: rear, y: 42))
        body.addCurve(to: CGPoint(x: shoulder, y: 34 + heave * 2), control1: CGPoint(x: rear - 2, y: 27 - arch), control2: CGPoint(x: 43, y: 28 - arch))
        body.addQuadCurve(to: CGPoint(x: shoulder - 2, y: 49), control: CGPoint(x: shoulder + 5, y: 41))
        body.addCurve(to: CGPoint(x: rear, y: 42), control1: CGPoint(x: 42, y: 45 - heave * 3), control2: CGPoint(x: rear + 2, y: 57 - tuck * 4))
        body.closeSubpath()
    }
    context.fill(body, with: .color(KatTheme.surface))
    context.stroke(body, with: .color(KatTheme.accent), lineWidth: 2.6)
    for (hip, foot, phase) in [(mix(42, 30), mix(43, 31), 1.0), (56.0, 59.0, -1.0)] {
        let sweep = phase > 0 ? kick(0) : 0
        let lift = motion.leap * 4 + playfulLeap * 6 + max(0, gait * phase) * 2 + sweep * 7
        if natural > 0 {
            let rear = phase > 0
            let fx = foot + gait * 6 * phase + (rear ? 9 : -10) * tuck + (rear ? 4 : -3) * coil
            let fy = 58 - lift - tuck * 6
            line([CGPoint(x: hip, y: 43), CGPoint(x: rear ? hip + 5 : hip - 2, y: 50 - tuck * 5), CGPoint(x: fx, y: fy), CGPoint(x: fx + 5, y: fy)])
        } else {
        line([CGPoint(x: hip, y: 43), CGPoint(x: foot + gait * 6 * phase - sweep * 20, y: 58 - lift), CGPoint(x: foot + gait * 6 * phase + 5 - sweep * 20, y: 58 - lift)])
        }
    }
    if digging > 0 {
        // Small arcs of dust thrown backwards by alternating rear paws.
        for i in 0..<5 {
            let phase = (digging * 4 + Double(i) * 0.19).truncatingRemainder(dividingBy: 1)
            let x = 24 - phase * 22
            let y = 58 - sin(phase * .pi) * (7 + Double(i % 2) * 4)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.4, height: 1.8)), with: .color(KatTheme.accent.opacity((1 - phase) * 0.7)))
        }
    }
    let x = mix(44, 52) + retching * 3 + heave * 3 - twist * 16
    let y = mix(21, 26) + retching * 12 + heave * 3 - tuck * 2
    // Keep the logo face, but reduce its size in the side-on moving silhouette.
    let headScale = 1 - natural * 0.23
    context.translateBy(x: x + 4, y: y + 5)
    context.scaleBy(x: headScale, y: headScale)
    context.translateBy(x: -x - 4, y: -y - 5)
    var head = Path()
    head.move(to: CGPoint(x: x - 12, y: y - 2))
    head.addLine(to: CGPoint(x: x - 10, y: y - 17))
    head.addQuadCurve(to: CGPoint(x: x - 6, y: y - 17), control: CGPoint(x: x - 9, y: y - 20))
    head.addLine(to: CGPoint(x: x, y: y - 10))
    head.addLine(to: CGPoint(x: x + 8, y: y - 10))
    head.addLine(to: CGPoint(x: x + 13, y: y - 17))
    head.addQuadCurve(to: CGPoint(x: x + 17, y: y - 16), control: CGPoint(x: x + 16, y: y - 20))
    head.addLine(to: CGPoint(x: x + 21, y: y - 2))
    head.addQuadCurve(to: CGPoint(x: x + 12, y: y + 14), control: CGPoint(x: x + 25, y: y + 13))
    head.addLine(to: CGPoint(x: x - 2, y: y + 14))
    head.addQuadCurve(to: CGPoint(x: x - 12, y: y - 2), control: CGPoint(x: x - 17, y: y + 13))
    head.closeSubpath()
    context.fill(head, with: .color(KatTheme.surface))
    context.stroke(head, with: .color(KatTheme.accent), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
    let blink = t.truncatingRemainder(dividingBy: 4.6) > 4.35
    for eye in [x - 3, x + 10] {
        context.fill(Path(ellipseIn: CGRect(x: eye, y: y + 1, width: 3.8, height: blink || retching > 0.2 ? 1 : 5.5)), with: .color(KatTheme.accent))
    }
    if retching > 0.2 {
        context.stroke(Path(ellipseIn: CGRect(x: x + 4, y: y + 9, width: 5, height: 4)), with: .color(KatTheme.accent), lineWidth: 1.6)
        if spill > 0 {
            var stream = Path()
            stream.move(to: CGPoint(x: x + 7, y: y + 13))
            stream.addQuadCurve(to: CGPoint(x: 70, y: 62), control: CGPoint(x: 75, y: 49))
            context.stroke(stream, with: .color(KatTheme.accent.opacity(spill * 0.85)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    } else {
        line([CGPoint(x: x + 3, y: y + 9), CGPoint(x: x + 5, y: y + 10), CGPoint(x: x + 7, y: y + 9)], width: 1.6)
    }
}
