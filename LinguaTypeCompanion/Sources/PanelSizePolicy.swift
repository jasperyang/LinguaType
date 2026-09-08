import Cocoa

enum PanelSizeSource {
    case automatic
    case userOverride
}

struct PanelSizePolicy {
    let minimumSize = NSSize(width: 420, height: 190)
    let maximumHeightFraction: CGFloat = 0.60
    let margin: CGFloat = 6

    func size(requested: NSSize, visibleFrame: NSRect) -> NSSize {
        let maximumWidth = max(minimumSize.width, visibleFrame.width - margin * 2)
        let maximumHeight = max(
            minimumSize.height,
            min(560, visibleFrame.height * maximumHeightFraction)
        )
        return NSSize(
            width: min(max(requested.width, minimumSize.width), maximumWidth),
            height: min(max(requested.height, minimumSize.height), maximumHeight)
        )
    }
}
