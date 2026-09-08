import Cocoa

enum LinguaTypePalette {
    static let panelBackground = NSColor(
        calibratedRed: 0.075,
        green: 0.105,
        blue: 0.135,
        alpha: 0.92
    )
    static let understand = NSColor(
        calibratedRed: 0.43,
        green: 0.72,
        blue: 0.92,
        alpha: 1
    )
    static let compare = NSColor(
        calibratedRed: 0.67,
        green: 0.60,
        blue: 0.94,
        alpha: 1
    )
    static let remember = NSColor(
        calibratedRed: 0.93,
        green: 0.73,
        blue: 0.37,
        alpha: 1
    )
    static let practice = NSColor(
        calibratedRed: 0.39,
        green: 0.82,
        blue: 0.66,
        alpha: 1
    )
    static let review = NSColor(
        calibratedRed: 0.91,
        green: 0.55,
        blue: 0.67,
        alpha: 1
    )

    static func surface(for accent: NSColor, alpha: CGFloat = 0.12) -> NSColor {
        accent.withAlphaComponent(alpha)
    }
}
