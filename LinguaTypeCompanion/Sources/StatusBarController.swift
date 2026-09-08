import Cocoa

final class StatusBarController: NSObject {
    private let togglePanel: () -> Void
    private let setLearningEnabled: (Bool) -> Void
    private let setDictionaryLookupEnabled: (Bool) -> Void
    private let modelStatuses: () -> [LearningLanguage: String]
    private let dueReviewCount: () -> Int
    private let showReview: () -> Void
    private let clearCache: () -> Void
    private let showPrivacy: () -> Void

    private(set) var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var learningItem: NSMenuItem!
    private var dictionaryItem: NSMenuItem!
    private var reviewItem: NSMenuItem!
    private var modelItems: [LearningLanguage: NSMenuItem] = [:]

    private(set) var installPath = ""
    var modelStatusLanguages: Set<LearningLanguage> { Set(modelItems.keys) }
    var reviewMenuTitle: String { reviewItem?.title ?? reviewTitle() }

    init(
        togglePanel: @escaping () -> Void,
        setLearningEnabled: @escaping (Bool) -> Void,
        setDictionaryLookupEnabled: @escaping (Bool) -> Void,
        modelStatuses: @escaping () -> [LearningLanguage: String],
        dueReviewCount: @escaping () -> Int = { 0 },
        showReview: @escaping () -> Void = {},
        clearCache: @escaping () -> Void,
        showPrivacy: @escaping () -> Void
    ) {
        self.togglePanel = togglePanel
        self.setLearningEnabled = setLearningEnabled
        self.setDictionaryLookupEnabled = setDictionaryLookupEnabled
        self.modelStatuses = modelStatuses
        self.dueReviewCount = dueReviewCount
        self.showReview = showReview
        self.clearCache = clearCache
        self.showPrivacy = showPrivacy
    }

    func install() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        let autosaveName = "LinguaType"
        let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: preferredPositionKey) == nil {
            // New status items are normally appended at the far-left edge of
            // the extras area. On a crowded notched display that edge is
            // physically obscured, so seed a right-side position once. The
            // user can still Command-drag the item anywhere afterwards.
            UserDefaults.standard.set(180, forKey: preferredPositionKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.isVisible = true
        statusItem = item
        guard let button = item.button else { return }
        button.image = MenuBarIcon.make()
        button.imagePosition = .imageOnly
        button.toolTip = "LinguaType 语言学习 — 点击显示学习卡片，右键打开设置"
        button.setAccessibilityLabel("LinguaType 语言学习")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        buildMenu()
        installPath = "macOS menu bar NSStatusItem"
    }

    private func buildMenu() {
        menu.removeAllItems()

        learningItem = item(title: "启用语言学习", action: #selector(toggleLearning))
        dictionaryItem = item(title: "联网查词", action: #selector(toggleDictionaryLookup))
        menu.addItem(learningItem)
        menu.addItem(dictionaryItem)
        reviewItem = item(title: reviewTitle(), action: #selector(openReview))
        menu.addItem(reviewItem)
        menu.addItem(.separator())

        for language in LearningLanguage.displayOrder {
            let status = NSMenuItem(title: "\(language.displayName)模型", action: nil, keyEquivalent: "")
            status.isEnabled = false
            modelItems[language] = status
            menu.addItem(status)
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "清除词典缓存", action: #selector(clearDictionaryCache)))
        menu.addItem(item(title: "隐私说明…", action: #selector(openPrivacy)))
        menu.addItem(.separator())
        menu.addItem(item(title: "退出 LinguaType Companion", action: #selector(quit), keyEquivalent: "q"))
        refreshMenuState()
    }

    private func item(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshMenuState() {
        learningItem?.state = LinguaTypePreferences.isEnabled ? .on : .off
        dictionaryItem?.state = LinguaTypePreferences.isDictionaryLookupEnabled ? .on : .off
        reviewItem?.title = reviewTitle()
        let statuses = modelStatuses()
        for language in LearningLanguage.displayOrder {
            modelItems[language]?.title = "\(language.displayName)模型：\(statuses[language] ?? "按需准备")"
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp,
           let button = statusItem?.button {
            refreshMenuState()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else {
            togglePanel()
        }
    }

    @objc private func toggleLearning() {
        let enabled = !LinguaTypePreferences.isEnabled
        LinguaTypePreferences.setEnabled(enabled)
        setLearningEnabled(enabled)
        refreshMenuState()
    }

    @objc private func toggleDictionaryLookup() {
        let enabled = !LinguaTypePreferences.isDictionaryLookupEnabled
        LinguaTypePreferences.setDictionaryLookupEnabled(enabled)
        setDictionaryLookupEnabled(enabled)
        refreshMenuState()
    }

    @objc private func clearDictionaryCache() { clearCache() }
    @objc private func openReview() { showReview() }
    @objc private func openPrivacy() { showPrivacy() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func performReviewAction() { showReview() }

    private func reviewTitle() -> String {
        let count = dueReviewCount()
        return count > 0 ? "今日复习 (\(count))" : "复习"
    }
}
