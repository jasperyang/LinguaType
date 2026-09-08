import Cocoa

enum MenuBarTests {
    static func run() {
        let image = MenuBarIcon.make()
        Test.expect(
            image.size == NSSize(width: 18, height: 18),
            "menu bar icon is legible at an 18 point square"
        )
        Test.expect(image.isTemplate, "menu bar icon follows the system menu bar tint")

        let controller = StatusBarController(
            togglePanel: {},
            setLearningEnabled: { _ in },
            setDictionaryLookupEnabled: { _ in },
            modelStatuses: { [:] },
            clearCache: {},
            showPrivacy: {}
        )
        controller.install()
        let legacyAnchors = NSApp.windows.filter {
            $0.frame.size == NSSize(width: 36, height: 28)
                && $0.styleMask.contains(.nonactivatingPanel)
                && $0.level == .statusBar
        }
        Test.expect(
            legacyAnchors.isEmpty,
            "installing the menu bar item creates no floating anchor window"
        )
        Test.expect(
            controller.installPath == "macOS menu bar NSStatusItem",
            "controls are installed in the native menu bar"
        )
        Test.expect(
            controller.statusItem?.autosaveName == "LinguaType",
            "menu bar item has a stable persisted position identity"
        )
        Test.expect(
            controller.statusItem?.isVisible == true,
            "menu bar item explicitly restores visible state"
        )
        Test.expect(
            controller.modelStatusLanguages == Set(LearningLanguage.displayOrder),
            "menu keeps model statuses for every supported language"
        )

        var reviewOpened = false
        let reviewController = StatusBarController(
            togglePanel: {},
            setLearningEnabled: { _ in },
            setDictionaryLookupEnabled: { _ in },
            modelStatuses: { [:] },
            dueReviewCount: { 3 },
            showReview: { reviewOpened = true },
            clearCache: {},
            showPrivacy: {}
        )
        reviewController.install()
        Test.expect(
            reviewController.reviewMenuTitle == "今日复习 (3)",
            "menu shows the local due review count"
        )
        reviewController.performReviewAction()
        Test.expect(reviewOpened, "review menu invokes the local review callback")
    }
}
