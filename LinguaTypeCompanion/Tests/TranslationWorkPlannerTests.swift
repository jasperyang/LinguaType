import Foundation

enum TranslationWorkPlannerTests {
    static func run() {
        let french = PhraseTranslation(language: .french, text: "Bonjour", status: .success)
        let english = PhraseTranslation(language: .english, text: nil, status: .loading)
        let japanese = PhraseTranslation(language: .japanese, text: "こんにちは", status: .success)
        let card = VocabularyCard(
            source: "输入",
            partOfSpeech: "动词",
            chineseSenses: ["录入信息"],
            contextualSense: "录入信息",
            terms: [
                LocalizedTerm(language: .french, term: "saisir", ipa: nil, kana: nil, romanization: nil)
            ],
            status: .partial
        )
        let state = LearningDisplayState(
            sourcePhrase: "输入文字",
            phraseTranslations: [french, english, japanese],
            vocabularyCards: [card],
            phase: .loadingVocabulary
        )
        let selection = LanguageSelection(primary: .french, selected: [.french, .english])

        let jobs = TranslationWorkPlanner().missingJobs(
            state: state,
            selection: selection,
            generation: 7
        )
        Test.expect(
            jobs.map(\.purpose) == [
                .phrase(language: .english),
                .term(cardID: 0, language: .english),
            ],
            "planner schedules only missing work for selected languages"
        )
        Test.expect(
            !jobs.contains { $0.targetLanguageID == "ja" },
            "planner excludes unselected languages"
        )

        var emitted: LearningDisplayState?
        var persisted: LanguageSelection?
        let frenchOnly = LanguageSelection(primary: .french, selected: [.french])
        let coordinator = LearningCoordinator(
            languageSelection: frenchOnly,
            persistSelection: { persisted = $0 }
        )
        coordinator.onUpdate = { emitted = $0 }
        coordinator.commit(text: "今天适合散步")
        Test.expect(
            emitted?.phraseTranslations.map(\.language) == [.french],
            "committed phrase publishes only selected language rows"
        )

        var expanded = frenchOnly
        expanded.setSelected(.english, enabled: true)
        coordinator.setLanguageSelection(expanded)
        Test.expect(
            emitted?.phraseTranslations.map(\.language) == [.french, .english],
            "adding a language publishes its loading row immediately"
        )

        expanded.setPrimary(.english)
        coordinator.setLanguageSelection(expanded)
        Test.expect(
            emitted?.phraseTranslations.map(\.language) == [.english, .french],
            "changing primary language reorders existing rows immediately"
        )
        Test.expect(persisted == expanded, "coordinator persists the latest language selection")
        coordinator.idle()

        var persistedLevel: (LearnerLevel, LearningLanguage)?
        let lessonCoordinator = LearningCoordinator(
            languageSelection: LanguageSelection(primary: .japanese, selected: [.japanese]),
            persistSelection: { _ in },
            learnerLevel: { _ in .beginner },
            persistLearnerLevel: { level, language in persistedLevel = (level, language) }
        )
        let lessonState = LearningDisplayState(
            sourcePhrase: "在东京生活",
            phraseTranslations: [
                PhraseTranslation(
                    language: .japanese,
                    text: "東京で生活する",
                    status: .success
                )
            ],
            vocabularyCards: [],
            phase: .complete
        )
        Test.expect(
            lessonCoordinator.lesson(for: lessonState)?.learningPoints.first?.id == "ja.place-action",
            "coordinator attaches a lesson using the selected primary language"
        )
        lessonCoordinator.setLearnerLevel(.advanced, for: .japanese)
        Test.expect(
            persistedLevel?.0 == .advanced && persistedLevel?.1 == .japanese,
            "coordinator persists a per-language learner level"
        )
    }
}
