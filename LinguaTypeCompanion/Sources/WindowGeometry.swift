import ApplicationServices
import Cocoa
import CoreGraphics

struct LinguaTypeScreenCoordinateSpace {
    let accessibilityFrame: CGRect
    let appKitFrame: NSRect

    static var current: [LinguaTypeScreenCoordinateSpace] {
        NSScreen.screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return LinguaTypeScreenCoordinateSpace(
                accessibilityFrame: CGDisplayBounds(displayID),
                appKitFrame: screen.frame
            )
        }
    }
}

enum LinguaTypeWindowGeometry {
    static func appKitRect(fromAXValue value: CFTypeRef,
                           coordinateSpaces: [LinguaTypeScreenCoordinateSpace])
        -> NSRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }

        var accessibilityRect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &accessibilityRect) else {
            return nil
        }

        let center = CGPoint(x: accessibilityRect.midX, y: accessibilityRect.midY)
        guard let space = coordinateSpaces.first(where: {
            $0.accessibilityFrame.contains(center)
        }) ?? coordinateSpaces.first else {
            return nil
        }

        let localX = accessibilityRect.minX - space.accessibilityFrame.minX
        let localY = accessibilityRect.minY - space.accessibilityFrame.minY
        return NSRect(
            x: space.appKitFrame.minX + localX,
            y: space.appKitFrame.maxY - localY - accessibilityRect.height,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
    }
}
