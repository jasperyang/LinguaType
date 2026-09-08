# Parameterized Lessons and Resizable Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build validated local FR/EN/JP language templates and a movable, safely resizable, content-adaptive learning panel.

**Architecture:** A pure template matcher validates explicit Chinese slots and target-language anchors before it yields lesson candidates. A separate panel size policy calculates safe bounds, while an AppKit resize overlay and `TranslationPanel` apply and persist manual dimensions.

**Tech Stack:** Swift 6, AppKit, Foundation, UserDefaults, existing `test-companion.sh` test executable.

## Global Constraints

- Lesson generation stays local; do not upload committed phrases or add dependencies.
- Support French, English, and Japanese only in this phase.
- Never render mapping, explanation, or practice without local source and target evidence.
- Preserve learner-level filtering and the four-point lesson cap.
- Keep learning-stage colors in `LinguaTypePalette`.
- Use `rtk` for commands, `apply_patch` for edits, `test-companion.sh` for regression, and `build-companion.sh` only for final installation.

---

### Task 1: Add a pure parameterized lesson matcher

**Files:**
- Create: `LinguaTypeCompanion/Sources/TemplateLessonMatcher.swift`
- Modify: `LinguaTypeCompanion/Tests/MicroLessonPlannerTests.swift`

**Consumes:** `LearningLanguage`, `LessonCandidate`, `LearnerLevel`.

**Produces:** `TemplateLessonMatcher.candidates(sourcePhrase:primaryTranslation:language:level:) -> [LessonCandidate]`.

- [ ] **Step 1: Add failing behavior tests**

Add to `MicroLessonPlannerTests.run()` and implement these tests:

```swift
private static func testParameterizedRulesAcceptKnownSlots() {
    let matcher = TemplateLessonMatcher.builtIn
    let ja = matcher.candidates(sourcePhrase: "在东京学习", primaryTranslation: "東京で勉強する", language: .japanese, level: .beginner)
    let fr = matcher.candidates(sourcePhrase: "在巴黎工作", primaryTranslation: "Je travaille à Paris.", language: .french, level: .beginner)
    let en = matcher.candidates(sourcePhrase: "在伦敦生活", primaryTranslation: "I live in London.", language: .english, level: .beginner)
    Test.expect(
        ja.first?.point.evidenceID == "ja.place-action"
            && fr.first?.point.evidenceID == "fr.place-action"
            && en.first?.point.evidenceID == "en.place-action",
        "known place-action slots create language-specific local lessons"
    )
}

private static func testParameterizedRulesRejectUnverifiedAnchors() {
    let candidates = TemplateLessonMatcher.builtIn.candidates(
        sourcePhrase: "在火星生活", primaryTranslation: "I live on Mars.", language: .english, level: .beginner
    )
    Test.expect(candidates.isEmpty, "unknown slots never fabricate a local lesson")
}
```

- [ ] **Step 2: Confirm red**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: compilation fails because `TemplateLessonMatcher` is absent.

- [ ] **Step 3: Implement explicit, bounded matching**

Create these boundaries:

```swift
struct LessonPlace: Equatable {
    let source: String
    let target: [LearningLanguage: String]
}

struct LessonAction: Equatable {
    let source: String
    let target: [LearningLanguage: String]
}

struct TemplateLessonMatcher {
    static let builtIn: TemplateLessonMatcher
    func candidates(
        sourcePhrase: String,
        primaryTranslation: String,
        language: LearningLanguage,
        level: LearnerLevel
    ) -> [LessonCandidate]
}
```

Define built-in places `东京`, `巴黎`, `伦敦`, `大阪`, `里昂`, and actions `生活`, `工作`, `学习`. Parse only normalized `在<place><action>` input. Validate the complete local target anchor:

```swift
case .japanese: "\(place)で\(action)"
case .french: "Je \(action) à \(place)"
case .english: "I \(action) in \(place)"
```

Return no candidates for unknown slots, incomplete source structure, absent language terms, or failed target anchor.

- [ ] **Step 4: Build reliable course artifacts**

For each valid match create one `LessonCandidate` with stable IDs `ja.place-action`, `fr.place-action`, or `en.place-action`, priority `80`, and levels `[.beginner, .intermediate]`. Include a `SentenceMapPair`, structure learning point, one local example, and a micro-practice whose only correct choice is `で`, `à`, or `in` respectively. Use the same non-empty identifier for all evidence fields.

- [ ] **Step 5: Confirm green**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: new matcher behavior and all prior tests pass.

- [ ] **Step 6: Commit**

```bash
git add LinguaTypeCompanion/Sources/TemplateLessonMatcher.swift LinguaTypeCompanion/Tests/MicroLessonPlannerTests.swift
git commit -m "feat: add local parameterized lesson matcher"
```

### Task 2: Compose curated and parameterized lesson packs

**Files:**
- Modify: `LinguaTypeCompanion/Sources/LessonContentPack.swift`
- Modify: `LinguaTypeCompanion/Tests/MicroLessonPlannerTests.swift`

**Consumes:** `TemplateLessonMatcher` from Task 1 and existing `LessonContentPack`.

**Produces:** per-language content packs that prefer exact curated lessons and fall back to validated templates.

- [ ] **Step 1: Add failing planner integration tests**

```swift
private static func testPlannerUsesParameterizedLessonForSupportedCombination() {
    let lesson = TutorLessonPlanner().plan(
        from: state(source: "在巴黎工作", primary: .french, translation: "Je travaille à Paris."),
        primaryLanguage: .french,
        level: .beginner
    )
    Test.expect(
        lesson?.mapPairs.first?.source == "在巴黎工作" && lesson?.practice?.correctChoice == "à",
        "planner turns validated parameterized French input into a lesson"
    )
}

private static func testExactCuratedRuleStillWinsOverParameterizedFallback() {
    let lesson = TutorLessonPlanner().plan(
        from: state(source: "在东京生活", primary: .japanese, translation: "東京で生活する"),
        primaryLanguage: .japanese,
        level: .beginner
    )
    Test.expect(lesson?.learningPoints.first?.id == "ja.place-action", "curated rule remains first")
}
```

- [ ] **Step 2: Confirm red**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: the French parameterized planner test fails because the pack only matches a whole fixed sentence.

- [ ] **Step 3: Implement pack composition**

Add these types to `LessonContentPack.swift`:

```swift
struct ParameterizedLessonContentPack: LessonContentPack {
    let language: LearningLanguage
    let matcher: TemplateLessonMatcher
}

struct CompositeLessonContentPack: LessonContentPack {
    let language: LearningLanguage
    let packs: [any LessonContentPack]
}
```

`ParameterizedLessonContentPack.candidates(...)` delegates to `matcher`; `CompositeLessonContentPack.candidates(...)` concatenates its packs in order. Replace each entry in `BuiltInLessonPacks.all` with a composite where the existing curated pack is first and the parameterized pack second. Curated priorities remain 100, so the unchanged `TutorLessonPlanner` sort keeps exact lessons first.

- [ ] **Step 4: Confirm green**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: the parameterized fallback appears, exact lessons retain priority, and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add LinguaTypeCompanion/Sources/LessonContentPack.swift LinguaTypeCompanion/Tests/MicroLessonPlannerTests.swift
git commit -m "feat: plan lessons from validated language templates"
```

### Task 3: Add safe and persistent panel sizing

**Files:**
- Create: `LinguaTypeCompanion/Sources/PanelSizePolicy.swift`
- Modify: `LinguaTypeCompanion/Sources/Preferences.swift`
- Modify: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`

**Consumes:** `NSSize`, `NSRect`, UserDefaults.

**Produces:** safe frame sizing and independent manual-size persistence.

- [ ] **Step 1: Add failing policy tests**

```swift
private static func testPanelSizePolicyClampsAndPreservesOverride() {
    let policy = PanelSizePolicy()
    let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
    let automatic = policy.size(requested: NSSize(width: 520, height: 900), visibleFrame: visible)
    let manual = policy.size(requested: NSSize(width: 760, height: 460), visibleFrame: visible)
    Test.expect(automatic == NSSize(width: 520, height: 480), "automatic size obeys the 60 percent screen cap")
    Test.expect(manual == NSSize(width: 760, height: 460), "valid manual size is preserved")
}

private static func testPanelSizePreferencesRoundTrip() {
    let defaults = UserDefaults(suiteName: "PanelSizePreferencesTests")!
    defaults.removePersistentDomain(forName: "PanelSizePreferencesTests")
    PanelSizePreferences.setUserSize(NSSize(width: 700, height: 420), defaults: defaults)
    Test.expect(PanelSizePreferences.userSize(defaults: defaults) == NSSize(width: 700, height: 420), "manual size persists")
}
```

- [ ] **Step 2: Confirm red**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: compilation fails for `PanelSizePolicy` and `PanelSizePreferences`.

- [ ] **Step 3: Implement pure sizing and defaults adapter**

Create:

```swift
enum PanelSizeSource { case automatic, userOverride }

struct PanelSizePolicy {
    let minimumSize = NSSize(width: 420, height: 190)
    let maximumHeightFraction: CGFloat = 0.60
    let margin: CGFloat = 6
    func size(requested: NSSize, visibleFrame: NSRect) -> NSSize
}
```

Clamp width to `420...visibleFrame.width - 12` and height to `190...min(560, visibleFrame.height * 0.60)`. In `Preferences.swift`, implement `PanelSizePreferences.userSize(defaults:)` and `setUserSize(_:defaults:)` as two `Double` values, returning nil if either value is non-positive.

- [ ] **Step 4: Confirm green and commit**

Run `rtk proxy /bin/sh -c './test-companion.sh'`, then:

```bash
git add LinguaTypeCompanion/Sources/PanelSizePolicy.swift LinguaTypeCompanion/Sources/Preferences.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift
git commit -m "feat: add persistent safe panel sizing"
```

Expected: all tests pass before commit.

### Task 4: Implement edge and corner resize interaction

**Files:**
- Create: `LinguaTypeCompanion/Sources/PanelResizeHandleView.swift`
- Modify: `LinguaTypeCompanion/Sources/TranslationPanel.swift`
- Modify: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`

**Consumes:** `PanelSizePolicy`, `PanelSizePreferences`, `NSPanel.frame`.

**Produces:** edge/corner gesture deltas and persisted manual frame size.

- [ ] **Step 1: Add failing resize-math tests**

```swift
private static func testResizeDirectionsMoveExpectedEdges() {
    let frame = NSRect(x: 100, y: 100, width: 520, height: 300)
    let southeast = PanelResizeMath.frame(from: frame, direction: .bottomRight, delta: NSPoint(x: 80, y: -50))
    let west = PanelResizeMath.frame(from: frame, direction: .left, delta: NSPoint(x: -40, y: 0))
    Test.expect(southeast.size == NSSize(width: 600, height: 350), "bottom-right resize changes both dimensions")
    Test.expect(west.origin.x == 60 && west.width == 560, "left resize preserves the opposite edge")
}
```

- [ ] **Step 2: Confirm red**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: compilation fails for `PanelResizeMath`.

- [ ] **Step 3: Implement pure resize math and AppKit handle**

Create:

```swift
enum PanelResizeDirection { case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
enum PanelResizeMath {
    static func frame(from frame: NSRect, direction: PanelResizeDirection, delta: NSPoint) -> NSRect
}
final class PanelResizeHandleView: NSView {
    var onResize: ((PanelResizeDirection, NSPoint) -> Void)?
}
```

Use an 8pt edge band and 14pt corner zones. The view records `NSEvent.mouseLocation` on mouse down, emits cumulative mouse deltas during drag, and changes to horizontal, vertical, or diagonal resize cursors only in a hit zone. Use the pure math to preserve the opposite edge for left and bottom drags.

- [ ] **Step 4: Wire into the floating panel**

Add the handle above `content` in `TranslationPanel.visualEffect`, constrained to its four edges. In the callback, calculate the raw frame with `PanelResizeMath`, clamp only its size with `PanelSizePolicy`, preserve the appropriate opposite edge after clamping, set the frame, persist the resulting size, and set `hasUserSizeOverride = true`. Keep controls clickable by leaving the resize view transparent outside hit zones.

- [ ] **Step 5: Confirm green and commit**

Run `rtk proxy /bin/sh -c './test-companion.sh'`, then:

```bash
git add LinguaTypeCompanion/Sources/PanelResizeHandleView.swift LinguaTypeCompanion/Sources/TranslationPanel.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift
git commit -m "feat: resize the floating learning panel"
```

Expected: resize behavior and all previous tests pass.

### Task 5: Coordinate automatic content height and deep-content scrolling

**Files:**
- Modify: `LinguaTypeCompanion/Sources/LearningPanelContentView.swift`
- Modify: `LinguaTypeCompanion/Sources/TranslationPanel.swift`
- Modify: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`

**Consumes:** manual override state from Task 4 and `LearningPanelContentView.preferredHeight`.

**Produces:** automatic short-content sizing, remembered manual size, and internal scrolling for constrained deep lessons.

- [ ] **Step 1: Add the failing overflow test**

Expose `var usesInternalScrolling: Bool` from `LearningPanelContentView`. Build `longLessonFixture()` with four points, three map pairs, explanation, and practice. Add:

```swift
private static func testLongLessonUsesInternalScrollingWhenConstrained() {
    let view = LearningPanelContentView(frame: NSRect(x: 0, y: 0, width: 520, height: 220))
    view.apply(longLessonFixture(), selection: .default, isPinned: false)
    view.layoutSubtreeIfNeeded()
    Test.expect(view.usesInternalScrolling, "deep content scrolls inside a constrained panel")
}
```

- [ ] **Step 2: Confirm red**

Run `rtk proxy /bin/sh -c './test-companion.sh'`.

Expected: the seam is missing or the assertion fails because lesson content is unbounded.

- [ ] **Step 3: Make only variable content scroll**

Keep header, source, and translations outside the new internal `NSScrollView`. Move `microLessonView`, `learnLabel`, and vocabulary content into its document view. Set `usesInternalScrolling` only when available height is less than the document fitting height; default automatic presentations remain unscrolled for short content.

- [ ] **Step 4: Use the size policy on every panel refresh**

In `TranslationPanel.position(near:)`, choose `PanelSizePreferences.userSize()` when `hasUserSizeOverride` is true; otherwise request `(520, content.preferredHeight)`. Clamp with `PanelSizePolicy`, place within `visibleFrame` margin, then provide the final available content height to `LearningPanelContentView`. Do not overwrite a valid user override on `apply`, pin changes, review dismissal, or new input.

- [ ] **Step 5: Verify, install, and commit**

Run `rtk proxy /bin/sh -c './test-companion.sh'`, then `rtk proxy /bin/sh -c './build-companion.sh'`. Confirm codesigning succeeds. After user enables Accessibility for the newly installed app, validate TextEdit with `在东京学习`, `在巴黎工作`, and `在伦敦生活`; check matching maps/practice, stage colors, header dragging, right/bottom/corner resizing, persistence across another input, pinning, Minimal/Deep, and internal scroll for long lessons.

```bash
git add LinguaTypeCompanion/Sources/LearningPanelContentView.swift LinguaTypeCompanion/Sources/TranslationPanel.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift
git commit -m "feat: adapt learning panel size to content"
git push origin feature/menu-bar-learning-panel
```

## Plan Self-Review

- Spec coverage: Tasks 1–2 supply local parameterized FR/EN/JP lessons and reliable fallback; Tasks 3–5 cover persistence, safety limits, edge/corner resizing, content scrolling, colors during manual acceptance, and installation.
- Placeholder scan: no incomplete implementation references or deferred work items are present.
- Type consistency: Task 1 produces the matcher consumed in Task 2; Task 3 produces sizing policy/preferences consumed in Task 4; Task 4’s override state is consumed in Task 5.
