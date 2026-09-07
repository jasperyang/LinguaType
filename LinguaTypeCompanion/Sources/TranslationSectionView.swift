import Cocoa

final class TranslationSectionView: NSView {
    private let stack = NSStackView()
    private let copyService: TranslationCopyService
    private var selection: LanguageSelection = .default
    private var translations: [LearningLanguage: PhraseTranslation] = [:]
    private var sourcePhrase = ""
    private var rows: [LearningLanguage: TranslationRowView] = [:]

    private(set) var primaryLanguage: LearningLanguage?
    private(set) var referenceLanguages: [LearningLanguage] = []
    private(set) var expandedReference: LearningLanguage?
    private(set) var phraseLabels: [NSTextField] = []

    var copyButtonLanguages: [LearningLanguage] {
        selection.orderedLanguages.filter { rows[$0] != nil }
    }

    var renderedLanguageCodes: [String] {
        copyButtonLanguages.map(\.shortCode)
    }

    init(copyService: TranslationCopyService) {
        self.copyService = copyService
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { nil }

    func apply(
        translations: [PhraseTranslation],
        selection: LanguageSelection,
        sourcePhrase: String
    ) {
        if self.sourcePhrase != sourcePhrase {
            expandedReference = nil
        }
        self.sourcePhrase = sourcePhrase
        self.selection = selection
        self.translations = Dictionary(
            translations.map { ($0.language, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        rebuild()
    }

    func toggleReference(_ language: LearningLanguage) {
        guard language != selection.primary,
              selection.selected.contains(language) else { return }
        expandedReference = expandedReference == language ? nil : language
        rebuild()
    }

    func copyButton(for language: LearningLanguage) -> NSButton? {
        rows[language]?.copyButton
    }

    func cancelCopyFeedback() {
        rows.values.forEach { $0.cancelCopyFeedback() }
    }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll()
        phraseLabels.removeAll()

        primaryLanguage = selection.primary
        referenceLanguages = selection.orderedLanguages.filter { $0 != selection.primary }
        if let expandedReference, !referenceLanguages.contains(expandedReference) {
            self.expandedReference = nil
        }

        for language in selection.orderedLanguages {
            let fallback = PhraseTranslation(language: language, text: nil, status: .loading)
            let translation = translations[language] ?? fallback
            let isPrimary = language == selection.primary
            let row = TranslationRowView(
                translation: translation,
                isPrimary: isPrimary,
                isExpanded: isPrimary || expandedReference == language,
                copyService: copyService
            )
            if !isPrimary {
                row.onToggleExpansion = { [weak self] in
                    self?.toggleReference(language)
                }
            }
            rows[language] = row
            phraseLabels.append(row.translationLabel)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

private final class TranslationRowView: NSView {
    let translationLabel = NSTextField(wrappingLabelWithString: "")
    let copyButton = NSButton()
    var onToggleExpansion: (() -> Void)?

    private let translation: PhraseTranslation
    private let copyService: TranslationCopyService
    private let isPrimary: Bool
    private var resetCopyWorkItem: DispatchWorkItem?

    init(
        translation: PhraseTranslation,
        isPrimary: Bool,
        isExpanded: Bool,
        copyService: TranslationCopyService
    ) {
        self.translation = translation
        self.isPrimary = isPrimary
        self.copyService = copyService
        super.init(frame: .zero)
        build(isExpanded: isExpanded)
    }

    required init?(coder: NSCoder) { nil }

    private func build(isExpanded: Bool) {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = (
            isPrimary
                ? NSColor.controlAccentColor.withAlphaComponent(0.10)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.10)
        ).cgColor

        let code = NSTextField(labelWithString: translation.language.shortCode)
        code.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        code.textColor = isPrimary ? .controlAccentColor : .secondaryLabelColor
        code.setContentHuggingPriority(.required, for: .horizontal)
        code.setAccessibilityLabel(translation.language.displayName)

        let name = NSTextField(labelWithString: translation.language.nativeName)
        name.font = .systemFont(ofSize: 10, weight: isPrimary ? .semibold : .regular)
        name.textColor = isPrimary ? .labelColor : .secondaryLabelColor
        name.setContentHuggingPriority(.required, for: .horizontal)

        let languageLine = NSStackView(views: [code, name])
        languageLine.orientation = .horizontal
        languageLine.alignment = .firstBaseline
        languageLine.spacing = 7

        translationLabel.stringValue = renderedText
        translationLabel.font = .systemFont(ofSize: isPrimary ? 14 : 12, weight: isPrimary ? .medium : .regular)
        translationLabel.textColor = textColor
        translationLabel.maximumNumberOfLines = isPrimary || isExpanded ? 0 : 1
        translationLabel.lineBreakMode = isPrimary || isExpanded ? .byWordWrapping : .byTruncatingTail
        translationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        translationLabel.setAccessibilityLabel("\(translation.language.displayName)译文")
        if !isPrimary {
            translationLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleExpansion)))
        }

        let textStack = NSStackView(views: [languageLine, translationLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = isPrimary ? 5 : 3
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        copyButton.target = self
        copyButton.action = #selector(copyTranslation)
        copyButton.isBordered = false
        copyButton.bezelStyle = .inline
        copyButton.imagePosition = .imageOnly
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制译文")
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.isEnabled = translation.status == .success && !(translation.text ?? "").isEmpty
        copyButton.setAccessibilityLabel("复制\(translation.language.displayName)译文")
        copyButton.setContentHuggingPriority(.required, for: .horizontal)

        let trailingStack = NSStackView()
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 3

        if !isPrimary {
            let expandButton = NSButton()
            expandButton.target = self
            expandButton.action = #selector(toggleExpansion)
            expandButton.isBordered = false
            expandButton.bezelStyle = .inline
            expandButton.imagePosition = .imageOnly
            expandButton.image = NSImage(
                systemSymbolName: isExpanded ? "chevron.up" : "chevron.down",
                accessibilityDescription: isExpanded ? "收起译文" : "展开译文"
            )
            expandButton.contentTintColor = .tertiaryLabelColor
            expandButton.setAccessibilityLabel(isExpanded ? "收起\(translation.language.displayName)译文" : "展开\(translation.language.displayName)译文")
            trailingStack.addArrangedSubview(expandButton)
        }
        trailingStack.addArrangedSubview(copyButton)

        let content = NSStackView(views: [textStack, trailingStack])
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(
            top: isPrimary ? 10 : 7,
            left: 10,
            bottom: isPrimary ? 10 : 7,
            right: 8
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingStack.widthAnchor.constraint(greaterThanOrEqualToConstant: isPrimary ? 24 : 50),
        ])
    }

    private var renderedText: String {
        switch translation.status {
        case .loading:
            return "正在翻译…"
        case .success:
            return translation.text ?? "暂无译文"
        case .failure(let message):
            return message
        }
    }

    private var textColor: NSColor {
        switch translation.status {
        case .failure:
            return .systemRed
        case .loading:
            return .secondaryLabelColor
        case .success:
            return isPrimary ? .labelColor : .secondaryLabelColor
        }
    }

    @objc private func toggleExpansion() {
        onToggleExpansion?()
    }

    @objc private func copyTranslation() {
        guard copyService.copy(translation) else { return }
        resetCopyWorkItem?.cancel()
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "复制完成")
        copyButton.contentTintColor = .systemGreen
        copyButton.setAccessibilityLabel("复制完成")

        let item = DispatchWorkItem { [weak self] in
            self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制译文")
            self?.copyButton.contentTintColor = .secondaryLabelColor
            self?.copyButton.setAccessibilityLabel("复制\(self?.translation.language.displayName ?? "")译文")
        }
        resetCopyWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    func cancelCopyFeedback() {
        resetCopyWorkItem?.cancel()
        resetCopyWorkItem = nil
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制译文")
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.setAccessibilityLabel("复制\(translation.language.displayName)译文")
    }
}
