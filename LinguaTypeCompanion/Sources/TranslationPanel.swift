import Cocoa

/// Floating NSPanel that the learning coordinator fills with translation
/// rows. Lives outside the Dock (NSWindow.Level.floating, .nonactivatingPanel
/// style) so it never steals focus from the field the user is typing in.
///
/// The same visual treatment as the IMK variant: NSVisualEffectView with
/// hudWindow material, three lines (primary translation / secondary /
/// vocabulary), parked near the caret.
final class TranslationPanel: NSObject {
    private weak var coordinator: LearningCoordinator?

    private let panel: NSPanel
    private let visualEffect = NSVisualEffectView()
    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "语言学习")
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let vocabularyLabel = NSTextField(labelWithString: "")

    init(coordinator: LearningCoordinator) {
        self.coordinator = coordinator

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 126),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = .moveToActiveSpace

        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 9
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = visualEffect

        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        for label in [primaryLabel, secondaryLabel, vocabularyLabel] {
            label.font = .systemFont(ofSize: 12.5, weight: .regular)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        vocabularyLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        vocabularyLabel.textColor = .secondaryLabelColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(primaryLabel)
        stack.addArrangedSubview(secondaryLabel)
        stack.addArrangedSubview(vocabularyLabel)
        visualEffect.addSubview(stack)
        coordinator.install(into: visualEffect)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        coordinator.onUpdate = { [weak self] state in self?.apply(state) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggleAttachedToMouse() {
        if panel.isVisible { hide() } else { showAttachedToMouse() }
    }

    func showAttachedToMouse() {
        position(near: currentMouseRect())
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    func position(near anchor: NSRect) {
        let width: CGFloat = 460
        let height: CGFloat = vocabularyLabel.stringValue.isEmpty ? 98 : 126
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.minX
        var y = anchor.minY - 54 - height
        if y < visible.minY + 6 { y = anchor.maxY + 54 }
        x = min(max(x, visible.minX + 6), visible.maxX - width - 6)
        y = min(max(y, visible.minY + 6), visible.maxY - height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func currentMouseRect() -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - 12, y: mouse.y - 12, width: 24, height: 24)
    }

    private func apply(_ state: LearningCoordinator.DisplayState) {
        switch state {
        case .idle:
            hide()
        case .loading(let source):
            primaryLabel.stringValue = "\(flag(for: LinguaTypePreferences.primaryLanguageID))  ···"
            secondaryLabel.isHidden = LinguaTypePreferences.secondaryLanguageID == nil
            if let secondary = LinguaTypePreferences.secondaryLanguageID {
                secondaryLabel.stringValue = "\(flag(for: secondary))  ···"
            }
            if let vocab = source.vocabulary, !vocab.isEmpty {
                vocabularyLabel.isHidden = false
                vocabularyLabel.stringValue = "词汇  \(vocab)  →  ···"
            } else {
                vocabularyLabel.isHidden = true
            }
            panel.orderFrontRegardless()
        case .translated(let source, let translations):
            let primary = LinguaTypePreferences.primaryLanguageID
            let secondary = LinguaTypePreferences.secondaryLanguageID
            primaryLabel.stringValue = "\(flag(for: primary))  \(translations.primary ?? "···")"
            secondaryLabel.isHidden = secondary == nil
            if let secondary {
                secondaryLabel.stringValue = "\(flag(for: secondary))  \(translations.secondary ?? "···")"
            }
            if let vocab = source.vocabulary {
                let pieces = translations.vocabulary.compactMap { $0 }.filter { !$0.isEmpty }
                vocabularyLabel.isHidden = false
                vocabularyLabel.stringValue = pieces.isEmpty
                    ? "词汇  \(vocab)  →  ···"
                    : "词汇  \(vocab)  →  \(pieces.joined(separator: "  /  "))"
            } else {
                vocabularyLabel.isHidden = true
            }
            panel.orderFrontRegardless()
        }
    }

    private func flag(for language: String) -> String {
        let id = language.lowercased()
        if id.hasPrefix("fr") { return "🇫🇷" }
        if id.hasPrefix("en") { return "🇬🇧" }
        if id.hasPrefix("ja") { return "🇯🇵" }
        if id.hasPrefix("de") { return "🇩🇪" }
        if id.hasPrefix("es") { return "🇪🇸" }
        if id.hasPrefix("ko") { return "🇰🇷" }
        return "🌐"
    }
}
