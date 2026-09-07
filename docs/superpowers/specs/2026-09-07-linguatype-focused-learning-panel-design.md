# LinguaType Focused Learning Panel Design

**Date:** 2026-09-07  
**Status:** Approved in conversation  
**Scope:** Native macOS Companion learning panel

## Goal

Redesign the floating panel from an equal-weight translation/debug display into a quiet, focused learning surface: source text first, one primary learning language, optional reference languages, then concise vocabulary help. Add one-click copying and a session-only pin without changing the input capture or translation providers.

## Product Principle

The panel should answer three questions in order:

1. What did I type?
2. How do I say it in the language I am learning?
3. What useful vocabulary can I take away from this sentence?

The design direction is “Raycast × Linear × a minimal dictionary”: calm, text-first, low-chrome, and suitable for remaining visible beside another application.

## Scope

This iteration includes:

- A primary learning language with selected reference languages.
- A future-friendly language dropdown rather than fixed segmented buttons.
- One-click copy for every visible sentence translation.
- A session-only panel pin.
- Expandable reference-language translations.
- A revised source, translation, and vocabulary information hierarchy.
- Reduced borders and a restrained dark blue-gray visual system.
- Translation and dictionary work limited to selected languages.

This iteration does not include:

- Phrase-level alignment or synchronized source/translation highlighting.
- Automatic expression or grammar extraction.
- Saving vocabulary.
- Additional languages beyond French, English, and Japanese.
- A resizable standalone window.

Phrase alignment and expression/grammar extraction require a separate semantic-analysis design; they must not be approximated with unreliable substring matching.

## Information Architecture

The panel is one vertical reading flow:

1. **Header:** `LINGUATYPE · WRITE · TRANSLATE · LEARN`, language dropdown, and pin.
2. **Source:** a small `原文 · 中文` label and subdued source text.
3. **Translate:** the primary language in a higher-emphasis surface, followed by compact reference-language rows.
4. **Learn:** up to three vocabulary cards, using a two-column grid when space permits and one column when it does not.

Only the Learn region scrolls. The header, source, and sentence translations remain visible while vocabulary is scrolled.

## Language Selection

### Defaults

- Primary language: French.
- Selected languages: French, English, and Japanese.
- Both choices persist in `UserDefaults`.

### Collapsed Control

The header dropdown displays only the primary language name and chevron, for example `法语⌄`. It does not display a selected-language count such as `+2`.

### Expanded Menu

Each supported language has two related controls:

- A checkbox determines whether that language is translated and displayed.
- Selecting the language name makes it the primary language and implicitly checks it.

Exactly one selected language is primary. The primary language cannot be unchecked until another language becomes primary. At least one language must remain selected.

The current implementation lists French, English, and Japanese. The control and selection model must allow more languages to be added later without widening the header.

### Ordering and Work Scheduling

- The primary language is always rendered first.
- Other selected languages follow the product display order.
- Unselected languages are absent from sentence translations and vocabulary term rows.
- Unselected languages do not receive new translation or dictionary jobs.
- Changing only the primary language immediately reorders existing results and does not repeat completed work.
- Selecting a previously unselected language adds loading placeholders and requests only missing sentence and vocabulary results for the current source phrase.
- Deselecting a language hides it immediately. Already completed in-memory results may be retained for reuse during the current phrase.

## Sentence Translation Interaction

### Primary Translation

The primary language uses the highest text contrast and an unobtrusive, slightly lighter surface. Its header contains the language code, native name, `主学习语言`, and a copy button.

### Reference Translations

Reference languages display as single-line summaries by default. Long text truncates with an ellipsis, but the adjacent copy button always copies the complete translation.

Clicking the text portion expands or collapses that reference translation. Only one reference language can be expanded at a time. Clicking a different reference row expands it and collapses the previous row. The copy button acts independently and must not toggle expansion.

Expansion survives progressive result updates for the same source phrase. A newly committed source phrase resets all reference rows to collapsed.

### Copy

- Every visible sentence translation has its own copy button.
- The button writes only the complete translation text to the local macOS pasteboard.
- It never includes the language code, language name, loading text, or error message.
- The button is disabled while the row is loading or failed.
- After a successful copy, the icon changes in place to a checkmark for 1.2 seconds, then returns to the copy glyph.
- Copying does not show a toast, send network traffic, or write translation content to logs.

## Pin and Visibility

The panel starts unpinned on each application launch.

- Clicking pin cancels the active 12-second auto-hide timer and prevents later updates from starting another timer.
- While pinned, newly committed input replaces the panel content in the same panel.
- Clicking pin again restores the unpinned state and starts a fresh 12-second timer if the panel is visible.
- Hover pause/resume continues to apply only while unpinned.
- Left-clicking the macOS menu-bar item can still hide or show the panel while pinned.
- Pin state is not persisted across application launches.

The active pin uses the single accent color and exposes an accessibility label that changes between `固定浮窗` and `取消固定浮窗`.

## Vocabulary Presentation

Vocabulary cards prioritize usage over dictionary detail:

1. Source word.
2. Pronunciation and part of speech when available.
3. `当前语境` using the contextual Chinese sense.
4. Selected-language equivalents, with the primary language emphasized.
5. A concise Chinese definition, capped at two visible lines.

French and English terms retain IPA when available. Japanese retains kana and local romaji. Language rows use `FR`, `EN`, and `JP`; flags are removed from the learning panel.

Cards use a 3–8% background lift instead of a visible rectangular border. Up to three cards are shown. Their content determines their height; cards must never overlap or allow text to escape their bounds.

## Visual System

- Panel width: 520 points.
- Maximum panel height: 60% of the containing screen's visible frame, capped at 560 points.
- Base material: dark blue-gray HUD material, not near-black.
- Accent: one low-saturation blue used for the primary language, active pin, selection, and copy success.
- Text hierarchy:
  - Primary translation: high-contrast label color.
  - Source and reference translations: approximately 75% visual emphasis.
  - Pronunciation, part of speech, and definitions: approximately 50–60% visual emphasis.
- Dividers are used only between major Source, Translate, and Learn regions.
- Component separation relies on subtle background luminance rather than strong borders.
- Controls have at least a 24-point target and clear accessibility labels and help text.

## Component Boundaries

### `LanguageSelection`

A value type containing:

- `primary: LearningLanguage`
- `selected: Set<LearningLanguage>`

It normalizes invalid values so the primary language is selected and at least one language remains. A preferences adapter reads and writes the primary raw value and selected raw values in `UserDefaults`.

### `PanelHeaderView`

Renders the brand, language dropdown, and pin. It emits intent callbacks and does not schedule translation work itself.

### `SourceSectionView`

Renders the source label and source phrase with the lower visual priority defined above.

### `TranslationSectionView`

Renders the primary translation and reference rows. It owns only presentation state for the currently expanded reference and transient copied-language feedback. It delegates pasteboard writes through an injected clipboard boundary.

### `VocabularyGridView`

Renders selected-language vocabulary equivalents and concise definitions. It owns no dictionary or translation work.

### `TranslationPanel`

Owns window visibility, `isPinned`, and auto-hide coordination. It connects view callbacks to panel behavior and the coordinator.

### `LearningCoordinator`

Owns the current `LanguageSelection`, translation state, and jobs. It filters new work to selected languages, retains completed results for the current phrase, and schedules only missing work when languages are added.

## State Flow

```text
Header language action
  -> LanguageSelection normalizes and persists
  -> LearningCoordinator updates the current state
  -> panel reorders or hides rows immediately
  -> coordinator queues only missing selected-language work
  -> progressive results update the same panel
```

```text
Pin action
  -> TranslationPanel toggles isPinned
  -> pinned: cancel auto-hide
  -> unpinned and visible: start a fresh 12-second timer
```

```text
Copy action
  -> validate successful non-empty translation
  -> write translation only to NSPasteboard
  -> show local checkmark for 1.2 seconds
```

## Loading and Failure Behavior

- Each selected language loads independently.
- Loading rows reserve stable space and disable copy.
- A language failure displays a short message only in that row and does not hide successful languages or Learn content.
- The next committed phrase retries failed languages normally.
- Selecting a language during an active phrase shows its row immediately, then progressively fills sentence and vocabulary results.
- Removing a language makes any later result for that hidden language non-visible; it must not reorder or revive the row.

## Privacy

The redesign does not expand data collection. Complete source phrases remain on-device in Apple Translation. Online dictionary requests contain isolated terms only. Clipboard operations are local. Logs may record status and counts but must never include source phrases, translations, copied text, or dictionary terms.

## Acceptance Criteria

1. The default panel renders French as the full primary translation and English/Japanese as collapsed references.
2. The collapsed language selector reads `法语⌄` and contains no selected-language count.
3. The dropdown cannot uncheck the primary or leave zero selected languages.
4. Changing the primary language immediately reorders existing translations without repeating completed requests.
5. Adding a language to the current phrase requests only results missing for that language.
6. Removing a language removes both its sentence row and vocabulary equivalents and prevents new work for it.
7. Each successful visible translation copies only its complete text and shows a 1.2-second checkmark.
8. At most one reference translation is expanded, and new input collapses it.
9. A pinned panel remains visible after 12 seconds and through later input; unpinning restarts auto-hide.
10. Long source text, translations, and three vocabulary cards do not overlap or overflow horizontally.
11. The panel uses language codes rather than flags and contains no strong vocabulary-card borders.
12. Accessibility labels describe language selection, copy, expansion, and pin states.
13. Existing privacy, translation ordering, dictionary cache, and input-observer regression tests remain green.

## Verification Strategy

- Unit-test `LanguageSelection` normalization, ordering, and persistence.
- Unit-test coordinator scheduling when languages are selected, added, removed, or promoted to primary.
- Unit-test clipboard output through an injected local writer; assert that labels and user source text are excluded.
- Unit-test pin behavior with the existing deterministic panel timer scheduler.
- View-test primary/reference ordering, copy enabled states, single reference expansion, language-code labels, and long-content layout bounds.
- Run the complete Companion regression suite.
- Build and code-sign the installed app, then re-authorize Accessibility because the local build uses an ad-hoc signature.
- Perform a real TextEdit smoke test covering input capture, language selection, reference expansion, copying, pinning past 12 seconds, unpinning, and auto-hide.

