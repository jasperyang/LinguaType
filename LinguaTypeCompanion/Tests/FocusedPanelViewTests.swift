import Cocoa

private final class FocusedPanelClipboard: TranslationClipboardWriting {
    var values: [String] = []
    func write(_ text: String) { values.append(text) }
}

enum FocusedPanelViewTests {
    static func run() {
        testLanguagePickerRules()
        testFocusedTranslationPresentation()
        testReferenceExpansionAndCopy()
    }

    private static func testLanguagePickerRules() {
        let picker = LanguagePickerView(selection: .default)
        var emitted: LanguageSelection?
        picker.onChange = { emitted = $0 }

        picker.setSelected(.japanese, enabled: false)
        Test.expect(
            emitted?.selected == [.french, .english],
            "language picker checkbox controls reference visibility"
        )

        picker.makePrimary(.english)
        Test.expect(
            emitted?.primary == .english && emitted?.selected.contains(.english) == true,
            "language picker name action selects the primary language"
        )

        picker.setSelected(.english, enabled: false)
        Test.expect(
            emitted?.selected.contains(.english) == true,
            "language picker cannot uncheck the primary language"
        )
    }

    private static func testFocusedTranslationPresentation() {
        let clipboard = FocusedPanelClipboard()
        let view = LearningPanelContentView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 480),
            clipboard: clipboard
        )
        view.apply(fixture(source: "第一句"), selection: .default, isPinned: false)
        view.layoutSubtreeIfNeeded()

        Test.expect(
            view.languageButtonTitle == "法语",
            "collapsed language control shows only the primary language"
        )
        Test.expect(
            !view.languageButtonTitle.contains("+"),
            "collapsed language control omits selected-language count"
        )
        Test.expect(view.primaryLanguage == .french, "French renders as the primary translation")
        Test.expect(
            view.referenceLanguages == [.english, .japanese],
            "English and Japanese render as references"
        )
        Test.expect(
            view.copyButtonLanguages == [.french, .english, .japanese],
            "each visible translation has a copy button"
        )
        Test.expect(
            view.renderedLanguageCodes == ["FR", "EN", "JP"],
            "panel uses language codes instead of flags"
        )
    }

    private static func testReferenceExpansionAndCopy() {
        let clipboard = FocusedPanelClipboard()
        let view = LearningPanelContentView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 480),
            clipboard: clipboard
        )
        view.apply(fixture(source: "第一句"), selection: .default, isPinned: false)

        view.toggleReference(.english)
        Test.expect(view.expandedReference == .english, "reference language expands on demand")
        view.toggleReference(.japanese)
        Test.expect(
            view.expandedReference == .japanese,
            "expanding a reference collapses the previous language"
        )
        view.apply(fixture(source: "第二句"), selection: .default, isPinned: false)
        Test.expect(view.expandedReference == nil, "new source phrase collapses reference languages")

        view.copyButton(for: .french)?.performClick(nil)
        Test.expect(
            clipboard.values == ["Traduction française complète"],
            "copy button writes only its complete translation"
        )
    }

    private static func fixture(source: String) -> LearningDisplayState {
        LearningDisplayState(
            sourcePhrase: source,
            phraseTranslations: [
                PhraseTranslation(language: .french, text: "Traduction française complète", status: .success),
                PhraseTranslation(language: .english, text: "Complete English translation", status: .success),
                PhraseTranslation(language: .japanese, text: "完全な日本語訳", status: .success),
            ],
            vocabularyCards: [],
            phase: .complete
        )
    }
}
