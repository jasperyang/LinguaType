import Foundation

struct LessonCandidate: Equatable {
    var point: LearningPoint
    var mapPair: SentenceMapPair?
    var explanation: WhyExplanation?
    var practice: MicroPractice?
    var priority: Int
    var eligibleLevels: Set<LearnerLevel>

    init(
        point: LearningPoint,
        mapPair: SentenceMapPair?,
        explanation: WhyExplanation?,
        practice: MicroPractice?,
        priority: Int,
        eligibleLevels: Set<LearnerLevel> = Set(LearnerLevel.allCases)
    ) {
        self.point = point
        self.mapPair = mapPair
        self.explanation = explanation
        self.practice = practice
        self.priority = priority
        self.eligibleLevels = eligibleLevels
    }

    var hasEvidence: Bool {
        !point.evidenceID.isEmpty
            && (mapPair.map { !$0.evidenceID.isEmpty } ?? true)
            && (explanation.map { !$0.evidenceID.isEmpty } ?? true)
            && (practice.map { !$0.evidenceID.isEmpty } ?? true)
    }
}

protocol LessonContentPack {
    var language: LearningLanguage { get }

    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        vocabularyCards: [VocabularyCard],
        level: LearnerLevel
    ) -> [LessonCandidate]
}

struct CuratedLessonContentPack: LessonContentPack {
    struct Rule {
        var sourcePhrase: String
        var targetPhrase: String
        var candidate: LessonCandidate
    }

    let language: LearningLanguage
    let rules: [Rule]

    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        vocabularyCards: [VocabularyCard],
        level: LearnerLevel
    ) -> [LessonCandidate] {
        let source = normalized(sourcePhrase)
        let target = normalized(primaryTranslation)
        return rules.compactMap { rule in
            guard source == normalized(rule.sourcePhrase),
                  target == normalized(rule.targetPhrase),
                  rule.candidate.eligibleLevels.contains(level),
                  rule.candidate.hasEvidence else {
                return nil
            }
            return rule.candidate
        }
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }
}

struct ParameterizedLessonContentPack: LessonContentPack {
    let language: LearningLanguage
    let matcher: TemplateLessonMatcher

    init(
        language: LearningLanguage,
        matcher: TemplateLessonMatcher = .builtIn
    ) {
        self.language = language
        self.matcher = matcher
    }

    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        vocabularyCards _: [VocabularyCard],
        level: LearnerLevel
    ) -> [LessonCandidate] {
        matcher.candidates(
            sourcePhrase: sourcePhrase,
            primaryTranslation: primaryTranslation,
            language: language,
            level: level
        )
    }
}

struct CompositeLessonContentPack: LessonContentPack {
    let language: LearningLanguage
    let packs: [any LessonContentPack]

    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        vocabularyCards: [VocabularyCard],
        level: LearnerLevel
    ) -> [LessonCandidate] {
        packs.flatMap {
            $0.candidates(
                sourcePhrase: sourcePhrase,
                primaryTranslation: primaryTranslation,
                vocabularyCards: vocabularyCards,
                level: level
            )
        }
    }
}

enum BuiltInLessonPacks {
    static let all: [any LessonContentPack] = [
        CompositeLessonContentPack(
            language: .japanese,
            packs: [japanese, ParameterizedLessonContentPack(language: .japanese)]
        ),
        CompositeLessonContentPack(
            language: .french,
            packs: [french, ParameterizedLessonContentPack(language: .french)]
        ),
        CompositeLessonContentPack(
            language: .english,
            packs: [english, ParameterizedLessonContentPack(language: .english)]
        ),
    ]

    static let japanese = CuratedLessonContentPack(
        language: .japanese,
        rules: [
            .init(
                sourcePhrase: "在东京生活",
                targetPhrase: "東京で生活する",
                candidate: LessonCandidate(
                    point: LearningPoint(
                        id: "ja.place-action",
                        language: .japanese,
                        kind: .pattern,
                        targetExpression: "東京で生活する",
                        pronunciation: "とうきょうで せいかつする",
                        chineseMeaning: "在东京生活",
                        pattern: "地点 + で + 动作",
                        example: LearningExample(
                            target: "大阪で働く",
                            chineseMeaning: "在大阪工作"
                        ),
                        evidenceID: "ja.place-action"
                    ),
                    mapPair: SentenceMapPair(
                        source: "在东京生活",
                        target: "東京で生活する",
                        evidenceID: "ja.place-action"
                    ),
                    explanation: nil,
                    practice: MicroPractice(
                        id: "ja.place-action.practice",
                        prompt: "“在东京生活”　東京 ___ 生活する",
                        choices: ["で", "に", "を"],
                        correctChoice: "で",
                        successFeedback: "地点后用 で 表示动作发生的场所。",
                        evidenceID: "ja.place-action"
                    ),
                    priority: 100,
                    eligibleLevels: [.beginner, .intermediate]
                )
            ),
            .init(
                sourcePhrase: "在东京生活",
                targetPhrase: "東京で生活する",
                candidate: LessonCandidate(
                    point: LearningPoint(
                        id: "ja.life-verb",
                        language: .japanese,
                        kind: .expression,
                        targetExpression: "生活する",
                        pronunciation: "せいかつする",
                        chineseMeaning: "生活、过日子",
                        pattern: nil,
                        example: LearningExample(
                            target: "海外で生活する",
                            chineseMeaning: "在海外生活"
                        ),
                        evidenceID: "ja.life-verb"
                    ),
                    mapPair: SentenceMapPair(
                        source: "生活",
                        target: "生活する",
                        evidenceID: "ja.life-verb"
                    ),
                    explanation: nil,
                    practice: nil,
                    priority: 100,
                    eligibleLevels: [.advanced]
                )
            ),
        ]
    )

    static let french = CuratedLessonContentPack(
        language: .french,
        rules: [
            .init(
                sourcePhrase: "在巴黎生活",
                targetPhrase: "Je vis à Paris.",
                candidate: LessonCandidate(
                    point: LearningPoint(
                        id: "fr.place-activity",
                        language: .french,
                        kind: .pattern,
                        targetExpression: "vivre à Paris",
                        pronunciation: "/vivʁ a paʁi/",
                        chineseMeaning: "在巴黎生活",
                        pattern: "vivre à + 地点",
                        example: LearningExample(
                            target: "Je travaille à Lyon.",
                            chineseMeaning: "我在里昂工作。"
                        ),
                        evidenceID: "fr.place-activity"
                    ),
                    mapPair: SentenceMapPair(
                        source: "在巴黎生活",
                        target: "Je vis à Paris",
                        evidenceID: "fr.place-activity"
                    ),
                    explanation: nil,
                    practice: MicroPractice(
                        id: "fr.place-activity.practice",
                        prompt: "“在巴黎生活”　Je vis ___ Paris.",
                        choices: ["à", "de", "en"],
                        correctChoice: "à",
                        successFeedback: "城市前常用 à 表示地点。",
                        evidenceID: "fr.place-activity"
                    ),
                    priority: 100
                )
            ),
        ]
    )

    static let english = CuratedLessonContentPack(
        language: .english,
        rules: [
            .init(
                sourcePhrase: "在伦敦工作",
                targetPhrase: "I work in London.",
                candidate: LessonCandidate(
                    point: LearningPoint(
                        id: "en.place-activity",
                        language: .english,
                        kind: .pattern,
                        targetExpression: "work in London",
                        pronunciation: "/wɜːk ɪn ˈlʌndən/",
                        chineseMeaning: "在伦敦工作",
                        pattern: "work in + 地点",
                        example: LearningExample(
                            target: "I study in Tokyo.",
                            chineseMeaning: "我在东京学习。"
                        ),
                        evidenceID: "en.place-activity"
                    ),
                    mapPair: SentenceMapPair(
                        source: "在伦敦工作",
                        target: "work in London",
                        evidenceID: "en.place-activity"
                    ),
                    explanation: nil,
                    practice: MicroPractice(
                        id: "en.place-activity.practice",
                        prompt: "“在伦敦工作”　I work ___ London.",
                        choices: ["in", "at", "to"],
                        correctChoice: "in",
                        successFeedback: "城市前常用 in 表示所在地点。",
                        evidenceID: "en.place-activity"
                    ),
                    priority: 100
                )
            ),
        ]
    )
}
