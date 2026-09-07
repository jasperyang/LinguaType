import Cocoa

private final class TestTimerToken: PanelTimerToken {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class TestPanelScheduler: PanelTimerScheduling {
    struct Scheduled { let deadline: TimeInterval; let token: TestTimerToken; let action: () -> Void }
    var now: TimeInterval = 0
    var scheduled: [Scheduled] = []

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> PanelTimerToken {
        let token = TestTimerToken()
        scheduled.append(Scheduled(deadline: now + interval, token: token, action: action))
        return token
    }

    func advance(by interval: TimeInterval) {
        now += interval
        let due = scheduled.filter { $0.deadline <= now && !$0.token.isCancelled }
        scheduled.removeAll { $0.deadline <= now }
        due.forEach { $0.action() }
    }
}

enum PanelPresentationTests {
    static func run() {
        let view = LearningPanelContentView(frame: NSRect(x: 0, y: 0, width: 520, height: 480))
        view.apply(fixture())
        view.layoutSubtreeIfNeeded()
        Test.expect(view.phraseRows.count == 3, "learning panel renders three fixed phrase rows")
        Test.expect(view.vocabularyCardViews.count == 3, "learning panel renders all three vocabulary cards")
        Test.expect(
            view.vocabularyCardViews.allSatisfy { $0.frame.height >= 80 },
            "each vocabulary card receives enough layout height for its text"
        )
        let orderedFrames = view.vocabularyCardViews.map(\.frame).sorted { $0.minY < $1.minY }
        Test.expect(
            zip(orderedFrames, orderedFrames.dropFirst()).allSatisfy { lower, upper in lower.maxY <= upper.minY },
            "vocabulary cards occupy non-overlapping vertical regions"
        )

        let scheduler = TestPanelScheduler()
        let timer = PanelAutoHideController(interval: 12, scheduler: scheduler)
        var hidden = false
        timer.start { hidden = true }
        scheduler.advance(by: 11)
        Test.expect(!hidden, "learning panel remains visible before twelve seconds")
        timer.pointerEntered()
        scheduler.advance(by: 10)
        Test.expect(!hidden, "hover pauses panel auto-hide")
        timer.pointerExited()
        scheduler.advance(by: 1)
        Test.expect(hidden, "auto-hide resumes with the remaining delay after hover")

        let pinnedScheduler = TestPanelScheduler()
        let pinnedTimer = PanelAutoHideController(interval: 12, scheduler: pinnedScheduler)
        var pinnedHidden = false
        pinnedTimer.start { pinnedHidden = true }
        pinnedTimer.setPinned(true)
        pinnedScheduler.advance(by: 30)
        Test.expect(!pinnedHidden, "pinned panel ignores auto-hide deadline")
        pinnedTimer.setPinned(false)
        pinnedScheduler.advance(by: 11)
        Test.expect(!pinnedHidden, "unpin starts a fresh twelve-second deadline")
        pinnedScheduler.advance(by: 1)
        Test.expect(pinnedHidden, "unpinned panel hides after the fresh deadline")
    }

    private static func fixture() -> LearningDisplayState {
        let phrases = LearningLanguage.displayOrder.map {
            PhraseTranslation(language: $0, text: "translated", status: .success)
        }
        let terms = LearningLanguage.displayOrder.map {
            LocalizedTerm(language: $0, term: "term", ipa: $0 == .japanese ? nil : "/ipa/", kana: $0 == .japanese ? "かな" : nil, romanization: $0 == .japanese ? "kana" : nil)
        }
        let cards = ["天气", "适合", "散步"].map {
            VocabularyCard(source: $0, partOfSpeech: "词", chineseSenses: ["中文义项一", "中文义项二"], contextualSense: "中文义项一", terms: terms, status: .complete)
        }
        return LearningDisplayState(sourcePhrase: "今天的天气很适合散步", phraseTranslations: phrases, vocabularyCards: cards, phase: .complete)
    }
}
