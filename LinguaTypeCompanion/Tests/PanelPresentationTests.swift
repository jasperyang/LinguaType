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
        Test.expect(
            view.vocabularyCardViews.enumerated().allSatisfy { index, card in
                let cardFrame = view.convert(card.bounds, from: card)
                return view.vocabularyCardViews.dropFirst(index + 1).allSatisfy {
                    !cardFrame.intersects(view.convert($0.bounds, from: $0))
                }
            },
            "vocabulary cards occupy non-overlapping regions"
        )

        let contentReviewItem = ReviewItem(
            id: UUID(),
            point: LearningPoint(
                id: "review",
                language: .english,
                kind: .expression,
                targetExpression: "work in London",
                pronunciation: nil,
                chineseMeaning: "在伦敦工作",
                pattern: nil,
                example: nil,
                evidenceID: "review"
            ),
            dueDate: Date(),
            intervalIndex: 0,
            lastAnswerCorrect: nil
        )
        var reviewAnswer: Bool?
        view.showReview(contentReviewItem) { _, isCorrect in reviewAnswer = isCorrect }
        view.performReviewAnswer(isCorrect: false)
        Test.expect(
            view.isReviewVisible && reviewAnswer == false,
            "panel content presents and answers a review card"
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

        let integrationScheduler = TestPanelScheduler()
        let integrationTimer = PanelAutoHideController(
            interval: 12,
            scheduler: integrationScheduler
        )
        let coordinator = LearningCoordinator(
            languageSelection: .default,
            persistSelection: { _ in }
        )
        let panel = TranslationPanel(
            coordinator: coordinator,
            autoHide: integrationTimer
        )
        panel.apply(fixture())
        panel.performPinAction()
        Test.expect(panel.isPinned, "panel header pin action fixes the panel in place")
        panel.apply(nil)
        Test.expect(
            panel.isVisible,
            "pinned panel survives a temporary non-Chinese focus state"
        )
        integrationScheduler.advance(by: 30)
        Test.expect(panel.isVisible, "pinned panel remains visible beyond auto-hide deadline")
        panel.performPinAction()
        integrationScheduler.advance(by: 12)
        Test.expect(!panel.isVisible, "unpinning restores the twelve-second auto-hide")

        let panelReviewItem = ReviewItem(
            id: UUID(),
            point: LearningPoint(
                id: "review-panel",
                language: .english,
                kind: .expression,
                targetExpression: "work in London",
                pronunciation: nil,
                chineseMeaning: "在伦敦工作",
                pattern: nil,
                example: nil,
                evidenceID: "review-panel"
            ),
            dueDate: Date(),
            intervalIndex: 0,
            lastAnswerCorrect: nil
        )
        var reviewAnswered = false
        panel.showReview(panelReviewItem) { _, _ in reviewAnswered = true }
        panel.performReviewAnswer(isCorrect: true)
        Test.expect(
            reviewAnswered && !panel.isPinned,
            "review answer restores the panel's previous pin state"
        )
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
