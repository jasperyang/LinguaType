import Foundation

struct LessonPlace: Equatable {
    let source: String
    let target: [LearningLanguage: String]

    static let tokyo = LessonPlace(
        source: "东京",
        target: [.japanese: "東京", .french: "Tokyo", .english: "Tokyo"]
    )
    static let paris = LessonPlace(
        source: "巴黎",
        target: [.japanese: "パリ", .french: "Paris", .english: "Paris"]
    )
    static let london = LessonPlace(
        source: "伦敦",
        target: [.japanese: "ロンドン", .french: "Londres", .english: "London"]
    )
    static let osaka = LessonPlace(
        source: "大阪",
        target: [.japanese: "大阪", .french: "Osaka", .english: "Osaka"]
    )
    static let lyon = LessonPlace(
        source: "里昂",
        target: [.japanese: "リヨン", .french: "Lyon", .english: "Lyon"]
    )
}

struct LessonAction: Equatable {
    let source: String
    let target: [LearningLanguage: String]

    static let live = LessonAction(
        source: "生活",
        target: [.japanese: "生活する", .french: "vis", .english: "live"]
    )
    static let work = LessonAction(
        source: "工作",
        target: [.japanese: "働く", .french: "travaille", .english: "work"]
    )
    static let study = LessonAction(
        source: "学习",
        target: [.japanese: "勉強する", .french: "étudie", .english: "study"]
    )
}

struct TemplateLessonMatcher {
    static let builtIn = TemplateLessonMatcher(
        places: [.tokyo, .paris, .london, .osaka, .lyon],
        actions: [.live, .work, .study]
    )

    let places: [LessonPlace]
    let actions: [LessonAction]

    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        language: LearningLanguage,
        level: LearnerLevel
    ) -> [LessonCandidate] {
        guard let match = sourceMatch(for: sourcePhrase),
              let targetPhrase = targetPhrase(
                  place: match.place,
                  action: match.action,
                  language: language
              ),
              normalized(primaryTranslation) == normalized(targetPhrase) else {
            return []
        }

        return [candidate(
            sourcePhrase: normalized(sourcePhrase),
            targetPhrase: targetPhrase,
            place: match.place,
            action: match.action,
            language: language,
            level: level
        )]
        .compactMap { $0 }
    }

    private func sourceMatch(for phrase: String) -> (place: LessonPlace, action: LessonAction)? {
        let source = normalized(phrase)
        for place in places {
            for action in actions where source == "在\(place.source)\(action.source)" {
                return (place, action)
            }
        }
        return nil
    }

    private func targetPhrase(
        place: LessonPlace,
        action: LessonAction,
        language: LearningLanguage
    ) -> String? {
        guard let placeTerm = place.target[language],
              let actionTerm = action.target[language] else { return nil }
        switch language {
        case .japanese:
            return "\(placeTerm)で\(actionTerm)"
        case .french:
            return "Je \(actionTerm) à \(placeTerm)"
        case .english:
            return "I \(actionTerm) in \(placeTerm)"
        }
    }

    private func candidate(
        sourcePhrase: String,
        targetPhrase: String,
        place: LessonPlace,
        action: LessonAction,
        language: LearningLanguage,
        level: LearnerLevel
    ) -> LessonCandidate? {
        guard [.beginner, .intermediate].contains(level),
              let placeTerm = place.target[language],
              let actionTerm = action.target[language] else { return nil }

        let evidenceID = "\(language.rawValue).place-action"
        let practice = practice(
            sourcePhrase: sourcePhrase,
            place: placeTerm,
            action: actionTerm,
            language: language,
            evidenceID: evidenceID
        )
        return LessonCandidate(
            point: LearningPoint(
                id: evidenceID,
                language: language,
                kind: .pattern,
                targetExpression: targetPhrase,
                pronunciation: nil,
                chineseMeaning: sourcePhrase,
                pattern: pattern(for: language),
                example: example(for: language),
                evidenceID: evidenceID
            ),
            mapPair: SentenceMapPair(
                source: sourcePhrase,
                target: targetPhrase,
                evidenceID: evidenceID
            ),
            explanation: nil,
            practice: practice,
            priority: 80,
            eligibleLevels: [.beginner, .intermediate]
        )
    }

    private func pattern(for language: LearningLanguage) -> String {
        switch language {
        case .japanese: "地点 + で + 动作"
        case .french: "Je + 动词 + à + 地点"
        case .english: "I + 动词 + in + 地点"
        }
    }

    private func example(for language: LearningLanguage) -> LearningExample {
        switch language {
        case .japanese:
            LearningExample(target: "大阪で働く", chineseMeaning: "在大阪工作")
        case .french:
            LearningExample(target: "Je travaille à Lyon.", chineseMeaning: "我在里昂工作。")
        case .english:
            LearningExample(target: "I study in Tokyo.", chineseMeaning: "我在东京学习。")
        }
    }

    private func practice(
        sourcePhrase: String,
        place: String,
        action: String,
        language: LearningLanguage,
        evidenceID: String
    ) -> MicroPractice {
        switch language {
        case .japanese:
            MicroPractice(
                id: "\(evidenceID).practice",
                prompt: "“\(sourcePhrase)”　\(place) ___ \(action)",
                choices: ["で", "に", "を"],
                correctChoice: "で",
                successFeedback: "地点后用 で 表示动作发生的场所。",
                evidenceID: evidenceID
            )
        case .french:
            MicroPractice(
                id: "\(evidenceID).practice",
                prompt: "“\(sourcePhrase)”　Je \(action) ___ \(place).",
                choices: ["à", "de", "en"],
                correctChoice: "à",
                successFeedback: "城市前常用 à 表示地点。",
                evidenceID: evidenceID
            )
        case .english:
            MicroPractice(
                id: "\(evidenceID).practice",
                prompt: "“\(sourcePhrase)”　I \(action) ___ \(place).",
                choices: ["in", "at", "to"],
                correctChoice: "in",
                successFeedback: "城市前常用 in 表示所在地点。",
                evidenceID: evidenceID
            )
        }
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }
}
