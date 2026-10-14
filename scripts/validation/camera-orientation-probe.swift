// Compile together with shared/apple/Camera/CameraFrameOrientation.swift on macOS.
// Uses a rotated text chart to check the actual OCR raster, not only angle constants.
import AppKit
import CoreImage
import Vision

@main struct CameraOrientationProbe {
    static func main() throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        let cases: [(CameraFrameOrientation, Int, Int, CGFloat)] = [
            (.portrait, 600, 1000, .pi / 2),
            (.landscapeLeft, 1000, 600, .pi),
            (.landscapeRight, 1000, 600, 0),
            (.portraitUpsideDown, 600, 1000, -.pi / 2)
        ]
        func recognize(_ image: CGImage) throws -> [VNRecognizedTextObservation] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            return request.results ?? []
        }
        for (orientation, width, height, fixtureRotation) in cases {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black]
            ("RAILWAY STATION" as NSString).draw(at: NSPoint(x: 40, y: height - 100), withAttributes: attributes)
            ("TICKETS AND EXIT" as NSString).draw(at: NSPoint(x: 70, y: height - 230), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            let reference = bitmap.cgImage!
            // Independent fixture transform simulates the sensor when the handset is held this way.
            let sensorImage = CIImage(cgImage: reference).transformed(by: CGAffineTransform(rotationAngle: fixtureRotation))
            let sensor = context.createCGImage(sensorImage, from: sensorImage.extent)!
            let upright = orientation.upright(CIImage(cgImage: sensor))
            let raster = context.createCGImage(upright, from: upright.extent)!
            precondition(raster.width == width && raster.height == height, "Rotated dimensions differ")
            let expected = try recognize(reference), actual = try recognize(raster)
            precondition(actual.map { $0.topCandidates(1).first!.string } == ["RAILWAY STATION", "TICKETS AND EXIT"], "OCR text or reading order differs: \(orientation)")
            precondition(expected.count == actual.count)
            for (a, b) in zip(expected, actual) {
                precondition(abs(a.boundingBox.minX - b.boundingBox.minX) < 0.01 && abs(a.boundingBox.minY - b.boundingBox.minY) < 0.01, "Overlay coordinates differ")
            }
            print("PASS \(orientation): \(raster.width)x\(raster.height), OCR text and overlay boxes agree")
        }
    }
}
