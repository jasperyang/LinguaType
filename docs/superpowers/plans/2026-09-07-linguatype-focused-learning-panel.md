# LinguaType Focused Learning Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the macOS floating panel into a primary-language learning surface with a scalable language picker, per-language copy, a session-only pin, expandable reference translations, and concise vocabulary cards.

**Architecture:** Add a pure `LanguageSelection` domain model and a pure missing-work planner so selection rules and translation scheduling stay testable outside AppKit. Split the monolithic panel content into header, translation, and vocabulary components; keep window visibility and pin policy in `TranslationPanel`, while `LearningCoordinator` remains the owner of translation state and work queues.

**Tech Stack:** Swift 6, AppKit, SwiftUI Translation framework bridge, Foundation `UserDefaults`, deterministic in-process regression tests.

## Global Constraints

- Run every command through `rtk`.
- Use test-first red-green-refactor for every production behavior change.
- Support macOS 15 or newer and add no third-party dependency.
- Keep the panel width at 520 points and cap height at 60% of the visible screen or 560 points, whichever is smaller.
- Default to French as primary with French, English, and Japanese selected.
- The collapsed language control reads only the primary language, such as `法语⌄`; it never shows `+2` or another count.
- The language picker must enforce one selected primary language and at least one selected language.
- Only selected languages receive new sentence, term, and dictionary work.
- Copy only the complete successful translation; never copy or log labels, source text, errors, or loading placeholders.
- Pin state is session-only and must not be written to preferences.
- Use `FR`, `EN`, and `JP` in the panel; do not use flags as the primary language UI.
- Phrase alignment, grammar extraction, vocabulary saving, new languages, and a resizable window are out of scope.
- Never run `build-linguatype.sh`; use `test-companion.sh` and `build-companion.sh` only.

---

### Task 1: Language selection domain and persistence

**Files:**
- Create: `LinguaTypeCompanion/Sources/LanguageSelection.swift`
- Create: `LinguaTypeCompanion/Tests/LanguageSelectionTests.swift`
- Modify: `LinguaTypeCompanion/Sources/Preferences.swift`
- Modify: `LinguaTypeCompanion/Sources/LearningModels.swift`
- Modify: `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`

**Interfaces:**
- Produces: `LanguageSelection`, `orderedLanguages`, `setPrimary(_:)`, `setSelected(_:enabled:)`.
- Produces: `LinguaTypePreferences.languageSelection(defaults:)` and `setLanguageSelection(_:defaults:)`.
- Consumes: existing `LearningLanguage` raw values and `displayOrder`.

- [ ] **Step 1: Write failing domain and persistence tests**

```swift
enum LanguageSelectionTests {
    static func run() {
        var selection = LanguageSelection(primary: .french, selected: [.english])
        Test.expect(selection.selected == [.french, .english], "primary language is always selected")
        Test.expect(selection.orderedLanguages == [.french, .english], "primary language sorts before references")

        selection.setSelected(.french, enabled: false)
        Test.expect(selection.selected.contains(.french), "primary language cannot be unchecked")

        selection.setPrimary(.japanese)
        Test.expect(selection.primary == .japanese && selection.selected.contains(.japanese), "choosing a primary language also selects it")

        let suite = UserDefaults(suiteName: "LanguageSelectionTests")!
        suite.removePersistentDomain(forName: "LanguageSelectionTests")
        Test.expect(LinguaTypePreferences.languageSelection(defaults: suite) == .default, "language selection defaults to French plus all supported languages")
        LinguaTypePreferences.setLanguageSelection(selection, defaults: suite)
        Test.expect(LinguaTypePreferences.languageSelection(defaults: suite) == selection, "language selection persists")
    }
}
```

Register `LanguageSelectionTests.run()` immediately after `LearningModelsTests.run()`.

- [ ] **Step 2: Run the regression suite and verify RED**

Run: `rtk test ./test-companion.sh`

Expected: compilation fails because `LanguageSelection` and the language-selection preference API do not exist.

- [ ] **Step 3: Implement the minimal normalized value type**

```swift
struct LanguageSelection: Equatable {
    static let `default` = LanguageSelection(
        primary: .french,
        selected: Set(LearningLanguage.displayOrder)
    )

    private(set) var primary: LearningLanguage
    private(set) var selected: Set<LearningLanguage>

    init(primary: LearningLanguage, selected: Set<LearningLanguage>) {
        self.primary = primary
        self.selected = selected.union([primary])
    }

    var orderedLanguages: [LearningLanguage] {
        [primary] + LearningLanguage.displayOrder.filter { $0 != primary && selected.contains($0) }
    }

    mutating func setPrimary(_ language: LearningLanguage) {
        primary = language
        selected.insert(language)
    }

    mutating func setSelected(_ language: LearningLanguage, enabled: Bool) {
        guard language != primary || enabled else { return }
        if enabled { selected.insert(language) } else { selected.remove(language) }
    }
}
```

Persist `primary.rawValue` and the selected raw values under `LinguaType.primaryLanguage` and `LinguaType.selectedLanguages`. Ignore unknown raw values and normalize through the initializer.

Add `shortCode` (`FR`, `EN`, `JP`) and `nativeName` (`Français`, `English`, `日本語`) to `LearningLanguage`; retain `displayName` for Chinese UI labels.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `rtk test ./test-companion.sh`

Expected: all Companion regression tests pass.

- [ ] **Step 5: Commit the domain model**

```bash
rtk proxy /usr/bin/git add LinguaTypeCompanion/Sources/LanguageSelection.swift LinguaTypeCompanion/Sources/Preferences.swift LinguaTypeCompanion/Sources/LearningModels.swift LinguaTypeCompanion/Tests/LanguageSelectionTests.swift LinguaTypeCompanion/Tests/CompanionRegressionTests.swift
rtk proxy /usr/bin/git commit -m "feat: persist primary and selected languages"
```

---

### Task 2: Selection-aware translation work planning

**Files:**
- Create: `LinguaTypeCompanion/Sources/TranslationWorkPlanner.swift`
- Create: `LinguaTypeCompanion/Tests/TranslationWorkPlannerTests.swift`
- Modify: `LinguaTypeCompanion/Sources/LearningModels.swift`
- Modify: `LinguaTypeCompanion/Sources/LearningCoordinator.swift`
- Modify: `LinguaTypeCompanion/Tests/LearningModelsTests.swift`
- Modify: `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`

**Interfaces:**
- Consumes: `LanguageSelection`, `LearningDisplayState`, `TranslationJob`.
- Produces: `TranslationWorkPlanner.missingJobs(state:selection:generation:) -> [TranslationJob]`.
- Produces: `LearningCoordinator.languageSelection` and `setLanguageSelection(_:)`.

- [ ] **Step 1: Write failing planner tests**

Build a state containing successful French sentence/term results and loading English results. Assert literal purposes:

```swift
let jobs = TranslationWorkPlanner().missingJobs(
    state: state,
    selection: LanguageSelection(primary: .french, selected: [.french, .english]),
    generation: 7
)
Test.expect(
    jobs.map(\.purpose) == [
        .phrase(language: .english),
        .term(cardID: 0, language: .english),
    ],
    "planner schedules only missing work for selected languages"
)
Test.expect(
    !jobs.contains { $0.targetLanguageID == "ja" },
    "planner excludes unselected languages"
)
```

Add coordinator tests that commit with only French selected, then change primary to French/English selected and verify the published rows reorder to French first and gain an English loading row without losing the French success row fixture.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test ./test-companion.sh`

Expected: compilation fails because the planner and coordinator selection API do not exist.

- [ ] **Step 3: Implement missing-work planning and coordinator integration**

The planner must emit all missing phrase jobs first, followed by missing term jobs, preserving current job priority expectations:

```swift
struct TranslationWorkPlanner {
    func missingJobs(
        state: LearningDisplayState,
        selection: LanguageSelection,
        generation: UInt64
    ) -> [TranslationJob] {
        let phraseJobs = selection.orderedLanguages.compactMap { language -> TranslationJob? in
            guard state.phraseTranslations.first(where: { $0.language == language })?.status != .success else { return nil }
            return TranslationJob(generation: generation, purpose: .phrase(language: language), text: state.sourcePhrase, sourceLanguageID: "zh-Hans", targetLanguageID: language.rawValue)
        }
        let termJobs = state.vocabularyCards.enumerated().flatMap { cardID, card in
            selection.orderedLanguages.compactMap { language -> TranslationJob? in
                guard !card.terms.contains(where: { $0.language == language }) else { return nil }
                return TranslationJob(generation: generation, purpose: .term(cardID: cardID, language: language), text: card.source, sourceLanguageID: "zh-Hans", targetLanguageID: language.rawValue)
            }
        }
        return phraseJobs + termJobs
    }
}
```

Change `LearningDisplayState.loading` to accept a `LanguageSelection` and create rows in `orderedLanguages`. In `LearningCoordinator.commit`, read the current selection and enqueue the planner output after debounce.

`setLanguageSelection(_:)` must normalize/persist, ensure newly selected languages have loading rows, publish immediately, and enqueue only the planner's missing jobs for the current generation. Deselecting hides via presentation filtering but does not delete completed in-memory results for the current phrase. Ignore late hidden-language results in presentation while allowing the queue to finish safely.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `rtk test ./test-companion.sh`

Expected: planner, coordinator, and existing queue-priority tests pass.

- [ ] **Step 5: Commit selection-aware work scheduling**

```bash
rtk proxy /usr/bin/git add LinguaTypeCompanion/Sources/TranslationWorkPlanner.swift LinguaTypeCompanion/Sources/LearningModels.swift LinguaTypeCompanion/Sources/LearningCoordinator.swift LinguaTypeCompanion/Tests/TranslationWorkPlannerTests.swift LinguaTypeCompanion/Tests/LearningModelsTests.swift LinguaTypeCompanion/Tests/CompanionRegressionTests.swift
rtk proxy /usr/bin/git commit -m "feat: translate only selected languages"
```

---

### Task 3: Copy and pin interaction policies

**Files:**
- Create: `LinguaTypeCompanion/Sources/TranslationClipboard.swift`
- Create: `LinguaTypeCompanion/Tests/TranslationClipboardTests.swift`
- Modify: `LinguaTypeCompanion/Sources/PanelAutoHideController.swift`
- Modify: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`
- Modify: `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`

**Interfaces:**
- Produces: `TranslationClipboardWriting.write(_:)` and `SystemTranslationClipboard`.
- Produces: `TranslationCopyService.copy(_:) -> Bool`.
- Produces: `PanelAutoHideController.isPinned` and `setPinned(_:)`.

- [ ] **Step 1: Write failing copy and pin tests**

```swift
final class CapturingClipboard: TranslationClipboardWriting {
    var values: [String] = []
    func write(_ text: String) { values.append(text) }
}

let clipboard = CapturingClipboard()
let service = TranslationCopyService(clipboard: clipboard)
Test.expect(service.copy(PhraseTranslation(language: .french, text: "Bonjour", status: .success)), "successful translation can be copied")
Test.expect(clipboard.values == ["Bonjour"], "copy writes only the full translation")
Test.expect(!service.copy(PhraseTranslation(language: .english, text: nil, status: .loading)), "loading translation cannot be copied")
```

Extend deterministic timer tests:

```swift
timer.start { hidden = true }
timer.setPinned(true)
scheduler.advance(by: 30)
Test.expect(!hidden, "pinned panel ignores auto-hide deadline")
timer.setPinned(false)
scheduler.advance(by: 11)
Test.expect(!hidden, "unpin starts a fresh twelve-second deadline")
scheduler.advance(by: 1)
Test.expect(hidden, "unpinned panel hides after the fresh deadline")
```

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test ./test-companion.sh`

Expected: compilation fails because the clipboard boundary and pin methods do not exist.

- [ ] **Step 3: Implement the local clipboard boundary and pinned timer state**

`SystemTranslationClipboard.write(_:)` clears `NSPasteboard.general` and writes one string value. `TranslationCopyService.copy(_:)` returns false unless the row is `.success` with non-empty text.

In `PanelAutoHideController`, store `private(set) var isPinned = false`. `start(_:)` retains the hide action but does not schedule while pinned. `setPinned(true)` cancels the token without clearing the action. `setPinned(false)` resets `remaining` to the full interval and schedules if an action exists. `cancel()` continues to clear all pending hide state but does not change `isPinned`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `rtk test ./test-companion.sh`

Expected: copy isolation, pinned timer, hover pause, and existing 12-second tests pass.

- [ ] **Step 5: Commit interaction policies**

```bash
rtk proxy /usr/bin/git add LinguaTypeCompanion/Sources/TranslationClipboard.swift LinguaTypeCompanion/Sources/PanelAutoHideController.swift LinguaTypeCompanion/Tests/TranslationClipboardTests.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift LinguaTypeCompanion/Tests/CompanionRegressionTests.swift
rtk proxy /usr/bin/git commit -m "feat: add translation copy and panel pin policies"
```

---

### Task 4: Language picker and focused translation section

**Files:**
- Create: `LinguaTypeCompanion/Sources/PanelHeaderView.swift`
- Create: `LinguaTypeCompanion/Sources/LanguagePickerView.swift`
- Create: `LinguaTypeCompanion/Sources/TranslationSectionView.swift`
- Create: `LinguaTypeCompanion/Tests/FocusedPanelViewTests.swift`
- Modify: `LinguaTypeCompanion/Sources/LearningPanelContentView.swift`
- Modify: `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`

**Interfaces:**
- Consumes: `LanguageSelection`, `[PhraseTranslation]`, `TranslationCopyService`.
- Produces: header callbacks `onSelectionChange` and `onTogglePin`.
- Produces: translation-section state `expandedReference: LearningLanguage?` and copy buttons keyed by language.
- Produces: `LearningPanelContentView.apply(_:selection:isPinned:)`.

- [ ] **Step 1: Write failing view tests**

Instantiate the real AppKit components with the three-language fixture and assert:

```swift
let view = LearningPanelContentView(frame: NSRect(x: 0, y: 0, width: 520, height: 480), clipboard: clipboard)
view.apply(fixture(), selection: .default, isPinned: false)
Test.expect(view.languageButtonTitle == "法语", "collapsed language control shows only the primary language")
Test.expect(!view.languageButtonTitle.contains("+"), "collapsed language control omits selected-language count")
Test.expect(view.primaryLanguage == .french, "French renders as the primary translation")
Test.expect(view.referenceLanguages == [.english, .japanese], "English and Japanese render as references")
Test.expect(view.copyButtonLanguages == [.french, .english, .japanese], "each visible translation has a copy button")
Test.expect(view.renderedLanguageCodes == ["FR", "EN", "JP"], "panel uses language codes instead of flags")
```

Exercise a reference-row click and assert only that language is expanded; click a second row and assert the first collapses. Apply a state with a different `sourcePhrase` and assert expansion resets. Exercise a copy button through `performClick(nil)` and assert the captured clipboard receives only the full translation.

Exercise picker checkbox and primary-name actions directly and assert the emitted `LanguageSelection` obeys the domain rules.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test ./test-companion.sh`

Expected: compilation fails because the focused view components and new apply signature do not exist.

- [ ] **Step 3: Implement the language dropdown as an AppKit popover**

Use a compact borderless `NSButton` titled with only `selection.primary.displayName` and a chevron image. The button opens an `NSPopover` containing `LanguagePickerView`. Each language row contains an independent checkbox, a language-name button, and a `主语言` marker when applicable. Checkbox changes call `setSelected`; name clicks call `setPrimary`.

The picker is a popover rather than a fixed-width `NSPopUpButton` so a row can independently support primary selection and inclusion without overloading one menu action.

- [ ] **Step 4: Implement primary and reference translation views**

Render the primary row first with high-contrast text. Render references below as one-line buttons with separate copy controls. Store only one `expandedReference`; row actions replace it, while copy actions never mutate it.

Use `NSTextField` wrapping for expanded text and `lineBreakMode = .byTruncatingTail` for collapsed references. Give copy buttons accessibility labels such as `复制法语译文`; use `复制完成` during the 1.2-second success state. Use a cancellable `DispatchWorkItem` per latest copy feedback rather than a blocking delay.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `rtk test ./test-companion.sh`

Expected: header title, picker rules, language codes, primary/reference ordering, expansion, and copy tests pass.

- [ ] **Step 6: Commit the focused translation UI**

```bash
rtk proxy /usr/bin/git add LinguaTypeCompanion/Sources/PanelHeaderView.swift LinguaTypeCompanion/Sources/LanguagePickerView.swift LinguaTypeCompanion/Sources/TranslationSectionView.swift LinguaTypeCompanion/Sources/LearningPanelContentView.swift LinguaTypeCompanion/Tests/FocusedPanelViewTests.swift LinguaTypeCompanion/Tests/CompanionRegressionTests.swift
rtk proxy /usr/bin/git commit -m "feat: add focused multilingual translation UI"
```

---

### Task 5: Source hierarchy and concise vocabulary grid

**Files:**
- Create: `LinguaTypeCompanion/Sources/SourceSectionView.swift`
- Create: `LinguaTypeCompanion/Sources/VocabularyGridView.swift`
- Modify: `LinguaTypeCompanion/Sources/LearningPanelContentView.swift`
- Modify: `LinguaTypeCompanion/Sources/TranslationPanel.swift`
- Modify: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`
- Modify: `LinguaTypeCompanion/Tests/FocusedPanelViewTests.swift`

**Interfaces:**
- Consumes: source phrase, `[VocabularyCard]`, `LanguageSelection`.
- Produces: a source section with subdued text and a vocabulary grid filtered to selected languages.
- Preserves: panel maximum dimensions and scroll-only Learn region.

- [ ] **Step 1: Write failing hierarchy and layout tests**

Use long source, translation, and sense fixtures. Assert:

```swift
Test.expect(view.sourceMaximumLines == 3, "source area is compact but readable")
Test.expect(view.vocabularyColumnCount == 2, "520-point panel uses a two-column vocabulary grid")
Test.expect(view.vocabularyCardViews.count == 3, "panel shows up to three vocabulary cards")
Test.expect(view.vocabularyLanguageCodes.allSatisfy { ["FR", "EN", "JP"].contains($0) }, "vocabulary uses language codes")
let textFits = view.vocabularyCardViews.allSatisfy { card in
    card.descendants.compactMap { $0 as? NSTextField }.allSatisfy { field in
        card.bounds.contains(card.convert(field.bounds, from: field))
    }
}
Test.expect(textFits, "long vocabulary content stays inside each card")
Test.expect(view.vocabularyCardViews.allSatisfy { ($0.layer?.borderWidth ?? 0) == 0 }, "vocabulary cards avoid strong borders")
```

Add this test-only recursive helper in `FocusedPanelViewTests.swift`:

```swift
private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
```

Also apply a French-only selection and assert English and Japanese equivalents are absent. Preserve the existing non-overlap assertions.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test ./test-companion.sh`

Expected: hierarchy accessors/components are missing or existing flag/border/layout assertions fail.

- [ ] **Step 3: Implement source and vocabulary components**

`SourceSectionView` renders `原文 · 中文` and a source label at least 25% smaller than the old title treatment, capped at three lines.

`VocabularyGridView` uses rows containing up to two equal-width cards. Each card renders:

1. source and part of speech;
2. pronunciation metadata when available;
3. `当前语境：…` when available;
4. selected-language equivalents ordered with primary first;
5. a concise Chinese definition capped at two lines.

Use a background with 3–8% luminance lift and zero explicit border width. Keep content-driven card height and pin all internal stacks to their content views. If available width cannot sustain two 232-point cards plus spacing, render one card per row.

- [ ] **Step 4: Update panel sizing**

Replace the fixed `132 + cardCount * 116` estimate with `LearningPanelContentView.fittingSize.height` after applying state, clamped between a readable minimum and the existing screen-dependent maximum. Keep the Learn scroll view capped so header/source/translations never scroll away.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `rtk test ./test-companion.sh`

Expected: long-content bounds, selection filtering, two-column layout, no-border style, and existing card non-overlap tests pass.

- [ ] **Step 6: Commit the learning hierarchy redesign**

```bash
rtk proxy /usr/bin/git add LinguaTypeCompanion/Sources/SourceSectionView.swift LinguaTypeCompanion/Sources/VocabularyGridView.swift LinguaTypeCompanion/Sources/LearningPanelContentView.swift LinguaTypeCompanion/Sources/TranslationPanel.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift LinguaTypeCompanion/Tests/FocusedPanelViewTests.swift
rtk proxy /usr/bin/git commit -m "feat: redesign source and vocabulary hierarchy"
```

---

### Task 6: Application wiring, documentation, and end-to-end verification

**Files:**
- Modify: `LinguaTypeCompanion/Sources/AppDelegate.swift`
- Modify: `LinguaTypeCompanion/Sources/TranslationPanel.swift`
- Modify: `LinguaTypeCompanion/Sources/StatusBarController.swift`
- Modify: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`
- Modify: `LinguaTypeCompanion/Tests/MenuBarTests.swift`
- Modify: `README.md`

**Interfaces:**
- Connects: panel language callback to `LearningCoordinator.setLanguageSelection(_:)`.
- Connects: panel pin callback to `PanelAutoHideController.setPinned(_:)`.
- Preserves: menu-bar left-click show/hide, right-click settings menu, input observation, and privacy behavior.

- [ ] **Step 1: Write failing integration tests**

Assert that a real `TranslationPanel` exposes `isPinned`, toggles it through the header callback, remains visible after the deterministic deadline, and restarts auto-hide after unpinning. Assert that the app delegate installs the panel with the persisted language selection and the menu-bar controls still install into `NSStatusItem`.

Add a menu-state assertion that model status labels remain available for all three supported languages even when some are not selected.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test ./test-companion.sh`

Expected: panel pin/header callback integration is not yet wired.

- [ ] **Step 3: Wire the components**

Construct `LearningPanelContentView` with callbacks that call `coordinator.setLanguageSelection`, `TranslationPanel.togglePinned`, and `TranslationCopyService`. On every coordinator update, apply the current display state, `coordinator.languageSelection`, and pin state before sizing and showing.

Ensure `hide()` cancels pending copy-feedback work and auto-hide work but does not reset the language preference. `applicationWillTerminate` leaves pin unpersisted by design.

- [ ] **Step 4: Update the README**

Document:

- `法语⌄` language picker semantics;
- per-language copy;
- auxiliary expansion;
- pin/unpin and 12-second auto-hide;
- the need to re-authorize Accessibility after rebuilding an ad-hoc local app.

- [ ] **Step 5: Run automated verification**

Run:

```bash
rtk test ./test-companion.sh
rtk proxy /usr/bin/git diff --check
rtk run ./build-companion.sh
rtk proxy /usr/bin/codesign --verify --deep --strict --verbose=2 /Users/jasperyoung/Applications/LinguaTypeCompanion.app
```

Expected: all tests pass, diff check is silent, build succeeds, and code-sign verification reports a valid bundle.

- [ ] **Step 6: Re-authorize and run the real TextEdit smoke test**

Stop the LaunchAgent before replacing authorization, reset only `io.linguatype.companion`, add `/Users/jasperyoung/Applications/LinguaTypeCompanion.app` in System Settings > Privacy & Security > Accessibility, and restart the LaunchAgent.

In TextEdit, type a long Chinese sentence and verify:

1. French is primary by default.
2. English and Japanese are collapsed and expand one at a time.
3. Each copy button places only its full translation on the pasteboard.
4. Pin keeps the panel visible beyond 12 seconds and through a new input.
5. Unpin restores automatic hiding.
6. Three long vocabulary cards neither overlap nor overflow.

- [ ] **Step 7: Commit documentation and final wiring**

```bash
rtk proxy /usr/bin/git add LinguaTypeCompanion/Sources/AppDelegate.swift LinguaTypeCompanion/Sources/TranslationPanel.swift LinguaTypeCompanion/Sources/StatusBarController.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift LinguaTypeCompanion/Tests/MenuBarTests.swift README.md
rtk proxy /usr/bin/git commit -m "feat: ship focused learning panel interactions"
```

- [ ] **Step 8: Push the feature branch**

```bash
rtk proxy /usr/bin/git push origin feature/menu-bar-learning-panel
```
