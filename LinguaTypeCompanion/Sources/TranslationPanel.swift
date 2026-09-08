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
    private let resizeHandle = PanelResizeHandleView()
    private let autoHide: PanelAutoHideController
    private let sizePolicy = PanelSizePolicy()
    private weak var coordinator: LearningCoordinator?
    private var lastState: LearningDisplayState?
    private var lastAnchor: NSRect?
    private var autoHideStarted = false
    private var pinStateBeforeReview: Bool?
    private var hasUserSizeOverride = PanelSizePreferences.userSize() != nil

    init(
        coordinator: LearningCoordinator,
        autoHide: PanelAutoHideController = PanelAutoHideController(interval: 12)
    ) {
        self.coordinator = coordinator
        self.autoHide = autoHide
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
        panel.isMovableByWindowBackground = true
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
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            resizeHandle.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])
        resizeHandle.onResize = { [weak self] direction, delta in
            self?.resize(direction: direction, delta: delta)
        }
        coordinator.install(into: visualEffect)
        coordinator.onUpdate = { [weak self] state in self?.apply(state) }
        content.onSelectionChange = { [weak coordinator] selection in
            coordinator?.setLanguageSelection(selection)
        }
        content.onLearnerLevelChange = { [weak coordinator] level, language in
            coordinator?.setLearnerLevel(level, for: language)
        }
        content.onTogglePin = { [weak self] in self?.togglePinned() }
        visualEffect.onEnter = { [weak autoHide] in autoHide?.pointerEntered() }
        visualEffect.onExit = { [weak autoHide] in autoHide?.pointerExited() }
    }

    var isVisible: Bool { panel.isVisible }
    var isPinned: Bool { autoHide.isPinned }
    var isReviewVisible: Bool { content.isReviewVisible }
    var isMovableByBackground: Bool { panel.isMovableByWindowBackground }

    func toggleAttachedToMouse() {
        if panel.isVisible {
            hide()
        } else {
            showAttachedToMouse()
        }
    }

    func showAttachedToMouse() {
        guard let lastState else { return }
        refreshContent(with: lastState)
        position(near: currentMouseRect())
        panel.orderFrontRegardless()
        startAutoHideIfNeeded(for: lastState)
    }

    func hide() {
        panel.orderOut(nil)
        content.cancelTransientFeedback()
        autoHide.cancel()
        autoHideStarted = false
    }

    func performPinAction() {
        content.performPinAction()
    }

    func showReview(
        _ item: ReviewItem,
        onAnswer: @escaping (ReviewItem, Bool) -> Void
    ) {
        pinStateBeforeReview = autoHide.isPinned
        autoHide.setPinned(true)
        content.showReview(item) { [weak self] answeredItem, isCorrect in
            onAnswer(answeredItem, isCorrect)
            self?.dismissReview()
        }
        position(near: lastAnchor ?? currentMouseRect())
        panel.orderFrontRegardless()
    }

    func performReviewAnswer(isCorrect: Bool) {
        content.performReviewAnswer(isCorrect: isCorrect)
    }

    func togglePinned() {
        autoHide.setPinned(!autoHide.isPinned)
        if let lastState {
            refreshContent(with: lastState)
        }
    }

    func position(near anchor: NSRect) {
        lastAnchor = anchor
        guard let screen = screen(containing: anchor) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let maxHeight = min(560, visible.height * 0.60)
        let desiredHeight = min(maxHeight, estimatedHeight(for: lastState))
        let requestedSize = hasUserSizeOverride
            ? PanelSizePreferences.userSize() ?? NSSize(width: 520, height: desiredHeight)
            : NSSize(width: 520, height: desiredHeight)
        let size = sizePolicy.size(requested: requestedSize, visibleFrame: visible)
        let gap: CGFloat = 10
        let margin: CGFloat = 6

        var x = anchor.minX
        var y = anchor.minY - gap - size.height
        if y < visible.minY + margin { y = anchor.maxY + gap }
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        y = min(max(y, visible.minY + margin), visible.maxY - size.height - margin)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    private func resize(direction: PanelResizeDirection, delta: NSPoint) {
        guard let screen = screen(containing: panel.frame) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let raw = PanelResizeMath.frame(from: panel.frame, direction: direction, delta: delta)
        let size = sizePolicy.size(requested: raw.size, visibleFrame: screen.visibleFrame)
        var origin = raw.origin
        if preservesRightEdge(direction) { origin.x = raw.maxX - size.width }
        if preservesTopEdge(direction) { origin.y = raw.maxY - size.height }

        let margin = sizePolicy.margin
        origin.x = min(max(origin.x, screen.visibleFrame.minX + margin), screen.visibleFrame.maxX - size.width - margin)
        origin.y = min(max(origin.y, screen.visibleFrame.minY + margin), screen.visibleFrame.maxY - size.height - margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        PanelSizePreferences.setUserSize(size)
        hasUserSizeOverride = true
    }

    private func preservesRightEdge(_ direction: PanelResizeDirection) -> Bool {
        switch direction {
        case .left, .topLeft, .bottomLeft: true
        default: false
        }
    }

    private func preservesTopEdge(_ direction: PanelResizeDirection) -> Bool {
        switch direction {
        case .bottom, .bottomLeft, .bottomRight: true
        default: false
        }
    }

    func apply(_ state: LearningDisplayState?) {
        guard let state else {
            if autoHide.isPinned, lastState != nil {
                return
            }
            hide()
            lastState = nil
            return
        }
        lastState = state
        refreshContent(with: state)
        position(near: lastAnchor ?? currentMouseRect())
        panel.orderFrontRegardless()

        if state.phase == .translatingPhrase {
            autoHide.cancel()
            autoHideStarted = false
        } else {
            startAutoHideIfNeeded(for: state)
        }
    }

    private func refreshContent(with state: LearningDisplayState) {
        content.apply(
            state,
            selection: coordinator?.languageSelection ?? .default,
            isPinned: autoHide.isPinned
        )
    }

    private func dismissReview() {
        if let previous = pinStateBeforeReview {
            autoHide.setPinned(previous)
        }
        pinStateBeforeReview = nil
        guard let lastState else {
            hide()
            return
        }
        refreshContent(with: lastState)
        position(near: lastAnchor ?? currentMouseRect())
        if !autoHide.isPinned {
            autoHideStarted = false
            startAutoHideIfNeeded(for: lastState)
        }
    }

    private func startAutoHideIfNeeded(for state: LearningDisplayState) {
        guard !autoHideStarted,
              state.phraseTranslations.contains(where: { $0.status != .loading }) else {
            return
        }
        autoHideStarted = true
        autoHide.start { [weak self] in self?.hide() }
    }

    private func estimatedHeight(for state: LearningDisplayState?) -> CGFloat {
        guard state != nil else { return 190 }
        return max(190, content.preferredHeight)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private func currentMouseRect() -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - 12, y: mouse.y - 12, width: 24, height: 24)
    }
}
