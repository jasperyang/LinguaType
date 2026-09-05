import Cocoa

/// NSPanel subclass that intercepts right-mouse-down so we can pop up the
/// language menu without the OS treating the click as a left click on the
/// button.
private final class AnchorPanel: NSPanel {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onLeftClick?()
        } else if event.type == .rightMouseDown {
            onRightClick?()
        } else {
            super.sendEvent(event)
        }
    }
}

/// Owns the always-visible Companion "anchor" — a small floating window in
/// the top-right corner of the main screen. macOS 26 menu bars can host
/// only so many status items; if the user already has many icons, our
/// NSStatusItem either gets clipped or hidden in the overflow chevron. A
/// 36×28 floating panel survives that condition and also doubles as the
/// click target for toggling the translation panel.
final class StatusBarController: NSObject {
    private let togglePanel: () -> Void
    private let showPanel: () -> Void
    private let hidePanel: () -> Void
    private let isPanelVisible: () -> Bool

    private var anchorWindow: AnchorPanel!
    private var primaryItem: NSMenuItem!
    private var secondaryItem: NSMenuItem!
    private var menu: NSMenu!

    private(set) var installPath: String = ""

    init(togglePanel: @escaping () -> Void,
         showPanel:   @escaping () -> Void,
         hidePanel:   @escaping () -> Void,
         isPanelVisible: @escaping () -> Bool) {
        self.togglePanel = togglePanel
        self.showPanel = showPanel
        self.hidePanel = hidePanel
        self.isPanelVisible = isPanelVisible
    }

    func install() {
        anchorWindow = AnchorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 36, height: 28),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        anchorWindow.level = .statusBar
        anchorWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        anchorWindow.isOpaque = false
        anchorWindow.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 0.85)
        anchorWindow.hasShadow = true
        anchorWindow.ignoresMouseEvents = false
        anchorWindow.hidesOnDeactivate = false
        anchorWindow.acceptsMouseMovedEvents = true

        anchorWindow.onLeftClick = { [weak self] in self?.togglePanel() }
        anchorWindow.onRightClick = { [weak self] in self?.showMenu() }

        // The button inside is purely visual — actual click events are routed
        // through the AnchorPanel override. Having the button also gives
        // VoiceOver / screen readers a proper control to attach to.
        let button = NSButton(title: "字", target: nil, action: nil)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        if let cell = button.cell as? NSButtonCell {
            cell.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = "LinguaType Companion — 点击切换浮层，右键切换语言"

        anchorWindow.contentView?.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: anchorWindow.contentView!.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: anchorWindow.contentView!.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])

        positionInTopRight()
        anchorWindow.orderFrontRegardless()
        installPath = "floating window at top-right of main screen"

        menu = NSMenu()
        primaryItem = NSMenuItem(title: "主语言: \(LinguaTypePreferences.primaryLanguageID)",
                                 action: #selector(cyclePrimary), keyEquivalent: "")
        primaryItem.target = self
        menu.addItem(primaryItem)

        secondaryItem = NSMenuItem(title: "辅语言: \(LinguaTypePreferences.secondaryLanguageID ?? "off")",
                                   action: #selector(cycleSecondary), keyEquivalent: "")
        secondaryItem.target = self
        menu.addItem(secondaryItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 LinguaType Companion", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func positionInTopRight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = anchorWindow.frame.size
        let margin: CGFloat = 8
        let x = frame.maxX - size.width - margin
        let y = frame.maxY - size.height - margin
        anchorWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showMenu() {
        guard let menu = self.menu, let view = anchorWindow.contentView else { return }
        let location = NSEvent.mouseLocation
        let windowPoint = anchorWindow.convertPoint(fromScreen: location)
        let viewPoint = view.convert(windowPoint, from: nil)
        // Show with synthetic event anchored at the mouse so the menu closes
        // when the user clicks elsewhere.
        let synthetic = NSEvent.mouseEvent(with: .rightMouseDown,
                                           location: viewPoint,
                                           modifierFlags: [],
                                           timestamp: 0,
                                           windowNumber: anchorWindow.windowNumber,
                                           context: nil,
                                           eventNumber: 0,
                                           clickCount: 1,
                                           pressure: 1.0)
            ?? NSEvent.mouseEvent(with: .leftMouseDown,
                                  location: viewPoint,
                                  modifierFlags: [],
                                  timestamp: 0,
                                  windowNumber: anchorWindow.windowNumber,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: 1.0)
        guard let synthetic else { return }
        NSMenu.popUpContextMenu(menu, with: synthetic, for: view)
    }

    @objc private func cyclePrimary() {
        LinguaTypePreferences.cyclePrimary()
        primaryItem.title = "主语言: \(LinguaTypePreferences.primaryLanguageID)"
    }

    @objc private func cycleSecondary() {
        LinguaTypePreferences.cycleSecondary()
        secondaryItem.title = "辅语言: \(LinguaTypePreferences.secondaryLanguageID ?? "off")"
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
