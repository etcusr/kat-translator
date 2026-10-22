import UIKit
import ImageIO
import OfflineCore

@MainActor enum CameraOverlay {
    /// Photos with an overlay are saved and shared as JPEG: PNG of a 3072 px photo was 10+ MB and slow to encode.
    /// 0.9 keeps overlay text sharp; Mac screen captures stay PNG (audit 22.10, owner decision O18).
    nonisolated static let photoQuality: CGFloat = 0.9
    /// This exact raster is used over the preview and composited into saved images.
    /// Renderers, fonts and string drawing are thread-safe; callers render off the main actor (audit 22.10, iOS C2).
    nonisolated static func render(size: CGSize, blocks: [TranslatedImageBlock]) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let unit = max(1, size.width / 720)
            for block in blocks {
                let b = block.box
                let rect = CGRect(x: b.x*size.width, y: b.y*size.height, width: b.width*size.width, height: b.height*size.height).insetBy(dx: -2*unit, dy: -2*unit).intersection(CGRect(origin: .zero, size: size))
                guard rect.width > 4*unit, rect.height > 4*unit else { continue }
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
                func attributes(_ value: CGFloat) -> [NSAttributedString.Key: Any] { [.font: UIFont.systemFont(ofSize: value, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: paragraph] }
                let fontSize = fittingSize(start: min(32*unit, max(8*unit, rect.height*0.65)), step: 0.5*unit, floor: 3*unit) { value in
                    (block.translation as NSString).boundingRect(with: CGSize(width: rect.width-4*unit, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin,.usesFontLeading], attributes: attributes(value), context: nil).height <= rect.height-4*unit
                }
                renderer.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.85).cgColor); renderer.cgContext.fill(rect)
                (block.translation as NSString).draw(with: rect.insetBy(dx: 2*unit, dy: 2*unit), options: [.usesLineFragmentOrigin,.usesFontLeading], attributes: attributes(fontSize), context: nil)
            }
        }
    }
    /// The size the former linear search chose: the first of start, start-step, … (same repeated subtraction)
    /// that fits, or the first at or below floor. Text height only shrinks with the font, so a binary search
    /// finds it with ~6 measurements instead of up to ~58 per block (audit 22.10, iOS C2).
    nonisolated static func fittingSize(start: CGFloat, step: CGFloat, floor: CGFloat, fits: (CGFloat) -> Bool) -> CGFloat {
        var sizes = [start]
        while let last = sizes.last, last > floor { sizes.append(last - step) }
        var low = 0, high = sizes.count - 1 // sizes[high] is at or below floor: chosen without measuring
        while low < high {
            let middle = (low + high) / 2
            if fits(sizes[middle]) { high = middle } else { low = middle + 1 }
        }
        return sizes[low]
    }
    nonisolated static func composite(_ image: CGImage, overlay: UIImage) -> UIImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size)); overlay.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    nonisolated static func decode(_ data: Data, maximumSize: Int = 3072) throws -> CGImage {
        guard data.count <= 50*1024*1024, let source = CGImageSourceCreateWithData(data as CFData,nil) else { throw CameraError.image }
        return try downsample(source, maximumSize: maximumSize)
    }
    /// A picked photo is read from its file, so panoramas and ProRAW files above the 50 MB in-memory limit
    /// are only downsampled, never loaded whole (audit 22.10, iOS C5).
    nonisolated static func decode(file: URL, maximumSize: Int = 3072) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw CameraError.image }
        return try downsample(source, maximumSize: maximumSize)
    }
    nonisolated private static func downsample(_ source: CGImageSource, maximumSize: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:maximumSize,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { throw CameraError.image }
        return image
    }
    nonisolated static func signature(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 256)
        pixels.withUnsafeMutableBytes { memory in
            if let context = CGContext(data: memory.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) { context.draw(image,in:CGRect(x:0,y:0,width:16,height:16)) }
        }
        return pixels
    }
    nonisolated static func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        return zip(a,b).reduce(0) { $0 + abs(Double($1.0)-Double($1.1)) } / Double(a.count) / 255
    }
}
