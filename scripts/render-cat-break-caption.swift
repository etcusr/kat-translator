// Render a deterministic caption layer for the shared loading video.
import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift render-cat-break-caption.swift OUTPUT.png")
}
let size = NSSize(width: 384, height: 288)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill(using: .copy)
NSColor.black.setFill()
// AppKit coordinates start at the bottom; cover the two baked Russian captions.
NSRect(x: 0, y: 210, width: 384, height: 78).fill()
NSRect(x: 0, y: 0, width: 384, height: 78).fill()
let caption = NSAttributedString(string: "CAT BREAK", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .heavy),
    .foregroundColor: NSColor.white,
])
let extent = caption.size()
for y: CGFloat in [39, 249] {
    caption.draw(at: NSPoint(x: (size.width - extent.width) / 2, y: y - extent.height / 2))
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]))
