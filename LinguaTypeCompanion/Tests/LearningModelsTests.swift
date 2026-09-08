import Foundation

enum LearningModelsTests {
    static func run() {
        testLearningPreferences()

        Test.expect(
            LearningLanguage.displayOrder == [.french, .english, .japanese],
            "loading results always use French, English, Japanese order"
        )

        let state = LearningDisplayState.loading(sourcePhrase: "今天适合散步")
        Test.expect(
            state.phraseTranslations.map(\.language) == [.french, .english, .japanese],
            "loading state exposes all three translation rows"
        )
        Test.expect(
            state.phraseTranslations.allSatisfy { $0.status == .loading && $0.text == nil },
            "loading rows never fabricate translated text"
        )
        Test.expect(state.vocabularyCards.isEmpty, "loading state starts without fabricated vocabulary")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "LinguaType.dictionaryLookupEnabled")
        Test.expect(
            LinguaTypePreferences.isDictionaryLookupEnabled,
            "online dictionary lookup defaults to enabled"
        )
        LinguaTypePreferences.setDictionaryLookupEnabled(false)
        Test.expect(
            !LinguaTypePreferences.isDictionaryLookupEnabled,
            "online dictionary lookup can be paused"
        )
        LinguaTypePreferences.setDictionaryLookupEnabled(true)

        var emitted: LearningDisplayState?
        let coordinator = LearningCoordinator.shared
        coordinator.onUpdate = { emitted = $0 }
        coordinator.commit(text: "今天的天气很适合散步")
        Test.expect(
            emitted?.phraseTranslations.map(\.language) == [.french, .english, .japanese],
            "a committed phrase immediately publishes three translation rows"
        )
        Test.expect(
            emitted?.vocabularyCards.map(\.source) == ["天气", "适合", "散步"],
            "a committed phrase immediately publishes up to three vocabulary cards"
        )
        coordinator.idle()
    }

    private static func testLearningPreferences() {
        let suiteName = "LinguaType.LearningModelsTests.preferences"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        Test.expect(
            LinguaTypePreferences.learningMode(defaults: defaults) == .minimal,
            "minimal mode is the default"
        )
        Test.expect(
            LinguaTypePreferences.learnerLevel(for: .japanese, defaults: defaults) == .beginner,
            "each language starts at beginner level"
        )

        LinguaTypePreferences.setLearningMode(.deep, defaults: defaults)
        LinguaTypePreferences.setLearnerLevel(.advanced, for: .japanese, defaults: defaults)

        Test.expect(
            LinguaTypePreferences.learningMode(defaults: defaults) == .deep
                && LinguaTypePreferences.learnerLevel(for: .japanese, defaults: defaults) == .advanced
                && LinguaTypePreferences.learnerLevel(for: .french, defaults: defaults) == .beginner,
            "mode and learner levels persist independently"
        )

        let point = LearningPoint(
            id: "ja.place-action",
            language: .japanese,
            kind: .pattern,
            targetExpression: "東京で生活する",
            pronunciation: "とうきょうで せいかつする",
            chineseMeaning: "在东京生活",
            pattern: "地点 + で + 动作",
            example: nil,
            evidenceID: "ja.place-action"
        )
        let lesson = MicroLesson(
            primaryLanguage: .japanese,
            mapPairs: [],
            learningPoints: [point],
            explanation: nil,
            practice: nil,
            reviewCandidates: [point]
        )
        Test.expect(
            lesson.learningPoints == [point] && lesson.mapPairs.isEmpty && lesson.practice == nil,
            "lesson model represents available teaching blocks without fabricating others"
        )
    }
}
