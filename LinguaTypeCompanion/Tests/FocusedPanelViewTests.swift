import Cocoa

private final class FocusedPanelClipboard: TranslationClipboardWriting {
    var values: [String] = []
    func write(_ text: String) { values.append(text) }
}

enum FocusedPanelViewTests {
    static func run() {
        testLanguagePickerRules()
        testLanguagePickerLearnerLevel()
        testFocusedTranslationPresentation()
        testReferenceExpansionAndCopy()
        testSourceAndVocabularyHierarchy()
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

    private static func testLanguagePickerLearnerLevel() {
        let picker = LanguagePickerView(selection: .default)
        var emitted: (LearnerLevel, LearningLanguage)?
        picker.onLearnerLevelChange = { level, language in emitted = (level, language) }
        picker.setLearnerLevel(.advanced, for: .japanese)
        Test.expect(
            emitted?.0 == .advanced && emitted?.1 == .japanese,
            "language picker exposes a learner level for each selected language"
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

    private static func testSourceAndVocabularyHierarchy() {
        let view = LearningPanelContentView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 540)
        )
        let longSense = "用于描述在当前语境里正在执行的动作，同时说明这个词在完整句子中的具体使用方式。"
        let terms = [
            LocalizedTerm(language: .french, term: "développer", ipa: "/de.və.lɔ.pe/", kana: nil, romanization: nil),
            LocalizedTerm(language: .english, term: "develop", ipa: "/dɪˈveləp/", kana: nil, romanization: nil),
            LocalizedTerm(language: .japanese, term: "開発する", ipa: nil, kana: "かいはつする", romanization: "kaihatsu suru"),
        ]
        let cards = ["开发", "输入", "翻译"].map {
            VocabularyCard(
                source: $0,
                partOfSpeech: "动词",
                chineseSenses: [longSense, "把想法或功能逐步实现并投入使用。"],
                contextualSense: "本句表示正在制作这款实时语言学习工具",
                terms: terms,
                status: .complete
            )
        }
        let state = LearningDisplayState(
            sourcePhrase: "这是一个很长的中文原文，用来确认原文区域最多显示三行，并且不会继续抢占主学习语言的视觉位置。",
            phraseTranslations: fixture(source: "占位").phraseTranslations,
            vocabularyCards: cards,
            phase: .complete
        )
        view.apply(state, selection: .default, isPinned: false)
        view.layoutSubtreeIfNeeded()

        Test.expect(view.sourceMaximumLines == 3, "source area is compact but readable")
        Test.expect(view.vocabularyColumnCount == 2, "520-point panel uses a two-column vocabulary grid")
        Test.expect(view.vocabularyCardViews.count == 3, "panel shows up to three vocabulary cards")
        Test.expect(
            view.vocabularyLanguageCodes.allSatisfy { ["FR", "EN", "JP"].contains($0) },
            "vocabulary uses language codes"
        )
        Test.expect(
            view.vocabularyCardViews.allSatisfy { ($0.layer?.borderWidth ?? 0) == 0 },
            "vocabulary cards avoid strong borders"
        )
        let textFits = view.vocabularyCardViews.allSatisfy { card in
            card.descendants.compactMap { $0 as? NSTextField }.allSatisfy { field in
                card.bounds.insetBy(dx: -0.5, dy: -0.5)
                    .contains(card.convert(field.bounds, from: field))
            }
        }
        Test.expect(textFits, "long vocabulary content stays inside each card")

        let frenchOnly = LanguageSelection(primary: .french, selected: [.french])
        view.apply(state, selection: frenchOnly, isPinned: false)
        Test.expect(
            Set(view.vocabularyLanguageCodes) == ["FR"],
            "vocabulary equivalents follow the selected languages"
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

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
