import Foundation

struct TutorLessonPlanner {
    let packs: [any LessonContentPack]

    init(packs: [any LessonContentPack] = BuiltInLessonPacks.all) {
        self.packs = packs
    }

    func plan(
        from state: LearningDisplayState,
        primaryLanguage: LearningLanguage,
        level: LearnerLevel
    ) -> MicroLesson? {
        guard let translation = state.phraseTranslations.first(where: {
            $0.language == primaryLanguage
                && $0.status == .success
                && !($0.text ?? "").isEmpty
        })?.text,
        let pack = packs.first(where: { $0.language == primaryLanguage }) else {
            return nil
        }

        let candidates = pack.candidates(
            sourcePhrase: state.sourcePhrase,
            primaryTranslation: translation,
            vocabularyCards: state.vocabularyCards,
            level: level
        )
        .filter(\.hasEvidence)
        .sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.point.id < rhs.point.id
            }
            return lhs.priority > rhs.priority
        }

        let selected = Array(candidates.prefix(4))
        guard !selected.isEmpty else { return nil }

        let mapPairs = deduplicated(
            selected.compactMap(\.mapPair),
            key: \.evidenceID
        )
        let points = deduplicated(selected.map(\.point), key: \.id)
        return MicroLesson(
            primaryLanguage: primaryLanguage,
            mapPairs: mapPairs,
            learningPoints: points,
            explanation: selected.compactMap(\.explanation).first,
            practice: selected.compactMap(\.practice).first,
            reviewCandidates: points
        )
    }

    private func deduplicated<Value>(
        _ values: [Value],
        key: (Value) -> String
    ) -> [Value] {
        var seen = Set<String>()
        return values.filter { seen.insert(key($0)).inserted }
    }
}
