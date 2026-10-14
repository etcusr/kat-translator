import CoreImage
import ImageIO

/// Rotation from the rear camera's unrotated sensor buffer into interface coordinates.
/// UIInterfaceOrientation uses the opposite left/right convention to UIDeviceOrientation.
enum CameraFrameOrientation: Sendable {
    case portrait, landscapeLeft, landscapeRight, portraitUpsideDown
    var degrees: CGFloat {
        switch self {
        case .portrait: return 90
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        case .portraitUpsideDown: return 270
        }
    }
    var exif: CGImagePropertyOrientation {
        switch self {
        case .portrait: return .right
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        case .portraitUpsideDown: return .left
        }
    }
    func upright(_ image: CIImage) -> CIImage { image.oriented(exif) }
}
