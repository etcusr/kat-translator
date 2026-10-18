import Foundation

/// Reconstruct paragraphs for still images. Coordinates alone cannot identify arbitrary
/// document structure; use conservative line adjacency and keep lists/columns separate.
public enum ImageTextLayout {
    public static func paragraphs(_ input: [ImageTextBlock]) -> [ImageTextBlock] {
        let lines = input.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.box.width > 0 && $0.box.height > 0 }
            .sorted { $0.box.y == $1.box.y ? $0.box.x < $1.box.x : $0.box.y < $1.box.y }
        var output: [ImageTextBlock] = []
        var previous: ImageTextBlock?
        for line in lines {
            let text = compact(line.text)
            defer { previous = line }
            if let previous, let paragraph = output.last {
                let a = previous.box, b = line.box
                let gap = b.y - a.y - a.height
                // Compare adjacent lines, not the height of the accumulated paragraph.
                // A crop must not impose a maximum paragraph height or character count.
                // Ink bounds vary with glyphs; a lowercase-only final word can be
                // nearly half as tall without representing a different font size.
                let similarHeight = max(a.height, b.height) <= min(a.height, b.height) * 2
                let shortLineBeforeWiderLine = a.width < b.width * 0.6
                if abs(a.x - b.x) < 0.0125, gap >= -min(a.height, b.height) * 0.3,
                   gap < min(a.height, b.height) * 0.65, similarHeight,
                   !shortLineBeforeWiderLine, !startsListItem(text) {
                    let p = paragraph.box
                    let x = min(p.x, b.x), y = min(p.y, b.y)
                    output[output.count - 1] = ImageTextBlock(
                        text: join(paragraph.text, text),
                        box: ImageTextBox(x: x, y: y, width: max(p.x+p.width, b.x+b.width)-x,
                                          height: max(p.y+p.height, b.y+b.height)-y))
                    continue
                }
            }
            output.append(ImageTextBlock(text: text, box: line.box))
        }
        return output
    }

    /// OCR/model line wrapping is not a paragraph break. Only reconstructed blocks
    /// introduce paragraph spacing in the editable/copyable translation pane.
    public static func plainText(_ blocks: [TranslatedImageBlock]) -> String {
        blocks.map { compact($0.translation) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func compact(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).map(String.init).reduce("") { $0.isEmpty ? $1 : join($0, $1) }
    }
    private static func join(_ left: String, _ right: String) -> String {
        let separator = left.unicodeScalars.last.map(isCJK) == true && right.unicodeScalars.first.map(isCJK) == true ? "" : " "
        return left + separator + right
    }
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value) || (0x3400...0x9FFF).contains(scalar.value) || (0x20000...0x3134F).contains(scalar.value)
    }
    private static func startsListItem(_ text: String) -> Bool {
        text.range(of: #"^(?:[•●▪◦‣*-]|\d+[.)]|[A-Za-z][.)])\s"#, options: .regularExpression) != nil
    }
}
