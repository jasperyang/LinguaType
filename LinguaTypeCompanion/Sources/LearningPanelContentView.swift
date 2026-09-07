import Cocoa

final class LearningPanelContentView: NSView {
    private let rootStack = NSStackView()
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")
    private let scrollView = NSScrollView()
    private let vocabularyStack = NSStackView()
    private let headerView: PanelHeaderView
    private let translationSection: TranslationSectionView

    private(set) var phraseRows: [NSTextField] = []
    private(set) var vocabularyCardViews: [NSView] = []
    var onSelectionChange: ((LanguageSelection) -> Void)?
    var onTogglePin: (() -> Void)?

    var languageButtonTitle: String { headerView.languageButtonTitle }
    var primaryLanguage: LearningLanguage? { translationSection.primaryLanguage }
    var referenceLanguages: [LearningLanguage] { translationSection.referenceLanguages }
    var copyButtonLanguages: [LearningLanguage] { translationSection.copyButtonLanguages }
    var renderedLanguageCodes: [String] { translationSection.renderedLanguageCodes }
    var expandedReference: LearningLanguage? { translationSection.expandedReference }

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, clipboard: SystemTranslationClipboard())
    }

    init(frame frameRect: NSRect, clipboard: TranslationClipboardWriting) {
        headerView = PanelHeaderView(selection: .default)
        translationSection = TranslationSectionView(
            copyService: TranslationCopyService(clipboard: clipboard)
        )
        super.init(frame: frameRect)
        wireActions()
        build()
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ state: LearningDisplayState) {
        apply(state, selection: .default, isPinned: false)
    }

    func apply(
        _ state: LearningDisplayState,
        selection: LanguageSelection,
        isPinned: Bool
    ) {
        sourceLabel.stringValue = state.sourcePhrase
        headerView.apply(selection: selection, isPinned: isPinned)
        translationSection.apply(
            translations: state.phraseTranslations,
            selection: selection,
            sourcePhrase: state.sourcePhrase
        )
        phraseRows = translationSection.phraseLabels

        vocabularyCardViews.forEach { vocabularyStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        vocabularyCardViews = state.vocabularyCards.prefix(3).map(makeVocabularyCard)
        vocabularyCardViews.forEach(vocabularyStack.addArrangedSubview)
        scrollView.isHidden = vocabularyCardViews.isEmpty
    }

    func toggleReference(_ language: LearningLanguage) {
        translationSection.toggleReference(language)
        phraseRows = translationSection.phraseLabels
    }

    func copyButton(for language: LearningLanguage) -> NSButton? {
        translationSection.copyButton(for: language)
    }

    private func wireActions() {
        headerView.onSelectionChange = { [weak self] selection in
            self?.onSelectionChange?(selection)
        }
        headerView.onTogglePin = { [weak self] in
            self?.onTogglePin?()
        }
    }

    private func build() {
        wantsLayer = true
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        sourceLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        sourceLabel.textColor = .labelColor
        sourceLabel.maximumNumberOfLines = 2

        vocabularyStack.orientation = .vertical
        vocabularyStack.alignment = .leading
        vocabularyStack.spacing = 7
        vocabularyStack.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(vocabularyStack)
        scrollView.documentView = document
        NSLayoutConstraint.activate([
            vocabularyStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            vocabularyStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            vocabularyStack.topAnchor.constraint(equalTo: document.topAnchor),
            vocabularyStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true

        rootStack.addArrangedSubview(headerView)
        rootStack.addArrangedSubview(sourceLabel)
        rootStack.addArrangedSubview(translationSection)
        rootStack.addArrangedSubview(scrollView)
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            sourceLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            translationSection.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
        ])
    }

    private func makeVocabularyCard(_ card: VocabularyCard) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.55)
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.28)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 9, bottom: 8, right: 9)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = [card.source, card.partOfSpeech].compactMap { $0 }.joined(separator: "  ·  ")
        stack.addArrangedSubview(label(heading, size: 12.5, weight: .bold, color: .labelColor))
        if !card.chineseSenses.isEmpty {
            stack.addArrangedSubview(label(card.chineseSenses.prefix(3).joined(separator: "；"), size: 11.5, weight: .regular, color: .secondaryLabelColor))
        }
        if let contextual = card.contextualSense {
            stack.addArrangedSubview(label("本句含义：\(contextual)", size: 10.5, weight: .medium, color: .systemIndigo))
        }
        for term in card.terms.sorted(by: { languageIndex($0.language) < languageIndex($1.language) }) {
            let pronunciation: String
            if term.language == .japanese {
                pronunciation = [term.kana, term.romanization].compactMap { $0 }.joined(separator: " · ")
            } else {
                pronunciation = term.ipa ?? ""
            }
            let suffix = pronunciation.isEmpty ? "" : "  \(pronunciation)"
            stack.addArrangedSubview(label("\(term.language.flag)  \(term.term)\(suffix)", size: 10.5, weight: .regular, color: .labelColor))
        }
        let contentView = box.contentView!
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 492).isActive = true
        return box
    }

    private func languageIndex(_ language: LearningLanguage) -> Int {
        LearningLanguage.displayOrder.firstIndex(of: language) ?? .max
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.maximumNumberOfLines = 3
        return label
    }
}
