# LinguaType Micro Lesson Design

**Date:** 2026-09-08

## Purpose

Turn each supported input into a short, trustworthy language-learning loop rather than a translation result followed by mechanically selected dictionary entries.

The learning loop is:

1. Understand a natural primary-language translation.
2. Inspect reliable sentence correspondences when the local teaching system can support them.
3. Notice the most useful patterns, expressions, or language differences.
4. Recall one small answer in a ten-to-twenty-second exercise.
5. Save selected learning points for local spaced review.

The feature applies consistently to Japanese, French, and English. It is not a promise of complete sentence parsing or arbitrary phrase alignment.

## Product Decisions

- The panel has two persistent display modes: **Minimal** and **Deep**. Minimal is the default.
- The existing language selector remains a multi-select dropdown. The selected primary language determines the natural translation and lesson content.
- Each selected learning language has its own learner level: beginner, intermediate, or advanced.
- Teaching content is local-first. No sentence, lesson request, learner level, answer, or review history is sent to a new tutor service.
- A sentence map, explanation, or practice appears only when it has explicit local evidence. Missing evidence removes that block; it never produces a speculative teaching result.
- Review is user-initiated from the menu-bar item, shown as **Today's review (N)**. It opens in the existing floating panel and does not create system notifications.

## Visual Structure

### Shared shell

The panel remains a quiet dark blue-gray reading surface with neutral layers and restrained borders. The top row contains:

- LinguaType identity.
- Existing language selector.
- A compact Minimal / Deep segmented control.
- Existing pin control and translation actions.

The source text is an understated source block, not a page-sized headline. The primary natural translation is the strongest text on the screen. Auxiliary translation languages remain available through the existing compact reference interaction instead of competing with the primary lesson.

### Semantic color system

Color identifies a learning stage, not a language or a country:

| Stage | Accent | Use |
| --- | --- | --- |
| Understand | low-saturation sky blue | primary natural translation and its label |
| Compare | restrained lavender | sentence map and language-difference explanation |
| Remember | warm amber | selected learning points and transferable patterns |
| Practice | soft mint | micro-practice prompt, choices, and feedback |
| Review | muted rose | save state and review actions |

Accents are limited to labels, a thin leading rule, small chips, and the corresponding action. Surfaces stay neutral. This keeps the panel readable and prevents a rainbow dashboard appearance.

### Minimal mode

Minimal mode is the default for normal typing. It shows:

1. Source text.
2. Natural primary-language translation.
3. Exactly one highest-ranked learning point, including the expression, concise Chinese meaning, and one transferable usage pattern or example when available.
4. One optional practice prompt.
5. A small save-to-review action when the displayed point is reviewable.

It does not show the sentence map, extra learning points, or the explanation block. The user can switch to Deep mode at any time; the setting persists.

### Deep mode

Deep mode preserves the same source and translation hierarchy, then adds only available teaching stages in this order:

1. **Sentence map**: source phrase and target phrase chips in paired rows.
2. **Worth remembering**: two to four ranked learning points.
3. **Why this expression**: a short contrastive explanation when a local content pack provides one.
4. **Try it**: one micro-practice.
5. **Add to review**: save controls for reviewable points.

No empty section or placeholder appears. A sentence with only a reliable translation may therefore look almost identical in either mode.

## Local Teaching Architecture

### Models

Introduce a lesson layer that is independent of raw translation rendering.

- LearningMode: minimal or deep.
- LearnerLevel: beginner, intermediate, or advanced.
- MicroLesson: a primary translation plus optional map pairs, learning points, explanation, practice, and review candidates.
- SentenceMapPair: source phrase, target phrase, and evidence identifier.
- LearningPoint: stable identifier, language, level range, kind (pattern, expression, or translationDifference), target expression, reading or pronunciation when available, concise Chinese explanation, and optional example.
- WhyExplanation: a pack-authored title and concise contrastive explanation.
- MicroPractice: a single-choice cloze question, choices, correct choice, and success feedback.
- ReviewItem: a saved learning-point snapshot, language, due date, current interval index, and answer state.

LearningDisplayState remains responsible for translations and current panel state. MicroLesson is attached after translation and vocabulary evidence are available so that presentation code never needs to infer teaching logic.

### Lesson planner

TutorLessonPlanner creates a MicroLesson from:

- source phrase;
- successful primary translation;
- selected learning language;
- that language's learner level;
- existing vocabulary and dictionary evidence; and
- a language-specific local lesson content pack.

The planner ranks content by level:

- Beginner: high-frequency structural patterns and basic target-language grammar.
- Intermediate: reusable expressions and common contextual usage.
- Advanced: contrastive wording, register, and translation choices.

It selects at most four points in Deep mode and one in Minimal mode. Higher-ranked learning points must be meaningful in the current sentence; generic named entities and tokenizer-only fragments are not eligible.

### Evidence rule

The planner may emit a map pair, teaching point, explanation, or exercise only if one or more of these hold:

- a language content pack recognizes a defined structural signature in the target translation;
- an existing vocabulary or dictionary result provides the target expression used by the pack;
- a content-pack example and its required target token match the current sentence structure.

Each emitted object records the rule or dictionary evidence that produced it. The UI does not expose implementation identifiers, but tests do.

The planner must not use unconstrained substring matching to invent an alignment. If it cannot establish reliable evidence, it returns no map, no explanation, and no exercise for that part of the sentence.

### Language content packs

French, English, and Japanese packs share the same interface while holding language-specific structure recognizers, explanations, examples, and exercise templates. The initial packs are intentionally small and curated; coverage expands by adding independent rules rather than weakening the evidence threshold.

The pack interface lets a pattern declare:

- eligible learner-level range;
- target-language structural signature;
- source-side meaning or contextual conditions;
- learning point content and example;
- optional paired sentence-map output;
- optional explanation;
- optional cloze template, answer, and distractors.

This supports examples such as Japanese place-plus-action structures, French preposition-plus-activity structures, and English preposition-plus-activity structures without treating the languages as word-for-word equivalents.

## Review Flow

### Saving

A reviewable learning point exposes a star action. Saving creates or updates one local ReviewItem; duplicate saves of the same stable learning-point identifier update the existing item rather than creating another card.

Only user-saved learning points enter the review store. The store is local application data. It may retain the saved phrase, target expression, answer state, and schedule so that review works; no review content is sent elsewhere.

### Scheduling

Correct answers advance through intervals of 1, 3, 7, 14, and 30 days. An incorrect answer returns the item to the 1-day interval. A newly saved item is due in one day.

The menu-bar menu presents **Today's review (N)** when due items exist and **Review** when there are none. Selecting it opens the pinned floating panel in review state, one item at a time. Completing or dismissing a review returns the panel to its ordinary display state without changing whether the panel was pinned before review began.

## Settings and Interaction Rules

- Learning mode is globally persisted and is changed through the panel's compact mode control and the menu settings.
- Learner level is persisted per selected learning language and is configured in the language settings area.
- Changing primary language or learner level regenerates the current lesson if the panel has a current display state. It does not change source input, pin state, or review history.
- Pinning continues to suppress the transient focus auto-hide behavior. Explicitly disabling learning still hides the panel.
- Copy actions remain available alongside each shown translation.

## Failure and Privacy Behavior

- If primary translation fails, no lesson is generated; existing translation error behavior remains authoritative.
- If the lesson planner, a content pack, dictionary evidence, or review storage fails, the translation panel remains usable and the affected teaching block is omitted.
- If a learner level has no eligible reliable rule, the planner falls back to the next useful eligible point, then to no teaching point.
- The implementation introduces no new network calls. Existing Apple Translation and existing privacy-safe dictionary behavior are unchanged.

## Acceptance Criteria

### Presentation

- Minimal is the first-run mode and persists after relaunch.
- Deep mode uses the same translation hierarchy and only adds available map, points, explanation, and practice sections.
- Stage colors are applied consistently and sparingly across all three languages.
- The source never outranks the primary natural translation visually.
- Missing lesson components do not leave blank headings, empty cards, or fixed-height gaps.

### Teaching reliability

- Every rendered map pair, point, explanation, and practice carries local rule or dictionary evidence in the lesson model.
- Unsupported or ambiguous sentences show translation without invented correspondence or exercise.
- A Deep lesson renders no more than four learning points; a Minimal lesson renders no more than one.
- Per-language level settings change the eligible and ranked content without changing the selected primary language.

### Review

- Saving the same learning point twice creates one review item.
- New, correct, and incorrect review answers schedule the next due date as 1 day, then 3/7/14/30 days, or reset to 1 day.
- The menu count reflects due local items.
- Opening and completing review preserves ordinary panel pin semantics.

### Regression coverage

Automated tests cover:

- learning-mode and per-language-level persistence;
- Japanese, French, and English content pack matches;
- evidence-only omission behavior;
- ranking limits and Minimal/Deep projections;
- practice answer feedback;
- review deduplication and interval transitions;
- panel pin and auto-hide behavior during ordinary and review presentation.
