import AppKit
import ScreenCaptureKit
import OfflineCore

@MainActor final class ScreenRegionCapture {
    /// ScreenCaptureKit registers the app with macOS and presents first-use consent.
    /// Calling the legacy CoreGraphics request alone may not add it to Settings.
    static func requestPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch { return false }
    }
    private var windows: [NSWindow] = []
    private var hidden: [NSWindow] = []
    private var previousApp: NSRunningApplication?
    private var completion: ((Result<Data?, Error>) -> Void)?
    private var work: Task<Void, Never>?
    private var ended = false
    static func clampedRect(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(bounds)
    }
    func begin(completion: @escaping (Result<Data?, Error>) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion; previousApp = NSWorkspace.shared.frontmostApplication
        hidden = NSApp.windows.filter { $0.isVisible }
        hidden.forEach { $0.orderOut(nil) }
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let panel = CapturePanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.select = { [weak self] rect in self?.selected(rect, displayID: id, scale: screen.backingScaleFactor) }
            view.cancel = { [weak self] in self?.cancel() }
            panel.contentView = view; windows.append(panel)
            panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
        if windows.isEmpty { finish(.failure(CaptureError.unavailable)) }
    }
    func cancel() { work?.cancel(); finish(.success(nil)) }
    private func selected(_ rect: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) {
        guard !ended, work == nil else { return }
        guard !rect.isNull, rect.width >= 4, rect.height >= 4 else { cancel(); return }
        let excluded = Set(windows.map { CGWindowID($0.windowNumber) })
        windows.forEach { $0.orderOut(nil) }
        work = Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try Task.checkCancellation()
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.unavailable }
                let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { excluded.contains($0.windowID) })
                let config = SCStreamConfiguration()
                config.sourceRect = rect
                config.width = max(1, Int((rect.width * scale).rounded()))
                config.height = max(1, Int((rect.height * scale).rounded()))
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CaptureError.unavailable }
                finish(.success(data))
            } catch is CancellationError { finish(.success(nil)) }
            catch { finish(.failure(error)) }
        }
    }
    private func finish(_ result: Result<Data?, Error>) {
        guard !ended else { return }; ended = true
        windows.forEach { $0.close() }; windows = []
        hidden.forEach { $0.orderBack(nil) }; hidden = []
        previousApp?.activate(options: [])
        let callback = completion; completion = nil; work = nil; callback?(result)
    }
    private enum CaptureError: LocalizedError {
        case unavailable
        var errorDescription: String? { L10n.text("Не удалось получить снимок области экрана.") }
    }
    private final class CapturePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    private final class SelectionView: NSView {
        var select: ((CGRect) -> Void)?
        var cancel: (() -> Void)?
        private var start: CGPoint?
        private var rect = CGRect.zero
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        // Only one display's panel can be key. The initial press on another
        // display must begin selection instead of merely activating its panel.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); rect = .zero; needsDisplay = true }
        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            rect = ScreenRegionCapture.clampedRect(from: start, to: convert(event.locationInWindow, from: nil), bounds: bounds)
            needsDisplay = true
        }
        override func mouseUp(with event: NSEvent) { mouseDragged(with: event); select?(rect) }
        override func rightMouseDown(with event: NSEvent) { cancel?() }
        override func keyDown(with event: NSEvent) {
            if MacShortcutSettings.shared.shortcut(for: .cancel)?.matches(event) == true { cancel?() }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if MacShortcutSettings.shared.shortcut(for: .cancel)?.matches(event) == true { cancel?(); return true }
            return false
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill()
            if rect.width > 0 && rect.height > 0 {
                NSColor.clear.setFill(); rect.fill(using: .copy)
                NSColor(calibratedRed: 0.78, green: 1, blue: 0.12, alpha: 1).setStroke()
                let path = NSBezierPath(rect: rect); path.lineWidth = 2; path.stroke()
            }
            let text = L10n.text("Выделите область для перевода. Правый клик — отмена.")
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white]
            (text as NSString).draw(at: NSPoint(x: 24, y: 28), withAttributes: attributes)
        }
    }
}
