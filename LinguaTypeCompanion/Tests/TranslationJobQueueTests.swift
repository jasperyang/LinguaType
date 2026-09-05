import Foundation

enum TranslationJobQueueTests {
    static func run() {
        var queue = TranslationJobQueue()
        queue.enqueue(.init(generation: 1, purpose: .definition(cardID: 0, language: .english, senseIndex: 0), text: "a condition", sourceLanguageID: "en", targetLanguageID: "zh-Hans"))
        queue.enqueue(.init(generation: 1, purpose: .term(cardID: 0, language: .japanese), text: "适合", sourceLanguageID: "zh-Hans", targetLanguageID: "ja"))
        queue.enqueue(.init(generation: 1, purpose: .phrase(language: .french), text: "今天适合散步", sourceLanguageID: "zh-Hans", targetLanguageID: "fr"))

        Test.expect(queue.popNext()?.purpose == .phrase(language: .french), "phrase work runs before vocabulary work")
        Test.expect(queue.popNext()?.purpose == .term(cardID: 0, language: .japanese), "term work runs before definition localization")
        Test.expect(queue.popNext()?.purpose == .definition(cardID: 0, language: .english, senseIndex: 0), "definition localization runs last")

        queue.enqueue(.init(generation: 1, purpose: .phrase(language: .english), text: "旧句", sourceLanguageID: "zh-Hans", targetLanguageID: "en"))
        queue.enqueue(.init(generation: 2, purpose: .phrase(language: .japanese), text: "新句", sourceLanguageID: "zh-Hans", targetLanguageID: "ja"))
        queue.discard(olderThan: 2)
        Test.expect(queue.popNext()?.generation == 2 && queue.isEmpty, "new input discards stale translation jobs")
    }
}
