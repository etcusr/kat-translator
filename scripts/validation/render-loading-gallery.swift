// Export the current app drawing and motion; compiled with -D CAT_WIDGET.
import SwiftUI
import AppKit

private struct Preview: View {
    let title: String
    let motion: CatProgressMotion
    let play: CatLoadingPlay
    let position: Double
    let facing: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("KAT TRANSLATOR").font(.system(size: 16, weight: .semibold)).tracking(3).foregroundStyle(KatTheme.accent)
            Text(title).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white).padding(.top, 16)
            Spacer(minLength: 0)
            ZStack(alignment: .bottomLeading) {
                if let mark = play.markPosition {
                    CatGroundMark(kind: play.markKind, cover: play.markCover).frame(width: 49.28, height: 35.2)
                        .offset(x: 624 * mark + 176 * (play.markKind == .pile ? (play.markFacingRight ? 0.16 : 0.56) : (play.markFacingRight ? 0.74 : -0.02)), y: -2).opacity(play.markOpacity)
                }
                CatProgressDrawing(motion: motion, playfulLeap: play.leap, crouch: play.crouch,
                                   playfulRotation: play.rotation, digging: play.digging, retching: play.retching, spill: play.spill, heave: play.heave, turning: play.turn, wallSpring: play.trick == .wallKick, preserveMischief: play.trick == .mischief, headroom: 105.6)
                    .frame(width: 176, height: 246.4)
                    .scaleEffect(x: facing * (play.turn < 0.5 ? 1 : -1), y: 1).offset(x: 624 * position)
            }.frame(width: 800, height: 246.4, alignment: .bottomLeading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(KatTheme.accent).frame(width: 176).offset(x: 624 * position)
            }.frame(height: 8).padding(.top, 4)
            Text("Загрузка и подготовка моделей").font(.system(size: 16)).foregroundStyle(.gray).padding(.top, 28)
        }.padding(.horizontal, 80).padding(.vertical, 44).frame(width: 960, height: 540)
            .background(.black).environment(\.colorScheme, .dark)
    }
}

@main struct Render {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let titles = ["hop": "Прыжок на месте", "doubleHop": "Двойной прыжок", "somersault": "Сальто", "mischief": "Кучка · закапывание задними лапами", "puke": "Лужица · перепрыгнул и пошёл дальше", "wallKick": "Отскок и разворот у края"]
        var scenarios: [(String, String, CatLoadingPlay.Trick?)] = [
            ("idle", "Ожидание · хвост и моргание", nil), ("walk", "Неторопливая ходьба", nil),
            ("run", "Бег при быстрой загрузке", nil), ("progress-jump", "Прыжок вслед за прогрессом", nil)
        ]
        scenarios += CatLoadingPlay.Trick.allCases.map { (String(describing: $0), titles[String(describing: $0)] ?? String(describing: $0), Optional($0)) }
        var catalog: [[String: Any]] = []
        for (id, title, trick) in scenarios {
            let frames = directory.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            var selected: CatLoadingPlay?
            if let trick, id != "wallKick" {
                // Use the real scheduler, not a duplicated probability table.
                for seed in UInt64(0)..<4096 {
                    var candidate = CatLoadingPlay(now: 0, seed: seed)
                    candidate.advance(now: 7, position: 0.5, facingRight: true, stepLength: 176.0 / 624)
                    if candidate.trick == trick { selected = candidate; break }
                }
                guard selected != nil else { fatalError("No scheduled example for \(id); update the gallery probe for this gesture") }
            }
            let initial = id == "wallKick" ? CatLoadingPlay.wallTakeoff(stepLength: 176.0 / 624) : (trick == nil && id != "idle" ? 0.08 : 0.5)
            var motion = CatProgressMotion(progress: initial, now: 0)
            var play = CatLoadingPlay(now: 10000, seed: 42)
            var began = false, completed = false
            var walkedOn: (time: Double, position: Double)?
            var landed: Double?
            var stoppedAt: Double?
            var count = 0
            for frame in 0..<600 {
                let time = Double(frame) / 30
                if trick == nil && time >= (id == "idle" ? 6 : id == "progress-jump" ? 4 : 5) { break }
                if let stoppedAt, time >= stoppedAt + (id == "wallKick" ? 2.7 : 1.2) { break }
                if trick != nil && !began && time >= 1 {
                    if id == "wallKick" { precondition(play.beginWallKick(now: time)) }
                    else { play = selected! }
                    began = true
                }
                if began && (!completed || play.markPosition != nil) {
                    let hadTrick = play.trick != nil
                    play.advance(now: time + (id == "wallKick" ? 0 : 6), position: motion.position, facingRight: true)
                    if hadTrick && play.trick == nil {
                        completed = true
                        if play.travel > 0 {
                            let landing = min(1, motion.position + play.travel)
                            motion = CatProgressMotion(progress: landing, now: time)
                            walkedOn = (time, landing)
                            play.settleTravel()
                        }
                        if id == "wallKick" { landed = time; motion = CatProgressMotion(progress: CatLoadingPlay.wallLanding(from: initial), now: time) }
                    }
                    if completed && play.markPosition == nil && stoppedAt == nil { stoppedAt = time }
                }
                var target = initial
                if id == "walk" { target = min(0.95, initial + max(0, time - 0.35) * 0.035) }
                if id == "run" { target = min(0.95, initial + max(0, time - 0.35) * 0.20) }
                if id == "progress-jump" { target = time < 1 ? initial : 0.90 }
                if let walkedOn { target = min(0.98, walkedOn.position + (time - walkedOn.time) * 0.07) }
                if let landed { target = min(0.95, CatLoadingPlay.wallLanding(from: initial) + (time - landed) * 0.08) }
                if !play.isPosing { motion.advance(progress: target, active: true, now: time) }
                let facing = landed == nil ? 1.0 : -1.0
                let base = facing > 0 ? motion.position : 1 - motion.position
                let position = min(1, max(0, base + (facing > 0 ? play.travel - play.retreat : play.retreat - play.travel)))
                try autoreleasepool {
                    let renderer = ImageRenderer(content: Preview(title: title, motion: motion, play: play, position: position, facing: facing))
                    renderer.scale = 1
                    guard let image = renderer.cgImage,
                          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("No image") }
                    try data.write(to: frames.appendingPathComponent(String(format: "%04d.png", frame)))
                }
                count += 1
            }
            if trick != nil { precondition(began && completed, "Gesture did not finish: \(id)") }
            catalog.append(["id": id, "title": title, "duration": Double(count) / 30])
            print("Rendered \(id)"); fflush(stdout)
        }
        try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("catalog.json"))
    }
}
