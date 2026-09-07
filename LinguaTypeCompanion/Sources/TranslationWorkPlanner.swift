import Foundation

struct TranslationWorkPlanner {
    func missingJobs(
        state: LearningDisplayState,
        selection: LanguageSelection,
        generation: UInt64
    ) -> [TranslationJob] {
        let phraseJobs = selection.orderedLanguages.compactMap { language -> TranslationJob? in
            if let row = state.phraseTranslations.first(where: { $0.language == language }),
               row.status == .success {
                return nil
            }
            return TranslationJob(
                generation: generation,
                purpose: .phrase(language: language),
                text: state.sourcePhrase,
                sourceLanguageID: "zh-Hans",
                targetLanguageID: language.rawValue
            )
        }

        let termJobs = state.vocabularyCards.enumerated().flatMap { cardID, card in
            selection.orderedLanguages.compactMap { language -> TranslationJob? in
                guard !card.terms.contains(where: {
                    $0.language == language && !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) else { return nil }
                return TranslationJob(
                    generation: generation,
                    purpose: .term(cardID: cardID, language: language),
                    text: card.source,
                    sourceLanguageID: "zh-Hans",
                    targetLanguageID: language.rawValue
                )
            }
        }

        return phraseJobs + termJobs
    }
}
