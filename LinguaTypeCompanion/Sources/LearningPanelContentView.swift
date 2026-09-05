import Cocoa

final class LearningPanelContentView: NSView {
    private let rootStack = NSStackView()
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")
    private let phraseStack = NSStackView()
    private let scrollView = NSScrollView()
    private let vocabularyStack = NSStackView()

    private(set) var phraseRows: [NSTextField] = []
    private(set) var vocabularyCardViews: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ state: LearningDisplayState) {
        sourceLabel.stringValue = state.sourcePhrase
        phraseRows.forEach { phraseStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        phraseRows = state.phraseTranslations.map(makePhraseRow)
        phraseRows.forEach(phraseStack.addArrangedSubview)

        vocabularyCardViews.forEach { vocabularyStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        vocabularyCardViews = state.vocabularyCards.prefix(3).map(makeVocabularyCard)
        vocabularyCardViews.forEach(vocabularyStack.addArrangedSubview)
        scrollView.isHidden = vocabularyCardViews.isEmpty
    }

    private func build() {
        wantsLayer = true
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let title = label("LINGUATYPE · 语言学习", size: 10, weight: .semibold, color: .secondaryLabelColor)
        sourceLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        sourceLabel.textColor = .labelColor
        sourceLabel.maximumNumberOfLines = 2

        phraseStack.orientation = .vertical
        phraseStack.alignment = .leading
        phraseStack.spacing = 6

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

        rootStack.addArrangedSubview(title)
        rootStack.addArrangedSubview(sourceLabel)
        rootStack.addArrangedSubview(phraseStack)
        rootStack.addArrangedSubview(scrollView)
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sourceLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            phraseStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
        ])
    }

    private func makePhraseRow(_ translation: PhraseTranslation) -> NSTextField {
        let value: String
        switch translation.status {
        case .loading: value = "···"
        case .success: value = translation.text ?? "···"
        case .failure(let message): value = message
        }
        return label("\(translation.language.flag)  \(translation.language.displayName)  \(value)", size: 12.5, weight: .regular, color: .labelColor)
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
        box.contentView = stack
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
