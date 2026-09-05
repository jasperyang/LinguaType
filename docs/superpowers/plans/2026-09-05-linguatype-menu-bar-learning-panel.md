# LinguaType Menu Bar Learning Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the floating “字” anchor with a native “A·あ” macOS menu bar item and deliver a privacy-preserving French, English, and Japanese learning panel with up to three rich vocabulary cards.

**Architecture:** Keep the existing Accessibility observer and hidden SwiftUI `TranslationSession` bridge, but split orchestration, vocabulary extraction, dictionary access, caching, presentation state, and panel rendering into focused units. Full phrases stay inside Apple Translation; only isolated normalized terms can enter provider-specific dictionary requests.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Apple Translation, NaturalLanguage, URLSession, MediaWiki Action API, Free Dictionary API, Jotoba/JMdict, custom `swiftc` test executable.

## Global Constraints

- Deployment target remains `arm64-apple-macos15`.
- Fixed display order is French (`fr`), English (`en`), Japanese (`ja`).
- At most three vocabulary cards are displayed per committed Chinese phrase.
- English and French show IPA; Japanese shows kana and locally generated romaji.
- No online AI service or user API key is introduced.
- Full committed phrases, app names, window titles, caret geometry, device identifiers, and exposure history never enter dictionary requests or network logs.
- Dictionary requests contain one normalized term of at most 32 Unicode characters.
- Dictionary request timeout is four seconds; only connectivity errors, timeouts, and HTTP 5xx receive one retry.
- Successful cache entries live for 30 days; negative and transient-failure entries live for 10 minutes.
- Panel width is 520 px; maximum height is `min(560, visibleScreenHeight * 0.60)`.
- Auto-hide begins 12 seconds after the first phrase result or explicit phrase error; pointer hover pauses it.
- Do not execute `build-linguatype.sh` during this work because it resets and cleans the dirty nested `work/rimes` checkout.
- Every shell command must be invoked through `rtk`.

---

## File Structure

### Repository and build files

- Create `.gitignore`: exclude generated apps, bundles, build output, `.superpowers`, and the nested upstream checkout.
- Create `build-companion.sh`: build, sign, install, and restart only the Companion without touching `work/rimes`.
- Modify `test-companion.sh`: compile every production Swift file except `main.swift`, plus all test Swift files.
- Modify `README.md`: document the menu bar UX, three languages, dictionary privacy, providers, and safe build commands.

### Production sources

- Create `LinguaTypeCompanion/Sources/LearningModels.swift`: immutable presentation types and fixed languages.
- Create `LinguaTypeCompanion/Sources/MenuBarIcon.swift`: render the 18×18 pt “A·あ” template image.
- Modify `LinguaTypeCompanion/Sources/StatusBarController.swift`: use `NSStatusItem`, left/right click routing, and settings menu; remove `AnchorPanel`.
- Modify `LinguaTypeCompanion/Sources/Preferences.swift`: learning and online-dictionary toggles only; remove language cycling.
- Create `LinguaTypeCompanion/Sources/VocabularyExtractor.swift`: local candidate extraction and deterministic ranking.
- Create `LinguaTypeCompanion/Sources/DictionaryModels.swift`: safe query and normalized entry models.
- Create `LinguaTypeCompanion/Sources/DictionaryCache.swift`: versioned 30-day/10-minute disk cache.
- Create `LinguaTypeCompanion/Sources/DictionaryNetworking.swift`: provider protocol, bounded request execution, retry, and redacted logging.
- Create `LinguaTypeCompanion/Sources/WiktionaryDictionaryProvider.swift`: Chinese and French MediaWiki requests and parsing.
- Create `LinguaTypeCompanion/Sources/EnglishDictionaryProvider.swift`: Free Dictionary API adapter.
- Create `LinguaTypeCompanion/Sources/JapaneseDictionaryProvider.swift`: Jotoba word-search adapter.
- Create `LinguaTypeCompanion/Sources/RomajiTransliterator.swift`: local kana-to-romaji conversion.
- Create `LinguaTypeCompanion/Sources/TranslationJobQueue.swift`: fixed-priority FIFO translation jobs.
- Modify `LinguaTypeCompanion/Sources/LearningCoordinator.swift`: integrate three phrase jobs, term jobs, dictionary lookup, definition localization, and progressive display state.
- Create `LinguaTypeCompanion/Sources/LearningPanelContentView.swift`: AppKit content hierarchy and vocabulary cards.
- Create `LinguaTypeCompanion/Sources/PanelAutoHideController.swift`: injectable 12-second timer state.
- Modify `LinguaTypeCompanion/Sources/TranslationPanel.swift`: nonactivating scrollable panel, geometry, hover, and last-result reopening.
- Modify `LinguaTypeCompanion/Sources/AppDelegate.swift`: connect menu actions, dictionary cache, model statuses, and panel state without activating the app.

### Tests and fixtures

- Modify `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`: suite runner only and updated launch regression.
- Create `LinguaTypeCompanion/Tests/TestSupport.swift`: assertions, reflection helpers, async wait helper, and temp directories.
- Create `LinguaTypeCompanion/Tests/LearningModelsTests.swift`.
- Create `LinguaTypeCompanion/Tests/MenuBarTests.swift`.
- Create `LinguaTypeCompanion/Tests/VocabularyExtractorTests.swift`.
- Create `LinguaTypeCompanion/Tests/DictionaryPrivacyTests.swift`.
- Create `LinguaTypeCompanion/Tests/DictionaryProviderTests.swift`.
- Create `LinguaTypeCompanion/Tests/DictionaryCacheTests.swift`.
- Create `LinguaTypeCompanion/Tests/TranslationJobQueueTests.swift`.
- Create `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`.
- Create JSON fixtures under `LinguaTypeCompanion/Tests/Fixtures/` for Chinese/French MediaWiki, Free Dictionary API, and Jotoba responses.

---

### Task 1: Public Repository Baseline and Safety Guardrails

**Files:**
- Create: `.gitignore`
- Modify: `README.md`
- Inspect: all non-ignored files at project root

**Interfaces:**
- Consumes: existing project contents and authenticated GitHub account `jasperyang`.
- Produces: public repository `jasperyang/LinguaType` with generated artifacts, `.superpowers`, `work/rimes`, and secrets excluded.

- [ ] **Step 1: Add public-repository exclusions**

```gitignore
.DS_Store
.superpowers/
.build/
DerivedData/
dist/
work/
*.app/
*.bundle/
*.pkg
*.xcuserstate
```

- [ ] **Step 2: Verify that ignored and candidate files are correct**

Run:

```bash
rtk find . -maxdepth 3 -type f
rtk grep -n -i "api[_-]*key|secret|password|authorization:|bearer |ghp_|sk-" . --exclude-dir=work --exclude-dir=.superpowers --exclude='*.app/*' --exclude='*.bundle/*'
```

Expected: no unmasked credentials, personal documents, generated app bundles, or nested upstream files in the candidate set. Any match must be inspected before continuing.

- [ ] **Step 3: Initialize and commit the reviewed baseline**

Run:

```bash
rtk git init -b main
rtk git add .gitignore README.md LinguaTypeCompanion docs patches activate-linguatype.sh build-linguatype.sh configure-languages.sh install-pkg-on-another-mac.sh patch_linguatype.py test-companion.sh SHA256SUMS.txt
rtk git status --short
rtk git commit -m "chore: publish LinguaType companion baseline"
```

Expected: generated apps, bundles, `.superpowers`, `dist`, and `work` are absent from the commit.

- [ ] **Step 4: Create and push the public GitHub repository**

Run:

```bash
rtk gh repo create jasperyang/LinguaType --public --source=. --remote=origin --push --description "A privacy-preserving macOS language-learning companion for Chinese input"
rtk gh repo view jasperyang/LinguaType --json nameWithOwner,visibility,url
```

Expected: `visibility` is `PUBLIC`, the remote points to `jasperyang/LinguaType`, and `main` is pushed.

---

### Task 2: Fixed Learning Models and Preferences

**Files:**
- Create: `LinguaTypeCompanion/Sources/LearningModels.swift`
- Modify: `LinguaTypeCompanion/Sources/Preferences.swift`
- Create: `LinguaTypeCompanion/Tests/LearningModelsTests.swift`
- Create: `LinguaTypeCompanion/Tests/TestSupport.swift`
- Modify: `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`
- Modify: `test-companion.sh`

**Interfaces:**
- Consumes: no feature-specific types.
- Produces: `LearningLanguage`, `LearningDisplayState`, `PhraseTranslation`, `VocabularyCard`, `LocalizedTerm`, `RowStatus`, `CardStatus`, `LoadingPhase`, and `LinguaTypePreferences.isDictionaryLookupEnabled`.

- [ ] **Step 1: Split the test runner and write failing model tests**

```swift
enum LearningModelsTests {
    static func run() {
        Test.expect(LearningLanguage.displayOrder == [.french, .english, .japanese],
                    "fixed language order is French, English, Japanese")
        let state = LearningDisplayState.loading(sourcePhrase: "今天适合散步")
        Test.expect(state.phraseTranslations.map(\.language) == LearningLanguage.displayOrder,
                    "loading state contains all three phrase rows")
        Test.expect(state.vocabularyCards.isEmpty,
                    "loading state starts without fabricated vocabulary")
    }
}
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because the new model types do not exist.

- [ ] **Step 2: Add the minimal fixed-language presentation model**

```swift
enum LearningLanguage: String, CaseIterable, Codable {
    case french = "fr", english = "en", japanese = "ja"
    static let displayOrder: [Self] = [.french, .english, .japanese]
}

struct LearningDisplayState: Equatable {
    var sourcePhrase: String
    var phraseTranslations: [PhraseTranslation]
    var vocabularyCards: [VocabularyCard]
    var phase: LoadingPhase

    static func loading(sourcePhrase: String) -> Self {
        .init(sourcePhrase: sourcePhrase,
              phraseTranslations: LearningLanguage.displayOrder.map {
                  PhraseTranslation(language: $0, text: nil, status: .loading)
              },
              vocabularyCards: [],
              phase: .translatingPhrase)
    }
}
```

Define the remaining structs exactly as named in the design spec, with optional pronunciation fields and explicit loading/failure enums.

- [ ] **Step 3: Replace language-cycle preferences with dictionary privacy preferences**

```swift
private static let dictionaryLookupKey = "LinguaType.dictionaryLookupEnabled"

static var isDictionaryLookupEnabled: Bool {
    if UserDefaults.standard.object(forKey: dictionaryLookupKey) == nil { return true }
    return UserDefaults.standard.bool(forKey: dictionaryLookupKey)
}

static func setDictionaryLookupEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: dictionaryLookupKey)
}
```

Keep the legacy language accessors temporarily so the existing status controller continues compiling in this independently testable task. Task 3 removes those accessors in the same commit that removes their final call sites.

- [ ] **Step 4: Compile all test files and verify the model suite passes**

Change `test-companion.sh` to collect `Sources/*.swift`, remove `Sources/main.swift` from that array, and compile the remaining production files with `Tests/*.swift`. Run `rtk test ./test-companion.sh`.

Expected: model tests and all pre-existing regression tests pass.

- [ ] **Step 5: Commit the model boundary**

```bash
rtk git add LinguaTypeCompanion/Sources/LearningModels.swift LinguaTypeCompanion/Sources/Preferences.swift LinguaTypeCompanion/Tests test-companion.sh
rtk git commit -m "refactor: define fixed three-language learning state"
```

---

### Task 3: Native Menu Bar Item and “A·あ” Icon

**Files:**
- Create: `LinguaTypeCompanion/Sources/MenuBarIcon.swift`
- Modify: `LinguaTypeCompanion/Sources/StatusBarController.swift`
- Modify: `LinguaTypeCompanion/Sources/AppDelegate.swift`
- Create: `LinguaTypeCompanion/Tests/MenuBarTests.swift`
- Modify: `LinguaTypeCompanion/Tests/CompanionRegressionTests.swift`

**Interfaces:**
- Consumes: `LinguaTypePreferences.isEnabled`, `LinguaTypePreferences.isDictionaryLookupEnabled`.
- Produces: `MenuBarIcon.make() -> NSImage`, `StatusBarController.install()`, and the initializer `init(togglePanel:setLearningEnabled:setDictionaryLookupEnabled:modelStatuses:clearCache:showPrivacy:)`.

- [ ] **Step 1: Write failing icon and anchor-removal tests**

```swift
enum MenuBarTests {
    static func run() {
        let image = MenuBarIcon.make()
        Test.expect(image.size == NSSize(width: 18, height: 18), "menu image is 18 pt square")
        Test.expect(image.isTemplate, "menu image follows macOS menu bar tint")

        let controller = StatusBarController(
            togglePanel: {},
            setLearningEnabled: { _ in },
            setDictionaryLookupEnabled: { _ in },
            modelStatuses: { [:] },
            clearCache: {},
            showPrivacy: {}
        )
        controller.install()
        Test.expect(controller.installPath == "macOS menu bar NSStatusItem",
                    "controller installs a native status item")
        Test.expect(Test.reflectedChild(named: "anchorWindow", in: controller) == nil,
                    "legacy floating anchor no longer exists")
    }
}
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because `MenuBarIcon` and the new initializer do not exist.

- [ ] **Step 2: Draw the selected template icon**

Implement `MenuBarIcon.make()` with `NSImage(size:flipped:drawingHandler:)`, centered `A·あ` glyphs, and `image.isTemplate = true`. Draw in black only; never bake light/dark colors into the asset.

- [ ] **Step 3: Replace `AnchorPanel` with `NSStatusItem`**

```swift
private var statusItem: NSStatusItem!

func install() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = statusItem.button else { return }
    button.image = MenuBarIcon.make()
    button.imagePosition = .imageOnly
    button.toolTip = "LinguaType 语言学习 — 点击显示学习卡片，右键打开设置"
    button.setAccessibilityLabel("LinguaType 语言学习")
    button.target = self
    button.action = #selector(handleStatusItemClick(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    installPath = "macOS menu bar NSStatusItem"
}
```

Route left mouse-up to `togglePanel`. Route right mouse-up to a menu containing learning toggle, online lookup toggle, disabled model-status rows, clear cache, privacy, and quit.

Remove `primaryLanguageID`, `secondaryLanguageID`, `cyclePrimary`, and `cycleSecondary` from `Preferences.swift` after this controller no longer references them.

- [ ] **Step 4: Remove launch focus stealing and update app wiring**

Delete `NSApp.activate(ignoringOtherApps: true)` from `AppDelegate`. Inject `clearCache` and `showPrivacy` closures into `StatusBarController`; preserve `.accessory` activation policy.

- [ ] **Step 5: Verify and commit**

Run `rtk test ./test-companion.sh`.

Expected: all menu tests pass and no test or production source refers to `AnchorPanel`, `anchorWindow`, or title `字`.

```bash
rtk git add LinguaTypeCompanion/Sources/MenuBarIcon.swift LinguaTypeCompanion/Sources/StatusBarController.swift LinguaTypeCompanion/Sources/AppDelegate.swift LinguaTypeCompanion/Tests
rtk git commit -m "feat: move LinguaType controls into the macOS menu bar"
```

---

### Task 4: Deterministic Three-Word Extraction

**Files:**
- Create: `LinguaTypeCompanion/Sources/VocabularyExtractor.swift`
- Create: `LinguaTypeCompanion/Tests/VocabularyExtractorTests.swift`

**Interfaces:**
- Consumes: committed Chinese phrase and an optional exposure-count closure.
- Produces: `VocabularyExtractor.extract(from:) -> [VocabularyCandidate]` with one to three unique source-ordered candidates.

- [ ] **Step 1: Write failing selection tests with deterministic candidates**

```swift
let extractor = VocabularyExtractor(exposureCount: { $0 == "天气" ? 4 : 0 })
let selected = extractor.select(candidates: [
    .init(word: "天气", lexicalClass: .noun, sourceOrder: 0),
    .init(word: "适合", lexicalClass: .verb, sourceOrder: 1),
    .init(word: "散步", lexicalClass: .verb, sourceOrder: 2),
    .init(word: "公园", lexicalClass: .noun, sourceOrder: 3),
])
Test.expect(selected.map(\.word) == ["适合", "散步", "公园"],
            "content words are ranked by learning value and returned in source order")
Test.expect(extractor.select(candidates: [.init(word: "的", lexicalClass: nil, sourceOrder: 0)]).isEmpty,
            "single-character function words are filtered")
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because the extractor does not exist.

- [ ] **Step 2: Implement pure filtering and ranking**

Define `VocabularyCandidate` with `word`, optional `NLTag`, and `sourceOrder`. Filter non-Han strings, duplicates, stopwords, numbers, punctuation, and single-character candidates. Score content POS, length two through four, and low exposure count; select the top three, then sort those three by `sourceOrder`.

- [ ] **Step 3: Connect NaturalLanguage tokenization**

Use `NLTokenizer(unit: .word)` and `NLTagger(tagSchemes: [.lexicalClass])` with `.simplifiedChinese`. Convert token ranges to candidates, then call the already-tested pure selector.

- [ ] **Step 4: Add real tokenization cases and verify**

Add cases for `今天的天气很适合散步`, duplicate words, punctuation, a two-word sentence, and a 120-character phrase. Run `rtk test ./test-companion.sh`.

Expected: one to three meaningful unique candidates; the selector never returns more than three.

- [ ] **Step 5: Commit**

```bash
rtk git add LinguaTypeCompanion/Sources/VocabularyExtractor.swift LinguaTypeCompanion/Tests/VocabularyExtractorTests.swift
rtk git commit -m "feat: select up to three learning vocabulary terms"
```

---

### Task 5: Privacy-Safe Dictionary Core and Cache

**Files:**
- Create: `LinguaTypeCompanion/Sources/DictionaryModels.swift`
- Create: `LinguaTypeCompanion/Sources/DictionaryCache.swift`
- Create: `LinguaTypeCompanion/Sources/DictionaryNetworking.swift`
- Create: `LinguaTypeCompanion/Tests/DictionaryPrivacyTests.swift`
- Create: `LinguaTypeCompanion/Tests/DictionaryCacheTests.swift`

**Interfaces:**
- Consumes: `LearningLanguage` and isolated translated terms.
- Produces: validated `DictionaryQuery`, `DictionaryEntry`, `DictionaryProvider`, `DictionaryNetworkClient`, and `DictionaryCache`.

- [ ] **Step 1: Write failing query validation and privacy tests**

```swift
let query = DictionaryQuery(term: "  take a walk。 ", language: .english)
Test.expect(query?.term == "take a walk", "query trims surrounding punctuation")
Test.expect(DictionaryQuery(term: String(repeating: "词", count: 33), language: .english) == nil,
            "query rejects terms longer than 32 characters")
Test.expect(Mirror(reflecting: query!).children.map(\.label).compactMap { $0 }
                == ["term", "language"],
            "network query type has no field capable of carrying source phrase context")
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because query and provider contracts do not exist.

- [ ] **Step 2: Implement safe query and normalized entry types**

```swift
struct DictionaryQuery: Hashable, Codable {
    let term: String
    let language: LearningLanguage

    init?(term: String, language: LearningLanguage) {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty, normalized.count <= 32 else { return nil }
        self.term = normalized
        self.language = language
    }
}

protocol DictionaryProvider {
    var id: String { get }
    func makeRequest(for query: DictionaryQuery) throws -> URLRequest
    func decode(_ data: Data, response: HTTPURLResponse, query: DictionaryQuery) throws -> DictionaryEntry?
}
```

`DictionaryEntry` contains `term`, `partOfSpeech`, up to three `senses`, `ipa`, `kana`, and provider attribution.

- [ ] **Step 3: Implement bounded networking and redacted diagnostics**

Use an actor-backed `DictionaryNetworkClient` with four global permits and two permits per provider. Set `URLRequest.timeoutInterval = 4`. Retry once only for `URLError.timedOut`, connectivity errors, and 5xx. Log provider ID, status, elapsed milliseconds, and cache hit; never interpolate `DictionaryQuery.term`.

- [ ] **Step 4: Write failing cache expiry tests, then implement disk cache**

```swift
let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
let cache = DictionaryCache(fileURL: tempURL, now: clock.now)
cache.store(.success(entry), for: key)
clock.advance(days: 29)
Test.expect(cache.value(for: key) == .success(entry), "success cache lives for 30 days")
clock.advance(days: 2)
Test.expect(cache.value(for: key) == nil, "expired success cache is removed")
```

Store a versioned Codable document atomically. Use 30 days for successful entries and 10 minutes for no-result or transient failure. `clear()` deletes only this cache file.

Add this mutable clock to `TestSupport.swift` so expiry tests do not sleep:

```swift
final class TestClock {
    private(set) var current: Date
    init(now: Date) { current = now }
    var now: () -> Date { { self.current } }
    func advance(days: Double) { current.addTimeInterval(days * 86_400) }
}
```

- [ ] **Step 5: Verify and commit**

Run `rtk test ./test-companion.sh`.

Expected: validation, privacy, retry, redacted logging, cache expiry, and clear tests pass.

```bash
rtk git add LinguaTypeCompanion/Sources/DictionaryModels.swift LinguaTypeCompanion/Sources/DictionaryCache.swift LinguaTypeCompanion/Sources/DictionaryNetworking.swift LinguaTypeCompanion/Tests
rtk git commit -m "feat: add privacy-safe dictionary core and cache"
```

---

### Task 6: English, French, Chinese, and Japanese Dictionary Adapters

**Files:**
- Create: `LinguaTypeCompanion/Sources/WiktionaryDictionaryProvider.swift`
- Create: `LinguaTypeCompanion/Sources/EnglishDictionaryProvider.swift`
- Create: `LinguaTypeCompanion/Sources/JapaneseDictionaryProvider.swift`
- Create: `LinguaTypeCompanion/Sources/RomajiTransliterator.swift`
- Create: `LinguaTypeCompanion/Tests/DictionaryProviderTests.swift`
- Create: `LinguaTypeCompanion/Tests/Fixtures/zh-wiktionary.json`
- Create: `LinguaTypeCompanion/Tests/Fixtures/fr-wiktionary.json`
- Create: `LinguaTypeCompanion/Tests/Fixtures/free-dictionary.json`
- Create: `LinguaTypeCompanion/Tests/Fixtures/jotoba.json`

**Interfaces:**
- Consumes: `DictionaryProvider`, `DictionaryQuery`, `DictionaryEntry`.
- Produces: four provider instances and `RomajiTransliterator.romanize(kana:) -> String?`.

- [ ] **Step 1: Capture minimal real response fixtures**

Use `rtk curl` to inspect representative provider responses for `适合`, `convenir`, `suit`, and `適する`. Add reduced fixtures with `apply_patch`, preserving real nesting and value types while omitting unrelated bulk data. Fixtures contain no user phrase.

- [ ] **Step 2: Write failing request and decode tests**

```swift
let english = EnglishDictionaryProvider()
let request = try! english.makeRequest(for: DictionaryQuery(term: "suit", language: .english)!)
Test.expect(request.url?.host == "api.dictionaryapi.dev", "English uses Free Dictionary API")
let entry = try! english.decode(fixture("free-dictionary"), response: ok(request), query: query)
Test.expect(entry?.ipa?.isEmpty == false, "English parser returns IPA")
Test.expect((entry?.senses.count ?? 0) >= 2, "English parser returns multiple senses")

let japanese = JapaneseDictionaryProvider()
let jpEntry = try! japanese.decode(fixture("jotoba"), response: ok(jpRequest), query: jpQuery)
Test.expect(jpEntry?.kana == "てきする", "Japanese parser returns kana")
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because the adapters do not exist.

- [ ] **Step 3: Implement request builders with fixed endpoints**

- Chinese: `https://zh.wiktionary.org/w/api.php` with `action=parse`, `prop=text`, `format=json`, and one `page` term.
- French: `https://fr.wiktionary.org/w/api.php` with the same fixed parameters.
- English: `https://api.dictionaryapi.dev/api/v2/entries/en/{percentEncodedTerm}`.
- Japanese: POST `https://jotoba.de/api/search/words` with JSON `{ "query": term, "language": "English", "no_english": false }`.

Set a descriptive `User-Agent` containing the public repository URL for Wikimedia and Jotoba requests.

- [ ] **Step 4: Implement parsers and local romanization**

Decode English and Jotoba JSON into typed private response structs. For MediaWiki, decode `parse.text["*"]`, extract the language section, part of speech, IPA, and the first three numbered meanings; strip tags and decode HTML entities before creating `DictionaryEntry`. Use `CFStringTransform` transliteration for kana-to-Latin, lowercase and normalize whitespace, and return `nil` when input cannot be transformed.

- [ ] **Step 5: Verify missing-field and malformed-response behavior**

Add tests for absent IPA, missing kana, no page, malformed JSON, 404, and an empty meanings list. Run `rtk test ./test-companion.sh`.

Expected: valid fixtures produce normalized entries; missing optional fields remain `nil`; missing entries return `nil`; malformed data throws a provider decode error.

- [ ] **Step 6: Commit**

```bash
rtk git add LinguaTypeCompanion/Sources/*DictionaryProvider.swift LinguaTypeCompanion/Sources/RomajiTransliterator.swift LinguaTypeCompanion/Tests/DictionaryProviderTests.swift LinguaTypeCompanion/Tests/Fixtures
rtk git commit -m "feat: connect multilingual dictionary providers"
```

---

### Task 7: Priority Translation Pipeline and Progressive Coordinator

**Files:**
- Create: `LinguaTypeCompanion/Sources/TranslationJobQueue.swift`
- Modify: `LinguaTypeCompanion/Sources/LearningCoordinator.swift`
- Create: `LinguaTypeCompanion/Tests/TranslationJobQueueTests.swift`
- Modify: `LinguaTypeCompanion/Tests/LearningModelsTests.swift`

**Interfaces:**
- Consumes: `LearningDisplayState`, `VocabularyExtractor`, providers, cache, `RomajiTransliterator`, and the existing SwiftUI Translation bridge.
- Produces: progressive `LearningCoordinator.onUpdate`, fixed priority translation scheduling, and last-result retention.

- [ ] **Step 1: Write failing queue-order tests**

```swift
var queue = TranslationJobQueue()
queue.enqueue(.init(generation: 1, purpose: .definition(cardID: 0, language: .english, senseIndex: 0), text: "a condition"))
queue.enqueue(.init(generation: 1, purpose: .term(cardID: 0, language: .japanese), text: "适合"))
queue.enqueue(.init(generation: 1, purpose: .phrase(language: .french), text: "今天适合散步"))
Test.expect(queue.popNext()?.purpose == .phrase(language: .french), "phrase translation has highest priority")
Test.expect(queue.popNext()?.purpose == .term(cardID: 0, language: .japanese), "term translation precedes definition localization")
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because the queue does not exist.

- [ ] **Step 2: Implement stable priority FIFO scheduling**

Define `TranslationPurpose` exactly as `phrase(language:)`, `term(cardID:language:)`, and `definition(cardID:language:senseIndex:)`. Define `TranslationJob` with `generation`, `purpose`, and `text`; the queue adds a monotonically increasing internal sequence number. `popNext()` sorts by purpose priority and then sequence number. `cancel(generation:)` removes stale work from prior committed phrases.

- [ ] **Step 3: Replace two-language coordinator dictionaries with display state**

On `commit(text:)`:

```swift
generation &+= 1
let currentGeneration = generation
var state = LearningDisplayState.loading(sourcePhrase: text)
state.vocabularyCards = vocabularyExtractor.extract(from: text).map(VocabularyCard.loading)
publish(state)
LearningLanguage.displayOrder.forEach {
    translationQueue.enqueue(.init(
        generation: currentGeneration,
        purpose: .phrase(language: $0),
        text: text
    ))
}
```

After phrase jobs, enqueue each source keyword translation to French, English, and Japanese. A completed term creates a `DictionaryQuery` for that language and starts an independent dictionary lookup when online lookup is enabled.

- [ ] **Step 4: Localize dictionary senses without leaking phrases**

For each returned foreign-language sense, enqueue definition-to-`zh-Hans` jobs after all pending phrase and term jobs. Chinese Wiktionary senses do not need reverse translation. Feed normalized terms, pronunciations, and up to three Chinese senses into the matching `VocabularyCard`.

- [ ] **Step 5: Add deterministic sense matching and failure isolation**

Score matching POS, exact translated headword, and normalized gloss overlap. Require the best score to exceed the runner-up by two points; otherwise leave `contextualSense` nil. A translation or dictionary failure updates only its row/card and then continues the queue.

- [ ] **Step 6: Verify progressive updates and privacy boundaries**

Use fake translator and dictionary provider implementations to assert update order: initial skeleton, three phrase rows, term entries, then localized senses. Assert fake providers receive only `DictionaryQuery`, never source phrase state. Run `rtk test ./test-companion.sh`.

Expected: fixed three-language state is progressively populated; stale generations cannot mutate the latest state.

- [ ] **Step 7: Commit**

```bash
rtk git add LinguaTypeCompanion/Sources/TranslationJobQueue.swift LinguaTypeCompanion/Sources/LearningCoordinator.swift LinguaTypeCompanion/Tests
rtk git commit -m "feat: orchestrate three-language learning results"
```

---

### Task 8: Layered Scrollable Panel and Auto-Hide

**Files:**
- Create: `LinguaTypeCompanion/Sources/LearningPanelContentView.swift`
- Create: `LinguaTypeCompanion/Sources/PanelAutoHideController.swift`
- Modify: `LinguaTypeCompanion/Sources/TranslationPanel.swift`
- Create: `LinguaTypeCompanion/Tests/PanelPresentationTests.swift`

**Interfaces:**
- Consumes: `LearningDisplayState` and caret geometry.
- Produces: nonactivating 520 px panel with fixed phrase content, scrollable vocabulary cards, hover-controlled auto-hide, and last-result reopening.

- [ ] **Step 1: Write failing presentation and timer tests**

```swift
let view = LearningPanelContentView()
let fixture = LearningDisplayState.makeTestFixture(cardCount: 3)
view.apply(fixture)
Test.expect(view.phraseRows.count == 3, "panel renders three fixed phrase rows")
Test.expect(view.vocabularyCardViews.count == 3, "panel renders three vocabulary cards")

let scheduler = TestScheduler()
let timer = PanelAutoHideController(interval: 12, scheduler: scheduler)
timer.start { hidden = true }
scheduler.advance(by: 11.9)
Test.expect(!hidden, "panel remains visible before 12 seconds")
timer.pointerEntered()
scheduler.advance(by: 20)
Test.expect(!hidden, "hover pauses auto-hide")
```

Run `rtk test ./test-companion.sh`.

Expected: compile fails because the content view and timer do not exist.

Define `LearningDisplayState.makeTestFixture(cardCount:)` in `PanelPresentationTests.swift` as a test-only extension that creates three successful phrase rows and the requested number of complete vocabulary cards.

Define `PanelTimerScheduling` in production with `schedule(after:_:) -> CancellableTimer`, and define `TestScheduler` in `PanelPresentationTests.swift` with an in-memory deadline queue and `advance(by:)`. `PanelAutoHideController` depends only on that protocol; its default scheduler wraps `Timer` on the main run loop.

- [ ] **Step 2: Build the selected layered AppKit content view**

Create a dark `NSVisualEffectView` hierarchy with title, two-line source, fixed translation stack, separator, and `NSScrollView` containing vocabulary cards. Cards render Chinese word/POS, two to three senses, optional contextual badge, and French/English/Japanese term rows with pronunciation.

- [ ] **Step 3: Implement bounded panel geometry**

Set width to 520. Compute height from intrinsic content, capped at `min(560, visibleFrame.height * 0.60)`. Use the screen containing the caret, place below with a 10 px gap, flip above when necessary, and clamp both axes to a 6 px visible-frame margin.

- [ ] **Step 4: Make scrolling interactive without stealing focus**

Use a `.nonactivatingPanel` subclass whose `canBecomeKey` and `canBecomeMain` return false. Enable mouse events and the scroll view; install an `NSTrackingArea` to notify `PanelAutoHideController` on enter/exit. Keep the hidden SwiftUI translation host attached outside the replaceable content stack.

- [ ] **Step 5: Implement 12-second hiding and reopening**

Start the timer when a phrase row first becomes success or explicit failure. Pause/resume on hover. `hide()` does not clear `lastDisplayState`; `showLastResult(near:)` reapplies and displays it. A new commit cancels the old timer and starts a new generation.

- [ ] **Step 6: Verify layout, behavior, and commit**

Run `rtk test ./test-companion.sh`.

Expected: panel tests cover three rows, three cards, scroll cap, top/bottom placement, hover pause, hide, and reopen; all suites pass.

```bash
rtk git add LinguaTypeCompanion/Sources/LearningPanelContentView.swift LinguaTypeCompanion/Sources/PanelAutoHideController.swift LinguaTypeCompanion/Sources/TranslationPanel.swift LinguaTypeCompanion/Tests/PanelPresentationTests.swift
rtk git commit -m "feat: redesign the language learning panel"
```

---

### Task 9: Safe Companion Build, Documentation, and Real Acceptance

**Files:**
- Create: `build-companion.sh`
- Modify: `build-linguatype.sh`
- Modify: `README.md`
- Modify: `LinguaTypeCompanion/Resources/Info.plist`

**Interfaces:**
- Consumes: all implemented production files and passing tests.
- Produces: installed and relaunched `~/Applications/LinguaTypeCompanion.app`, updated public documentation, and final evidence.

- [ ] **Step 1: Write the Companion-only build script**

The script compiles `LinguaTypeCompanion/Sources/*.swift`, links Cocoa, Carbon, Foundation, ApplicationServices, SwiftUI, Translation, and NaturalLanguage, copies Info.plist, ad-hoc signs the app, verifies the signature, atomically replaces `~/Applications/LinguaTypeCompanion.app`, and kickstarts `io.linguatype.companion`. It must not reference or modify `work/rimes`.

- [ ] **Step 2: Update build metadata and documentation**

Document:

- “A·あ” menu bar controls and right-click menu.
- Fixed French/English/Japanese rows.
- Up to three rich vocabulary cards and pronunciation formats.
- Exact dictionary providers and attribution links.
- The guarantee that only isolated terms are sent to dictionaries.
- `rtk test ./test-companion.sh` and `rtk run ./build-companion.sh` as the safe development workflow.
- Apple Translation model download/failure behavior.

Update stale `build-linguatype.sh` completion text so it no longer promises the “字” anchor or two configurable languages.

- [ ] **Step 3: Run automated verification**

Run:

```bash
rtk test ./test-companion.sh
rtk run ./build-companion.sh
rtk run codesign --verify --deep --strict "$HOME/Applications/LinguaTypeCompanion.app"
rtk run launchctl print gui/$(id -u)/io.linguatype.companion
```

Expected: all tests pass, signature verification exits zero, and LaunchAgent state is running.

- [ ] **Step 4: Perform real TextEdit acceptance**

With TextEdit frontmost and system Pinyin active, enter `今天的天气很适合散步` and verify:

1. Input focus stays in TextEdit.
2. The panel appears near the insertion point.
3. French, English, and Japanese rows are present.
4. One to three cards progressively populate with Chinese senses and pronunciations.
5. Vocabulary scrolls while header and phrase rows stay fixed.
6. Hover pauses hiding; exit allows hiding; left-click “A·あ” restores the last result.
7. Right-click opens the settings menu.
8. No “字” anchor exists on any screen.

Capture WindowServer geometry and Companion logs with `rtk`-wrapped commands. Redact any committed phrase from the final report.

- [ ] **Step 5: Verify degraded states**

Run parser tests with no-result fixtures, disable online lookup from the menu, and verify no dictionary request occurs. Confirm missing Apple model states affect only their own language rows. Confirm cached results remain available while lookup is paused.

- [ ] **Step 6: Commit and push final implementation**

```bash
rtk git add build-companion.sh build-linguatype.sh README.md LinguaTypeCompanion
rtk git commit -m "docs: document LinguaType learning companion"
rtk git status --short
rtk git push origin main
rtk gh repo view jasperyang/LinguaType --json visibility,url,defaultBranchRef
```

Expected: working tree is clean except explicitly preserved ignored artifacts; public GitHub `main` contains all implementation commits.
