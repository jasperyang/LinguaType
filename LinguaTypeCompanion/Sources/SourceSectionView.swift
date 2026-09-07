import Cocoa

final class SourceSectionView: NSView {
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")

    var maximumNumberOfLines: Int { sourceLabel.maximumNumberOfLines }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { nil }

    func apply(sourcePhrase: String) {
        sourceLabel.stringValue = sourcePhrase
        sourceLabel.setAccessibilityLabel("中文原文")
    }

    private func build() {
        let eyebrow = NSTextField(labelWithString: "原文 · 中文")
        eyebrow.font = .systemFont(ofSize: 9.5, weight: .medium)
        eyebrow.textColor = .tertiaryLabelColor

        sourceLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 3
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [eyebrow, sourceLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sourceLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
}
