import Cocoa

enum MicroLessonViewTests {
    static func run() {
        let view = MicroLessonView()
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
            mapPairs: [SentenceMapPair(source: "在东京生活", target: "東京で生活する", evidenceID: "ja.place-action")],
            learningPoints: [point],
            explanation: WhyExplanation(title: "为什么这么说", body: "日语将地点和动作组合。", evidenceID: "ja.place-action"),
            practice: MicroPractice(id: "practice", prompt: "東京 ___ 生活する", choices: ["で", "に"], correctChoice: "で", successFeedback: "正确", evidenceID: "ja.place-action"),
            reviewCandidates: [point]
        )

        view.apply(lesson: lesson, mode: .minimal)
        Test.expect(
            view.renderedLearningPointCount == 1 && !view.isSentenceMapVisible,
            "minimal mode shows one point without sentence map"
        )
        view.apply(lesson: lesson, mode: .deep)
        Test.expect(
            view.renderedLearningPointCount == 1 && view.isSentenceMapVisible,
            "deep mode shows reliable sentence map"
        )
    }
}
