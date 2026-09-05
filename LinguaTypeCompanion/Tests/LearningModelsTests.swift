import Foundation

enum LearningModelsTests {
    static func run() {
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
    }
}
