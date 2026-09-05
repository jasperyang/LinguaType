import Cocoa

private final class LearningPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverEffectView: NSVisualEffectView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

final class TranslationPanel: NSObject {
    private let panel: LearningPanelWindow
    private let visualEffect = HoverEffectView()
    private let content = LearningPanelContentView()
    private let autoHide = PanelAutoHideController(interval: 12)
    private var lastState: LearningDisplayState?
    private var lastAnchor: NSRect?
    private var autoHideStarted = false

    init(coordinator: LearningCoordinator) {
        panel = LearningPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        content.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            content.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            content.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])
        coordinator.install(into: visualEffect)
        coordinator.onUpdate = { [weak self] state in self?.apply(state) }
        visualEffect.onEnter = { [weak autoHide] in autoHide?.pointerEntered() }
        visualEffect.onExit = { [weak autoHide] in autoHide?.pointerExited() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggleAttachedToMouse() {
        if panel.isVisible {
            hide()
        } else {
            showAttachedToMouse()
        }
    }

    func showAttachedToMouse() {
        guard let lastState else { return }
        content.apply(lastState)
        position(near: currentMouseRect())
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        autoHide.cancel()
    }

    func position(near anchor: NSRect) {
        lastAnchor = anchor
        guard let screen = screen(containing: anchor) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let maxHeight = min(560, visible.height * 0.60)
        let desiredHeight = min(maxHeight, estimatedHeight(for: lastState))
        let width: CGFloat = 520
        let gap: CGFloat = 10
        let margin: CGFloat = 6

        var x = anchor.minX
        var y = anchor.minY - gap - desiredHeight
        if y < visible.minY + margin { y = anchor.maxY + gap }
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
        y = min(max(y, visible.minY + margin), visible.maxY - desiredHeight - margin)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: desiredHeight), display: true)
    }

    private func apply(_ state: LearningDisplayState?) {
        guard let state else {
            hide()
            lastState = nil
            return
        }
        lastState = state
        content.apply(state)
        position(near: lastAnchor ?? currentMouseRect())
        panel.orderFrontRegardless()

        if !autoHideStarted, state.phraseTranslations.contains(where: { $0.status != .loading }) {
            autoHideStarted = true
            autoHide.start { [weak self] in self?.hide() }
        }
        if state.phase == .translatingPhrase { autoHideStarted = false }
    }

    private func estimatedHeight(for state: LearningDisplayState?) -> CGFloat {
        guard let state else { return 190 }
        return 132 + CGFloat(state.vocabularyCards.count) * 116
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private func currentMouseRect() -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - 12, y: mouse.y - 12, width: 24, height: 24)
    }
}
