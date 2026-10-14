import AVFoundation
import CoreImage
import Foundation

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.openoffline.camera")
    private let frames = DispatchQueue(label: "org.openoffline.camera.frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @Sendable (CGImage, Int) async -> Void
    private let deliveryLock = NSLock()
    private var delivering = false
    // Shared with frame delivery; each image carries the revision it was rotated for.
    private var orientation: CameraFrameOrientation = .portrait
    private var orientationRevision = 0
    func setOrientation(_ value: CameraFrameOrientation, revision: Int) {
        deliveryLock.lock(); orientation = value; orientationRevision = revision; deliveryLock.unlock()
    }
    private func frameOrientation() -> (CameraFrameOrientation, Int) {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        return (orientation, orientationRevision)
    }
    private var configured = false
    private var lastFrame = 0.0
    private var device: AVCaptureDevice?
    private var photoOutput: AVCapturePhotoOutput?
    private var pendingPhoto: CheckedContinuation<CGImage, Error>?
    private var pendingPhotoID: Int64?
    private var subjectObserver: NSObjectProtocol?
    private var normalZoom: CGFloat = 1
    init(onFrame: @escaping @Sendable (CGImage, Int) async -> Void) { self.onFrame = onFrame; super.init() }
    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.cameraDenied }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in queue.async {
            do {
                if !self.configured {
                    self.session.beginConfiguration()
                    defer {
                        if !self.configured {
                            for output in self.session.outputs { self.session.removeOutput(output) }
                            for input in self.session.inputs { self.session.removeInput(input) }
                            self.device = nil; self.photoOutput = nil
                        }
                        self.session.commitConfiguration()
                    }
                    // A virtual camera can switch to its close-focusing lens automatically.
                    guard let camera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraError.cameraUnavailable }
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else { throw CameraError.cameraUnavailable }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.frames)
                    let photo = AVCapturePhotoOutput()
                    guard self.session.canAddOutput(output), self.session.canAddOutput(photo) else {
                        self.session.removeInput(input); throw CameraError.cameraUnavailable
                    }
                    self.session.addOutput(output); self.session.addOutput(photo)
                    if self.session.canSetSessionPreset(.photo) { self.session.sessionPreset = .photo }
                    photo.maxPhotoQualityPrioritization = .quality
                    // Bound photo memory while retaining much more detail than a 720p video frame.
                    let sizes = camera.activeFormat.supportedMaxPhotoDimensions
                    if let size = sizes.filter({ Int64($0.width)*Int64($0.height) <= 13_000_000 }).max(by: { Int64($0.width)*Int64($0.height) < Int64($1.width)*Int64($1.height) }) ?? sizes.first {
                        photo.maxPhotoDimensions = size
                    }
                    // Keep sensor buffers unrotated. Rotate only the throttled OCR frames,
                    // with an immutable orientation snapshot, rather than every video frame.
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                    self.device = camera; self.photoOutput = photo
                    self.normalZoom = camera.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
                    try camera.lockForConfiguration()
                    camera.videoZoomFactor = min(camera.maxAvailableVideoZoomFactor, max(camera.minAvailableVideoZoomFactor, self.normalZoom))
                    if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                    if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                    camera.isSubjectAreaChangeMonitoringEnabled = true
                    camera.unlockForConfiguration()
                    self.subjectObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: camera, queue: nil) { [weak self] _ in self?.focus(at: CGPoint(x: 0.5, y: 0.5), continuous: true) }
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                c.resume()
            } catch { c.resume(throwing: error) }
        } }
    }
    func focus(at point: CGPoint, continuous: Bool = false) {
        queue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                let mode: AVCaptureDevice.FocusMode = continuous ? .continuousAutoFocus : .autoFocus
                if device.isFocusModeSupported(mode) { device.focusMode = mode }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.isSubjectAreaChangeMonitoringEnabled = true
            } catch { /* Continuous capture stays available if the hardware is temporarily locked. */ }
        }
    }
    func zoom(_ factor: CGFloat) {
        queue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, self.normalZoom * factor))
            } catch { }
        }
    }
    func takePhoto() async throws -> CGImage {
        try await withCheckedThrowingContinuation { c in queue.async {
            guard self.pendingPhoto == nil, self.session.isRunning, let output = self.photoOutput else { c.resume(throwing: CameraError.cameraUnavailable); return }
            let angle = self.frameOrientation().0.degrees
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            self.pendingPhoto = c; self.pendingPhotoID = settings.uniqueID
            output.capturePhoto(with: settings, delegate: self)
        } }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            guard self.pendingPhotoID == photo.resolvedSettings.uniqueID, let pending = self.pendingPhoto else { return }
            self.pendingPhoto = nil; self.pendingPhotoID = nil
            do {
                if let error { throw error }
                guard let data = photo.fileDataRepresentation() else { throw CameraError.image }
                pending.resume(returning: try CameraOverlay.decode(data, maximumSize: 3072))
            } catch { pending.resume(throwing: error) }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async {
            guard self.pendingPhotoID == resolvedSettings.uniqueID, let pending = self.pendingPhoto else { return }
            self.pendingPhoto = nil; self.pendingPhotoID = nil
            pending.resume(throwing: error ?? CameraError.image)
        }
    }
    func stop() async {
        await withCheckedContinuation { c in queue.async {
            self.pendingPhoto?.resume(throwing: CancellationError()); self.pendingPhoto = nil; self.pendingPhotoID = nil
            if self.session.isRunning { self.session.stopRunning() }; c.resume()
        } }
    }
    private func finishDelivery() { deliveryLock.lock(); delivering = false; deliveryLock.unlock() }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = ProcessInfo.processInfo.systemUptime
        guard time-lastFrame >= 0.35, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        deliveryLock.lock()
        guard !delivering else { deliveryLock.unlock(); return }
        delivering = true; deliveryLock.unlock(); lastFrame = time
        let (orientation, revision) = frameOrientation()
        let original = orientation.upright(CIImage(cvPixelBuffer: buffer))
        let scale = min(1, 1600 / max(original.extent.width, original.extent.height))
        let image = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if let cg = context.createCGImage(image, from: image.extent) { Task { await onFrame(cg, revision); finishDelivery() } }
        else { finishDelivery() }
    }
    deinit { if let subjectObserver { NotificationCenter.default.removeObserver(subjectObserver) } }
}
