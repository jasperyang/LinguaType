import Cocoa

enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7.2, weight: .bold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
                .kern: -0.35,
            ]
            let mark = NSAttributedString(string: "A·あ", attributes: attributes)
            let size = mark.size()
            mark.draw(at: NSPoint(x: rect.midX - size.width / 2,
                                  y: rect.midY - size.height / 2 + 0.5))
            return true
        }
        image.isTemplate = true
        return image
    }
}
