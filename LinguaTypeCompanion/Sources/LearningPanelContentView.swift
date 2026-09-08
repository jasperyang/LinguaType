import Cocoa

final class LearningPanelContentView: NSView {
    private let rootStack = NSStackView()
    private let sourceSection = SourceSectionView()
    private let scrollView = NSScrollView()
    private let learnLabel = NSTextField(labelWithString: "LEARN")
    private let vocabularyGrid = VocabularyGridView()
    private let microLessonView = MicroLessonView()
    private let reviewStore = ReviewStore.shared
    private let headerView: PanelHeaderView
    private let translationSection: TranslationSectionView
    private var scrollHeightConstraint: NSLayoutConstraint?
    private var currentState: LearningDisplayState?
    private var currentSelection: LanguageSelection = .default
    private var currentPinned = false

    private(set) var phraseRows: [NSTextField] = []
    private(set) var vocabularyCardViews: [NSView] = []
    var onSelectionChange: ((LanguageSelection) -> Void)?
    var onTogglePin: (() -> Void)?
    var onLearnerLevelChange: ((LearnerLevel, LearningLanguage) -> Void)?

    var languageButtonTitle: String { headerView.languageButtonTitle }
    var primaryLanguage: LearningLanguage? { translationSection.primaryLanguage }
    var referenceLanguages: [LearningLanguage] { translationSection.referenceLanguages }
    var copyButtonLanguages: [LearningLanguage] { translationSection.copyButtonLanguages }
    var renderedLanguageCodes: [String] { translationSection.renderedLanguageCodes }
    var translationRowSpacing: CGFloat { translationSection.rowSpacing }
    var expandedReference: LearningLanguage? { translationSection.expandedReference }
    var sourceMaximumLines: Int { sourceSection.maximumNumberOfLines }
    var vocabularyColumnCount: Int { vocabularyGrid.columnCount }
    var vocabularyLanguageCodes: [String] { vocabularyGrid.renderedLanguageCodes }
    var isReviewVisible: Bool { microLessonView.isReviewVisible }
    var preferredHeight: CGFloat {
        layoutSubtreeIfNeeded()
        return rootStack.fittingSize.height
    }

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
        currentState = state
        currentSelection = selection
        currentPinned = isPinned
        sourceSection.apply(sourcePhrase: state.sourcePhrase)
        sourceSection.isHidden = false
        translationSection.isHidden = false
        headerView.apply(selection: selection, isPinned: isPinned)
        translationSection.apply(
            translations: state.phraseTranslations,
            selection: selection,
            sourcePhrase: state.sourcePhrase
        )
        phraseRows = translationSection.phraseLabels

        microLessonView.apply(
            lesson: state.lesson,
            mode: LinguaTypePreferences.learningMode()
        )

        let availableWidth = max(0, bounds.width - 28)
        vocabularyGrid.apply(
            cards: state.vocabularyCards,
            selection: selection,
            availableWidth: availableWidth
        )
        vocabularyCardViews = vocabularyGrid.cardViews
        vocabularyGrid.layoutSubtreeIfNeeded()
        let learningHeight = min(300, vocabularyGrid.fittingSize.height)
        scrollHeightConstraint?.constant = max(1, learningHeight)
        let hasLesson = state.lesson != nil
        scrollView.isHidden = hasLesson || vocabularyCardViews.isEmpty
        learnLabel.isHidden = hasLesson || vocabularyCardViews.isEmpty
    }

    func toggleReference(_ language: LearningLanguage) {
        translationSection.toggleReference(language)
        phraseRows = translationSection.phraseLabels
    }

    func copyButton(for language: LearningLanguage) -> NSButton? {
        translationSection.copyButton(for: language)
    }

    func performPinAction() {
        headerView.performPinAction()
    }

    func showReview(
        _ item: ReviewItem,
        onAnswer: @escaping (ReviewItem, Bool) -> Void
    ) {
        sourceSection.isHidden = true
        translationSection.isHidden = true
        learnLabel.isHidden = true
        scrollView.isHidden = true
        microLessonView.onReviewAnswer = onAnswer
        microLessonView.showReview(item)
    }

    func performReviewAnswer(isCorrect: Bool) {
        microLessonView.performReviewAnswer(isCorrect: isCorrect)
    }

    func cancelTransientFeedback() {
        translationSection.cancelCopyFeedback()
    }

    private func wireActions() {
        headerView.onSelectionChange = { [weak self] selection in
            self?.onSelectionChange?(selection)
        }
        headerView.onTogglePin = { [weak self] in
            self?.onTogglePin?()
        }
        headerView.onModeChange = { [weak self] _ in
            guard let self, let state = self.currentState else { return }
            self.apply(
                state,
                selection: self.currentSelection,
                isPinned: self.currentPinned
            )
        }
        headerView.onLearnerLevelChange = { [weak self] level, language in
            self?.onLearnerLevelChange?(level, language)
        }
        microLessonView.onSave = { [weak self] point in
            self?.reviewStore.save(point, now: Date())
        }
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = LinguaTypePalette.panelBackground.cgColor
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        learnLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        learnLabel.textColor = .tertiaryLabelColor

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        vocabularyGrid.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(vocabularyGrid)
        scrollView.documentView = document
        NSLayoutConstraint.activate([
            vocabularyGrid.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            vocabularyGrid.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            vocabularyGrid.topAnchor.constraint(equalTo: document.topAnchor),
            vocabularyGrid.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 1)
        heightConstraint.isActive = true
        scrollHeightConstraint = heightConstraint

        rootStack.addArrangedSubview(headerView)
        rootStack.addArrangedSubview(sourceSection)
        rootStack.addArrangedSubview(translationSection)
        rootStack.addArrangedSubview(microLessonView)
        rootStack.addArrangedSubview(learnLabel)
        rootStack.addArrangedSubview(scrollView)
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            headerView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            sourceSection.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            translationSection.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            microLessonView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            learnLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
        ])
    }
}
