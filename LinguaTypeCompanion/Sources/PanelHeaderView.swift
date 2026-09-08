import Cocoa

final class PanelHeaderView: NSView {
    var onSelectionChange: ((LanguageSelection) -> Void)?
    var onTogglePin: (() -> Void)?
    var onModeChange: ((LearningMode) -> Void)?

    private let brandLabel = NSTextField(labelWithString: "LINGUATYPE")
    private let subtitleLabel = NSTextField(labelWithString: "Write · Translate · Learn")
    private let languageButton = NSButton()
    private let pinButton = NSButton()
    private let modeControl = NSSegmentedControl(labels: ["极简", "深度"], trackingMode: .selectOne, target: nil, action: nil)
    private let languagePopover = NSPopover()
    private(set) var selection: LanguageSelection

    var languageButtonTitle: String { languageButton.title }

    init(selection: LanguageSelection) {
        self.selection = selection
        super.init(frame: .zero)
        build()
        apply(selection: selection, isPinned: false)
    }

    required init?(coder: NSCoder) { nil }

    func apply(selection: LanguageSelection, isPinned: Bool) {
        self.selection = selection
        languageButton.title = selection.primary.displayName
        languageButton.setAccessibilityLabel("选择翻译语言，当前主语言\(selection.primary.displayName)")
        pinButton.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin",
            accessibilityDescription: isPinned ? "取消固定浮窗" : "固定浮窗"
        )
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.setAccessibilityLabel(isPinned ? "取消固定浮窗" : "固定浮窗")
        modeControl.selectedSegment = LinguaTypePreferences.learningMode() == .minimal ? 0 : 1
    }

    func performPinAction() {
        pinButton.performClick(nil)
    }

    private func build() {
        brandLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        brandLabel.textColor = .secondaryLabelColor
        brandLabel.setAccessibilityLabel("LinguaType")

        subtitleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        subtitleLabel.textColor = .tertiaryLabelColor

        let identity = NSStackView(views: [brandLabel, subtitleLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 1

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        languageButton.target = self
        languageButton.action = #selector(showLanguagePicker(_:))
        languageButton.bezelStyle = .recessed
        languageButton.font = .systemFont(ofSize: 11, weight: .medium)
        languageButton.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )
        languageButton.imagePosition = .imageTrailing
        languageButton.imageScaling = .scaleProportionallyDown

        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.isBordered = false
        pinButton.bezelStyle = .inline
        pinButton.imagePosition = .imageOnly

        modeControl.target = self
        modeControl.action = #selector(changeMode(_:))
        modeControl.segmentStyle = .texturedRounded
        modeControl.font = .systemFont(ofSize: 9, weight: .medium)
        modeControl.setAccessibilityLabel("切换学习页面模式")

        let stack = NSStackView(views: [identity, spacer, languageButton, modeControl, pinButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func showLanguagePicker(_ sender: NSButton) {
        let picker = LanguagePickerView(selection: selection)
        picker.onChange = { [weak self] updatedSelection in
            guard let self else { return }
            self.selection = updatedSelection
            self.languageButton.title = updatedSelection.primary.displayName
            self.onSelectionChange?(updatedSelection)
        }
        let controller = NSViewController()
        controller.view = picker
        controller.preferredContentSize = NSSize(width: 248, height: 176)
        languagePopover.contentViewController = controller
        languagePopover.behavior = .transient
        languagePopover.animates = true
        languagePopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func togglePin() {
        onTogglePin?()
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        let mode: LearningMode = sender.selectedSegment == 1 ? .deep : .minimal
        LinguaTypePreferences.setLearningMode(mode)
        onModeChange?(mode)
    }
}
