// Compile alongside CatProgressMotion.swift and CatProgressDrawing from shared/apple/Shared/CatProgressDrawing.swift.
// Produces frames from the same drawing/motion used by the download UI.
import SwiftUI
import AppKit

struct CatDemoRow: View {
    let title: String
    let progress: Double
    let motion: CatProgressMotion
    var coat: CatCoat = .tuxedo
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 16, weight: .medium))
                Spacer()
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 15, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 332 * motion.position)
                CatProgressDrawing(motion: motion, coat: coat).frame(width: 68, height: 54)
                Spacer(minLength: 0)
            }.frame(width: 400, height: 54)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color(red: 0.83, green: 0.88, blue: 0.12)).frame(width: 400 * progress)
            }.frame(width: 400, height: 5)
        }
    }
}

@main struct RenderCatPreview {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var slow = CatProgressMotion(progress: 0.06, now: 0)
        var fast = CatProgressMotion(progress: 0.06, now: 0)
        var idle = CatProgressMotion(progress: 0.4, now: 0)
        for frame in 0..<480 {
            let time = Double(frame) / 24
            let slowProgress = min(1, 0.06 + floor(time) * 0.018)
            let fastProgress = min(1, 0.06 + max(0, floor((time - 1) * 4) / 4) * 0.9)
            idle.advance(progress: 0.4, active: true, now: time)
            slow.advance(progress: slowProgress, active: true, now: time)
            fast.advance(progress: fastProgress, active: true, now: time)
            let view = VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 8) {
                    ForEach(Array(CatCoat.allCases.enumerated()), id: \.offset) { index, coat in
                        VStack(spacing: 4) {
                            CatProgressDrawing(motion: idle, coat: coat).frame(width: 92, height: 74)
                            Text(["Пятнистый", "Рыжий", "Серый", "Чёрный"][index]).font(.system(size: 12))
                        }
                    }
                }
                CatDemoRow(title: "Неторопливая загрузка", progress: slowProgress, motion: slow)
                CatDemoRow(title: "Быстрая загрузка", progress: fastProgress, motion: fast, coat: .ginger)
            }.padding(30).frame(width: 460, height: 410)
                .foregroundStyle(.white).background(Color(red: 0.07, green: 0.08, blue: 0.08))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("No image") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            try data.write(to: directory.appendingPathComponent(String(format: "%04d.png", frame)))
        }
    }
}
