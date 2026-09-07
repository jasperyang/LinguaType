import Cocoa

final class VocabularyGridView: NSView {
    private let stack = NSStackView()
    private let minimumCardWidth: CGFloat = 232
    private let columnSpacing: CGFloat = 8

    private(set) var cardViews: [NSView] = []
    private(set) var columnCount = 1
    private(set) var renderedLanguageCodes: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { nil }

    func apply(
        cards: [VocabularyCard],
        selection: LanguageSelection,
        availableWidth: CGFloat
    ) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        cardViews.removeAll()
        renderedLanguageCodes.removeAll()

        let visibleCards = Array(cards.prefix(3))
        columnCount = availableWidth >= minimumCardWidth * 2 + columnSpacing ? 2 : 1
        let cardWidth = columnCount == 2
            ? (availableWidth - columnSpacing) / 2
            : availableWidth

        for start in stride(from: 0, to: visibleCards.count, by: columnCount) {
            let end = min(start + columnCount, visibleCards.count)
            let rowCards = visibleCards[start..<end].map {
                makeCard($0, selection: selection)
            }
            cardViews.append(contentsOf: rowCards)

            let row = NSStackView(views: rowCards)
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fill
            row.spacing = columnSpacing
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            rowCards.forEach {
                $0.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
            }
            if rowCards.count == columnCount, let first = rowCards.first {
                rowCards.dropFirst().forEach {
                    $0.heightAnchor.constraint(equalTo: first.heightAnchor).isActive = true
                }
            }
        }
    }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeCard(
        _ card: VocabularyCard,
        selection: LanguageSelection
    ) -> NSView {
        let cardView = NSView()
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 8
        cardView.layer?.borderWidth = 0
        cardView.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.18)
            .cgColor

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 5
        content.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        content.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.alignment = .firstBaseline
        heading.spacing = 6
        let source = label(card.source, size: 13, weight: .semibold, color: .labelColor, lines: 1)
        heading.addArrangedSubview(source)
        if let partOfSpeech = card.partOfSpeech, !partOfSpeech.isEmpty {
            let part = label(partOfSpeech, size: 9.5, weight: .medium, color: .tertiaryLabelColor, lines: 1)
            heading.addArrangedSubview(part)
        }
        content.addArrangedSubview(heading)

        if let contextual = card.contextualSense, !contextual.isEmpty {
            let context = label(
                "当前语境：\(contextual)",
                size: 10.5,
                weight: .medium,
                color: .controlAccentColor,
                lines: 2
            )
            content.addArrangedSubview(context)
            context.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -20).isActive = true
        }

        let selectedTerms = selection.orderedLanguages.compactMap { language in
            card.terms.first { $0.language == language }
        }
        for term in selectedTerms {
            renderedLanguageCodes.append(term.language.shortCode)
            let row = makeTermRow(term, isPrimary: term.language == selection.primary)
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -20).isActive = true
        }

        if !card.chineseSenses.isEmpty {
            let definition = label(
                "释义  \(card.chineseSenses.prefix(2).joined(separator: "；"))",
                size: 9.5,
                weight: .regular,
                color: .tertiaryLabelColor,
                lines: 2
            )
            content.addArrangedSubview(definition)
            definition.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -20).isActive = true
        }

        cardView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            content.topAnchor.constraint(equalTo: cardView.topAnchor),
            content.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])
        return cardView
    }

    private func makeTermRow(_ term: LocalizedTerm, isPrimary: Bool) -> NSView {
        let code = label(
            term.language.shortCode,
            size: 9,
            weight: .semibold,
            color: isPrimary ? .controlAccentColor : .tertiaryLabelColor,
            lines: 1
        )
        code.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        code.setContentHuggingPriority(.required, for: .horizontal)

        let pronunciation: String
        if term.language == .japanese {
            pronunciation = [term.kana, term.romanization]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        } else {
            pronunciation = term.ipa ?? ""
        }
        let detail = pronunciation.isEmpty ? term.term : "\(term.term)  \(pronunciation)"
        let value = label(
            detail,
            size: isPrimary ? 10.5 : 10,
            weight: isPrimary ? .semibold : .regular,
            color: isPrimary ? .labelColor : .secondaryLabelColor,
            lines: 2
        )
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [code, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 7
        return row
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        lines: Int
    ) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}
