import Cocoa

final class MicroLessonView: NSView {
    private let stack = NSStackView()
    private(set) var renderedLearningPointCount = 0
    private(set) var isSentenceMapVisible = false
    private(set) var isReviewVisible = false
    private var savedPoint: LearningPoint?
    private var practices: [String: MicroPractice] = [:]
    var onSave: ((LearningPoint) -> Void)?
    var onReviewAnswer: ((ReviewItem, Bool) -> Void)?
    private var reviewingItem: ReviewItem?

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(lesson: MicroLesson?, mode: LearningMode) {
        clearContent()
        renderedLearningPointCount = 0
        isSentenceMapVisible = false
        isReviewVisible = false
        guard let lesson else { isHidden = true; return }
        isHidden = false

        if mode == .deep, !lesson.mapPairs.isEmpty {
            isSentenceMapVisible = true
            addFullWidth(section(
                title: "句子拆解",
                color: LinguaTypePalette.compare,
                lines: lesson.mapPairs.map { "\($0.source)  ↔  \($0.target)" }
            ))
        }

        let points = mode == .minimal ? Array(lesson.learningPoints.prefix(1)) : lesson.learningPoints
        if !points.isEmpty {
            renderedLearningPointCount = points.count
            let lines = points.flatMap { point -> [String] in
                var values = [point.targetExpression, point.chineseMeaning]
                if let pattern = point.pattern { values.append(pattern) }
                if let example = point.example { values.append("\(example.target) · \(example.chineseMeaning)") }
                return values
            }
            addFullWidth(section(
                title: "值得记住",
                color: LinguaTypePalette.remember,
                lines: lines
            ))
        }

        if mode == .deep, let explanation = lesson.explanation {
            addFullWidth(section(
                title: explanation.title,
                color: LinguaTypePalette.compare,
                lines: [explanation.body]
            ))
        }

        if let practice = lesson.practice {
            addFullWidth(practiceSection(practice))
        }

        if let point = points.first {
            savedPoint = point
            let button = NSButton(title: "☆ 加入复习", target: self, action: #selector(savePoint(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("save")
            button.isBordered = false
            button.contentTintColor = LinguaTypePalette.review
            button.setAccessibilityLabel("加入复习")
            stack.addArrangedSubview(button)
        }
    }

    func showReview(_ item: ReviewItem) {
        clearContent()
        isHidden = false
        isReviewVisible = true
        reviewingItem = item
        let title = NSTextField(labelWithString: "今日复习")
        title.font = .systemFont(ofSize: 10, weight: .semibold)
        title.textColor = LinguaTypePalette.review
        let expression = NSTextField(wrappingLabelWithString: item.point.targetExpression)
        expression.font = .systemFont(ofSize: 20, weight: .semibold)
        let meaning = NSTextField(wrappingLabelWithString: item.point.chineseMeaning)
        meaning.font = .systemFont(ofSize: 13, weight: .regular)
        meaning.textColor = .secondaryLabelColor
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        let retry = NSButton(title: "还需复习", target: self, action: #selector(answerReview(_:)))
        retry.tag = 0
        let remembered = NSButton(title: "记住了", target: self, action: #selector(answerReview(_:)))
        remembered.tag = 1
        actions.addArrangedSubview(retry)
        actions.addArrangedSubview(remembered)
        [title, expression, meaning, actions].forEach { stack.addArrangedSubview($0) }
    }

    func performReviewAnswer(isCorrect: Bool) {
        guard let item = reviewingItem else { return }
        onReviewAnswer?(item, isCorrect)
    }

    private func clearContent() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        savedPoint = nil
        practices.removeAll()
        reviewingItem = nil
    }

    private func addFullWidth(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func section(title: String, color: NSColor, lines: [String]) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        container.wantsLayer = true
        container.layer?.cornerRadius = 9
        container.layer?.backgroundColor = LinguaTypePalette.surface(for: color).cgColor
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        titleLabel.textColor = color
        container.addArrangedSubview(titleLabel)
        lines.forEach { text in
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
            container.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -20).isActive = true
        }
        return container
    }

    private func practiceSection(_ practice: MicroPractice) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 5
        container.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        container.wantsLayer = true
        container.layer?.cornerRadius = 9
        container.layer?.backgroundColor = LinguaTypePalette.surface(for: LinguaTypePalette.practice).cgColor
        let title = NSTextField(labelWithString: "试一下 · 10 秒")
        title.font = .systemFont(ofSize: 9.5, weight: .semibold)
        title.textColor = LinguaTypePalette.practice
        let prompt = NSTextField(wrappingLabelWithString: practice.prompt)
        prompt.font = .systemFont(ofSize: 12, weight: .medium)
        let choices = NSStackView()
        choices.orientation = .horizontal
        choices.spacing = 6
        practice.choices.forEach { choice in
            let button = NSButton(title: choice, target: self, action: #selector(answerPractice(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(choice)
            button.setAccessibilityLabel("练习选项 \(choice)")
            choices.addArrangedSubview(button)
        }
        container.addArrangedSubview(title)
        container.addArrangedSubview(prompt)
        prompt.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -20).isActive = true
        container.addArrangedSubview(choices)
        practices = Dictionary(uniqueKeysWithValues: practice.choices.map { ($0, practice) })
        return container
    }

    @objc private func savePoint(_ sender: NSButton) {
        guard let point = savedPoint else { return }
        onSave?(point)
    }

    @objc private func answerPractice(_ sender: NSButton) {
        guard let choice = sender.identifier?.rawValue,
              let practice = practices[choice] else { return }
        sender.title = practice.isCorrect(choice: choice) ? "✓ \(choice)" : "再试一次"
    }

    @objc private func answerReview(_ sender: NSButton) {
        performReviewAnswer(isCorrect: sender.tag == 1)
    }
}
