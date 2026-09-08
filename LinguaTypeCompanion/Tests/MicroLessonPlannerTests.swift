import Foundation

private struct FixtureLessonPack: LessonContentPack {
    let language: LearningLanguage
    let emitted: [LessonCandidate]

    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        vocabularyCards: [VocabularyCard],
        level: LearnerLevel
    ) -> [LessonCandidate] {
        emitted
    }
}

enum MicroLessonPlannerTests {
    static func run() {
        testJapaneseRuleCreatesReliableMapAndPractice()
        testFrenchAndEnglishRulesHaveIndependentEvidence()
        testLevelChangesEligibleTeachingPoint()
        testUnsupportedTextDoesNotCreateLesson()
        testPlannerCapsTeachingPointsAndChecksPractice()
    }

    private static func testJapaneseRuleCreatesReliableMapAndPractice() {
        let lesson = TutorLessonPlanner().plan(
            from: state(
                source: "在东京生活",
                primary: .japanese,
                translation: "東京で生活する"
            ),
            primaryLanguage: .japanese,
            level: .beginner
        )

        Test.expect(
            lesson?.mapPairs == [
                SentenceMapPair(
                    source: "在东京生活",
                    target: "東京で生活する",
                    evidenceID: "ja.place-action"
                )
            ],
            "Japanese place-action map has local rule evidence"
        )
        Test.expect(
            lesson?.practice?.isCorrect(choice: "で") == true
                && lesson?.practice?.isCorrect(choice: "に") == false,
            "Japanese practice accepts only the evidence-backed choice"
        )
    }

    private static func testFrenchAndEnglishRulesHaveIndependentEvidence() {
        let planner = TutorLessonPlanner()
        let french = planner.plan(
            from: state(
                source: "在巴黎生活",
                primary: .french,
                translation: "Je vis à Paris."
            ),
            primaryLanguage: .french,
            level: .beginner
        )
        let english = planner.plan(
            from: state(
                source: "在伦敦工作",
                primary: .english,
                translation: "I work in London."
            ),
            primaryLanguage: .english,
            level: .beginner
        )

        Test.expect(
            french?.learningPoints.first?.evidenceID == "fr.place-activity"
                && english?.learningPoints.first?.evidenceID == "en.place-activity",
            "French and English use their own local teaching evidence"
        )
    }

    private static func testLevelChangesEligibleTeachingPoint() {
        let state = state(
            source: "在东京生活",
            primary: .japanese,
            translation: "東京で生活する"
        )
        let planner = TutorLessonPlanner()
        let beginner = planner.plan(
            from: state,
            primaryLanguage: .japanese,
            level: .beginner
        )
        let advanced = planner.plan(
            from: state,
            primaryLanguage: .japanese,
            level: .advanced
        )

        Test.expect(
            beginner?.learningPoints.first?.id == "ja.place-action"
                && advanced?.learningPoints.first?.id == "ja.life-verb",
            "learner level changes eligible Japanese teaching content"
        )
    }

    private static func testUnsupportedTextDoesNotCreateLesson() {
        let lesson = TutorLessonPlanner().plan(
            from: state(
                source: "任意句子",
                primary: .english,
                translation: "Arbitrary sentence"
            ),
            primaryLanguage: .english,
            level: .advanced
        )

        Test.expect(
            lesson == nil,
            "unsupported input does not invent mapping, explanation, or practice"
        )
    }

    private static func testPlannerCapsTeachingPointsAndChecksPractice() {
        let candidates = (0..<5).map { index in
            LessonCandidate(
                point: LearningPoint(
                    id: "fixture-\(index)",
                    language: .english,
                    kind: .expression,
                    targetExpression: "expression \(index)",
                    pronunciation: nil,
                    chineseMeaning: "释义 \(index)",
                    pattern: nil,
                    example: nil,
                    evidenceID: "fixture-\(index)"
                ),
                mapPair: nil,
                explanation: nil,
                practice: nil,
                priority: index
            )
        }
        let planner = TutorLessonPlanner(
            packs: [FixtureLessonPack(language: .english, emitted: candidates)]
        )
        let lesson = planner.plan(
            from: state(source: "测试", primary: .english, translation: "test"),
            primaryLanguage: .english,
            level: .beginner
        )

        Test.expect(
            lesson?.learningPoints.count == 4,
            "planner caps a deep lesson at four teaching points"
        )
    }

    private static func state(
        source: String,
        primary: LearningLanguage,
        translation: String
    ) -> LearningDisplayState {
        LearningDisplayState(
            sourcePhrase: source,
            phraseTranslations: [
                PhraseTranslation(language: primary, text: translation, status: .success)
            ],
            vocabularyCards: [],
            phase: .complete
        )
    }
}
