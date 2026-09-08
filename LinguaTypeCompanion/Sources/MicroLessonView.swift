import Cocoa

final class MicroLessonView: NSView {
    private let stack = NSStackView()
    private(set) var renderedLearningPointCount = 0
    private(set) var isSentenceMapVisible = false
    private var savedPoint: LearningPoint?
    private var practices: [String: MicroPractice] = [:]
    var onSave: ((LearningPoint) -> Void)?

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
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        renderedLearningPointCount = 0
        isSentenceMapVisible = false
        savedPoint = nil
        practices.removeAll()
        guard let lesson else { isHidden = true; return }
        isHidden = false

        if mode == .deep, !lesson.mapPairs.isEmpty {
            isSentenceMapVisible = true
            stack.addArrangedSubview(section(
                title: "句子拆解",
                color: NSColor(calibratedRed: 0.64, green: 0.59, blue: 0.94, alpha: 1),
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
            stack.addArrangedSubview(section(
                title: "值得记住",
                color: NSColor(calibratedRed: 0.91, green: 0.75, blue: 0.42, alpha: 1),
                lines: lines
            ))
        }

        if mode == .deep, let explanation = lesson.explanation {
            stack.addArrangedSubview(section(
                title: explanation.title,
                color: NSColor(calibratedRed: 0.64, green: 0.59, blue: 0.94, alpha: 1),
                lines: [explanation.body]
            ))
        }

        if let practice = lesson.practice {
            stack.addArrangedSubview(practiceSection(practice))
        }

        if let point = points.first {
            savedPoint = point
            let button = NSButton(title: "☆ 加入复习", target: self, action: #selector(savePoint(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("save")
            button.isBordered = false
            button.contentTintColor = NSColor(calibratedRed: 0.86, green: 0.57, blue: 0.67, alpha: 1)
            button.setAccessibilityLabel("加入复习")
            stack.addArrangedSubview(button)
        }
    }

    private func section(title: String, color: NSColor, lines: [String]) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
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
        }
        return container
    }

    private func practiceSection(_ practice: MicroPractice) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 5
        let title = NSTextField(labelWithString: "试一下 · 10 秒")
        title.font = .systemFont(ofSize: 9.5, weight: .semibold)
        title.textColor = NSColor(calibratedRed: 0.42, green: 0.83, blue: 0.65, alpha: 1)
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
}
