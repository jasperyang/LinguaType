import Cocoa

final class LearningPanelContentView: NSView {
    private let rootStack = NSStackView()
    private let sourceSection = SourceSectionView()
    private let scrollView = NSScrollView()
    private let learnLabel = NSTextField(labelWithString: "LEARN")
    private let vocabularyGrid = VocabularyGridView()
    private let microLessonView = MicroLessonView()
    private let lessonScrollView = NSScrollView()
    private let lessonDocument = NSView()
    private let reviewStore = ReviewStore.shared
    private let headerView: PanelHeaderView
    private let translationSection: TranslationSectionView
    private var scrollHeightConstraint: NSLayoutConstraint?
    private var lessonHeightConstraint: NSLayoutConstraint?
    private var availableContentHeight: CGFloat?
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
    private(set) var usesInternalScrolling = false
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
        updateLessonPresentation()

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

    func setAvailableContentHeight(_ height: CGFloat?) {
        availableContentHeight = height
        updateLessonPresentation()
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
        updateLessonPresentation()
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

        lessonDocument.translatesAutoresizingMaskIntoConstraints = false
        microLessonView.translatesAutoresizingMaskIntoConstraints = false
        lessonDocument.addSubview(microLessonView)
        NSLayoutConstraint.activate([
            microLessonView.leadingAnchor.constraint(equalTo: lessonDocument.leadingAnchor),
            microLessonView.trailingAnchor.constraint(equalTo: lessonDocument.trailingAnchor),
            microLessonView.topAnchor.constraint(equalTo: lessonDocument.topAnchor),
            microLessonView.bottomAnchor.constraint(equalTo: lessonDocument.bottomAnchor),
        ])
        lessonScrollView.documentView = lessonDocument
        lessonScrollView.drawsBackground = false
        lessonScrollView.hasVerticalScroller = false
        lessonScrollView.autohidesScrollers = true
        lessonScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lessonDocument.widthAnchor.constraint(equalTo: lessonScrollView.contentView.widthAnchor),
        ])
        let lessonHeight = lessonScrollView.heightAnchor.constraint(equalToConstant: 1)
        lessonHeight.isActive = true
        lessonHeightConstraint = lessonHeight

        rootStack.addArrangedSubview(headerView)
        rootStack.addArrangedSubview(sourceSection)
        rootStack.addArrangedSubview(translationSection)
        rootStack.addArrangedSubview(lessonScrollView)
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
            lessonScrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            learnLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
        ])
    }

    private func updateLessonPresentation() {
        guard !microLessonView.isHidden else {
            lessonScrollView.isHidden = true
            lessonHeightConstraint?.constant = 1
            usesInternalScrolling = false
            return
        }

        lessonScrollView.isHidden = false
        microLessonView.layoutSubtreeIfNeeded()
        let naturalHeight = max(1, microLessonView.fittingSize.height)
        guard let availableContentHeight else {
            lessonHeightConstraint?.constant = naturalHeight
            lessonScrollView.hasVerticalScroller = false
            usesInternalScrolling = false
            return
        }

        let fixedHeight = headerView.fittingSize.height
            + sourceSection.fittingSize.height
            + translationSection.fittingSize.height
            + rootStack.edgeInsets.top
            + rootStack.edgeInsets.bottom
            + rootStack.spacing * 3
        let displayHeight = max(80, availableContentHeight - fixedHeight)
        let lessonHeight = min(naturalHeight, displayHeight)
        lessonHeightConstraint?.constant = lessonHeight
        usesInternalScrolling = naturalHeight > lessonHeight + 0.5
        lessonScrollView.hasVerticalScroller = usesInternalScrolling
    }
}
