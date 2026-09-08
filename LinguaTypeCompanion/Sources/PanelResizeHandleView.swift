import Cocoa

enum PanelResizeDirection {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum PanelResizeMath {
    static func frame(
        from frame: NSRect,
        direction: PanelResizeDirection,
        delta: NSPoint
    ) -> NSRect {
        var resized = frame
        switch direction {
        case .left, .topLeft, .bottomLeft:
            resized.origin.x += delta.x
            resized.size.width -= delta.x
        default:
            break
        }
        switch direction {
        case .right, .topRight, .bottomRight:
            resized.size.width += delta.x
        default:
            break
        }
        switch direction {
        case .top, .topLeft, .topRight:
            resized.size.height += delta.y
        default:
            break
        }
        switch direction {
        case .bottom, .bottomLeft, .bottomRight:
            resized.origin.y += delta.y
            resized.size.height -= delta.y
        default:
            break
        }
        return resized
    }
}

final class PanelResizeHandleView: NSView {
    var onResize: ((PanelResizeDirection, NSPoint) -> Void)?

    private let edgeBand: CGFloat = 8
    private let cornerBand: CGFloat = 14
    private var dragDirection: PanelResizeDirection?
    private var dragStart: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? {
        direction(at: point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragDirection = direction(at: point)
        dragStart = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragDirection, let dragStart else { return }
        let current = NSEvent.mouseLocation
        onResize?(dragDirection, NSPoint(
            x: current.x - dragStart.x,
            y: current.y - dragStart.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragDirection = nil
        dragStart = nil
    }

    override func resetCursorRects() {
        let corners: [(NSRect, NSCursor)] = [
            (NSRect(x: 0, y: 0, width: cornerBand, height: cornerBand), .crosshair),
            (NSRect(x: bounds.maxX - cornerBand, y: 0, width: cornerBand, height: cornerBand), .crosshair),
            (NSRect(x: 0, y: bounds.maxY - cornerBand, width: cornerBand, height: cornerBand), .crosshair),
            (NSRect(x: bounds.maxX - cornerBand, y: bounds.maxY - cornerBand, width: cornerBand, height: cornerBand), .crosshair),
        ]
        corners.forEach { addCursorRect($0.0, cursor: $0.1) }
        addCursorRect(NSRect(x: 0, y: cornerBand, width: edgeBand, height: max(0, bounds.height - cornerBand * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.maxX - edgeBand, y: cornerBand, width: edgeBand, height: max(0, bounds.height - cornerBand * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: cornerBand, y: 0, width: max(0, bounds.width - cornerBand * 2), height: edgeBand), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: cornerBand, y: bounds.maxY - edgeBand, width: max(0, bounds.width - cornerBand * 2), height: edgeBand), cursor: .resizeUpDown)
    }

    private func direction(at point: NSPoint) -> PanelResizeDirection? {
        let nearLeft = point.x <= edgeBand
        let nearRight = point.x >= bounds.maxX - edgeBand
        let nearBottom = point.y <= edgeBand
        let nearTop = point.y >= bounds.maxY - edgeBand
        let inLeftCorner = point.x <= cornerBand
        let inRightCorner = point.x >= bounds.maxX - cornerBand
        let inBottomCorner = point.y <= cornerBand
        let inTopCorner = point.y >= bounds.maxY - cornerBand

        if inLeftCorner && inBottomCorner { return .bottomLeft }
        if inRightCorner && inBottomCorner { return .bottomRight }
        if inLeftCorner && inTopCorner { return .topLeft }
        if inRightCorner && inTopCorner { return .topRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearTop { return .top }
        return nil
    }
}
