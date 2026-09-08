import Cocoa

final class LanguagePickerView: NSView {
    var onChange: ((LanguageSelection) -> Void)?
    var onLearnerLevelChange: ((LearnerLevel, LearningLanguage) -> Void)?
    private(set) var selection: LanguageSelection

    private let stack = NSStackView()

    init(selection: LanguageSelection) {
        self.selection = selection
        super.init(frame: NSRect(x: 0, y: 0, width: 248, height: 176))
        build()
        rebuildRows()
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ selection: LanguageSelection) {
        self.selection = selection
        rebuildRows()
    }

    func setSelected(_ language: LearningLanguage, enabled: Bool) {
        selection.setSelected(language, enabled: enabled)
        rebuildRows()
        onChange?(selection)
    }

    func makePrimary(_ language: LearningLanguage) {
        selection.setPrimary(language)
        rebuildRows()
        onChange?(selection)
    }

    func setLearnerLevel(_ level: LearnerLevel, for language: LearningLanguage) {
        LinguaTypePreferences.setLearnerLevel(level, for: language)
        onLearnerLevelChange?(level, language)
        rebuildRows()
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func rebuildRows() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let title = NSTextField(labelWithString: "翻译语言")
        title.font = .systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.setAccessibilityLabel("翻译语言")
        stack.addArrangedSubview(title)

        for (index, language) in LearningLanguage.displayOrder.enumerated() {
            let row = makeRow(language: language, tag: index)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        }
    }

    private func makeRow(language: LearningLanguage, tag: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheckbox(_:)))
        checkbox.tag = tag
        checkbox.state = selection.selected.contains(language) ? .on : .off
        checkbox.isEnabled = language != selection.primary
        checkbox.setAccessibilityLabel("显示\(language.displayName)")

        let name = NSButton(
            title: "\(language.displayName)  \(language.nativeName)",
            target: self,
            action: #selector(selectPrimary(_:))
        )
        name.tag = tag
        name.isBordered = false
        name.alignment = .left
        name.font = .systemFont(ofSize: 12, weight: language == selection.primary ? .semibold : .regular)
        name.contentTintColor = language == selection.primary ? .controlAccentColor : .labelColor
        name.setAccessibilityLabel("设\(language.displayName)为主学习语言")
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let role = NSTextField(labelWithString: language == selection.primary ? "主语言" : "")
        role.font = .systemFont(ofSize: 9, weight: .medium)
        role.textColor = .secondaryLabelColor

        let level = NSPopUpButton(frame: .zero, pullsDown: false)
        level.addItems(withTitles: LearnerLevel.allCases.map(\.displayName))
        level.selectItem(withTitle: LinguaTypePreferences.learnerLevel(for: language).displayName)
        level.tag = tag
        level.target = self
        level.action = #selector(changeLearnerLevel(_:))
        level.font = .systemFont(ofSize: 9, weight: .medium)
        level.setAccessibilityLabel("\(language.displayName)学习等级")

        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(name)
        row.addArrangedSubview(role)
        row.addArrangedSubview(level)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return row
    }

    @objc private func toggleCheckbox(_ sender: NSButton) {
        guard LearningLanguage.displayOrder.indices.contains(sender.tag) else { return }
        setSelected(
            LearningLanguage.displayOrder[sender.tag],
            enabled: sender.state == .on
        )
    }

    @objc private func selectPrimary(_ sender: NSButton) {
        guard LearningLanguage.displayOrder.indices.contains(sender.tag) else { return }
        makePrimary(LearningLanguage.displayOrder[sender.tag])
    }

    @objc private func changeLearnerLevel(_ sender: NSPopUpButton) {
        guard LearningLanguage.displayOrder.indices.contains(sender.tag),
              LearnerLevel.allCases.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        setLearnerLevel(
            LearnerLevel.allCases[sender.indexOfSelectedItem],
            for: LearningLanguage.displayOrder[sender.tag]
        )
    }
}
