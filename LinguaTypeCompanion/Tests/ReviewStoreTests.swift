import Foundation

enum ReviewStoreTests {
    static func run() {
        testSaveDeduplicatesAndPersists()
        testReviewIntervalsAdvanceAndReset()
    }

    private static func testSaveDeduplicatesAndPersists() {
        let suiteName = "LinguaType.ReviewStoreTests.deduplication"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ReviewStore(defaults: defaults)
        let day0 = Date(timeIntervalSinceReferenceDate: 0)
        store.save(point, now: day0)
        store.save(point, now: day0)

        Test.expect(
            store.items.count == 1
                && store.items[0].dueDate == day0.addingTimeInterval(86_400)
                && store.dueItems(now: day0).isEmpty,
            "saving the same point once schedules it for tomorrow"
        )
        Test.expect(
            store.dueItems(now: day0.addingTimeInterval(86_400)).count == 1,
            "due review count includes locally saved items"
        )
        Test.expect(
            ReviewStore(defaults: defaults).items.count == 1,
            "saved review items persist locally"
        )
    }

    private static func testReviewIntervalsAdvanceAndReset() {
        let suiteName = "LinguaType.ReviewStoreTests.schedule"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ReviewStore(defaults: defaults)
        let day0 = Date(timeIntervalSinceReferenceDate: 0)
        let day1 = day0.addingTimeInterval(86_400)
        store.save(point, now: day0)
        let itemID = store.items[0].id

        store.answer(itemID: itemID, isCorrect: true, now: day1)
        let day4 = day1.addingTimeInterval(3 * 86_400)
        let advanced = store.items[0]
        store.answer(itemID: itemID, isCorrect: false, now: day4)

        Test.expect(
            advanced.intervalIndex == 1
                && advanced.dueDate == day4
                && store.items[0].intervalIndex == 0
                && store.items[0].dueDate == day4.addingTimeInterval(86_400),
            "correct review advances to three days and incorrect review resets to one day"
        )
    }

    private static let point = LearningPoint(
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
}
