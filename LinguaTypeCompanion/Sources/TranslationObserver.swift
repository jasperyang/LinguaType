import Cocoa
import ApplicationServices

/// Polls the focused text field via the Accessibility API at ~280 ms,
/// extracts the committed Chinese text, and hands it to the learning
/// coordinator. The cadence matches the IMK variant's debounce window
/// so the UX feels identical to the original LinguaType.app.
final class TranslationObserver {
    private weak var coordinator: LearningCoordinator?
    private let position: (NSRect) -> Void

    private var timer: Timer?
    private var lastSeenText: String = ""
    private var lastSeenAt: Date = .distantPast

    private static let pollInterval: TimeInterval = 0.28
    private static let minTextLength = 2
    private static let maxTextLength = 120

    init(coordinator: LearningCoordinator, position: @escaping (NSRect) -> Void) {
        self.coordinator = coordinator
        self.position = position
    }

    func start() {
        // Use the main run loop so the AXUIElementCopyAttributeValue dispatch
        // happens on the thread that owns AppKit (mandatory for NSPanel work).
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Read once immediately so the first commit doesn't wait 280 ms.
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let coordinator else { return }
        guard AXIsProcessTrusted() else {
            // Privacy hasn't been granted yet — skip until it is.
            return
        }
        guard let (text, rect) = readFocusedField() else { return }
        guard text != lastSeenText else { return }
        lastSeenText = text
        lastSeenAt = Date()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minTextLength,
              trimmed.count <= Self.maxTextLength else {
            coordinator.idle()
            return
        }
        guard containsHan(trimmed) else {
            coordinator.idle()
            return
        }

        NSLog("%@", PrivacySafeLog.committedText(characterCount: trimmed.count))
        position(rect)
        coordinator.commit(text: trimmed)
    }

    private func readFocusedField() -> (String, NSRect)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let axErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard axErr == .success, let focusedElement = focused else { return nil }
        let element = focusedElement as! AXUIElement

        var value: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard valueErr == .success, let cfString = value as? String else { return nil }

        var rectValue: CFTypeRef?
        let rectErr = AXUIElementCopyAttributeValue(element, "AXBounds" as CFString, &rectValue)
        let rect: NSRect
        if rectErr == .success,
           let rectValue,
           let converted = LinguaTypeWindowGeometry.appKitRect(
                fromAXValue: rectValue,
                coordinateSpaces: LinguaTypeScreenCoordinateSpace.current
           ) {
            rect = converted
        } else {
            rect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }

        return (cfString, rect)
    }

    private func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
