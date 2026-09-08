import Cocoa
import SwiftUI
import Translation

final class LearningCoordinator {
    static let shared = LearningCoordinator()

    var onUpdate: ((LearningDisplayState?) -> Void)?
    private(set) var languageSelection: LanguageSelection

    private weak var panel: TranslationPanel?
    private var generation: UInt64 = 0
    private var debounceWork: DispatchWorkItem?
    private var state: LearningDisplayState?
    private var queue = TranslationJobQueue()
    private var pendingLookups = 0
    private let extractor = VocabularyExtractor()
    private let dictionaryService = DictionaryLookupService()
    private let workPlanner = TranslationWorkPlanner()
    private let persistSelection: (LanguageSelection) -> Void
    private let lessonPlanner: TutorLessonPlanner
    private let learnerLevel: (LearningLanguage) -> LearnerLevel
    private let persistLearnerLevel: (LearnerLevel, LearningLanguage) -> Void

    private var bridgeModel: LinguaTypeTranslationBridgeModel!
    private var bridgeHost: NSHostingView<LinguaTypeTranslationBridgeView>!

    init(
        languageSelection: LanguageSelection = LinguaTypePreferences.languageSelection(),
        persistSelection: @escaping (LanguageSelection) -> Void = {
            LinguaTypePreferences.setLanguageSelection($0)
        },
        lessonPlanner: TutorLessonPlanner = TutorLessonPlanner(),
        learnerLevel: @escaping (LearningLanguage) -> LearnerLevel = {
            LinguaTypePreferences.learnerLevel(for: $0)
        },
        persistLearnerLevel: @escaping (LearnerLevel, LearningLanguage) -> Void = {
            LinguaTypePreferences.setLearnerLevel($0, for: $1)
        }
    ) {
        self.languageSelection = languageSelection
        self.persistSelection = persistSelection
        self.lessonPlanner = lessonPlanner
        self.learnerLevel = learnerLevel
        self.persistLearnerLevel = persistLearnerLevel
        bridgeModel = LinguaTypeTranslationBridgeModel(coordinator: self)
        bridgeHost = NSHostingView(rootView: LinguaTypeTranslationBridgeView(model: bridgeModel))
        bridgeHost.translatesAutoresizingMaskIntoConstraints = false
        bridgeHost.alphaValue = 0.001
    }

    func install(into hostView: NSView) {
        guard bridgeHost.superview == nil else { return }
        hostView.addSubview(bridgeHost)
        NSLayoutConstraint.activate([
            bridgeHost.widthAnchor.constraint(equalToConstant: 1),
            bridgeHost.heightAnchor.constraint(equalToConstant: 1),
            bridgeHost.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            bridgeHost.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
    }

    func attach(panel: TranslationPanel) { self.panel = panel }

    func idle() {
        generation &+= 1
        debounceWork?.cancel()
        debounceWork = nil
        bridgeModel.cancel()
        queue.removeAll()
        state = nil
        onUpdate?(nil)
    }

    func commit(text: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard LinguaTypePreferences.isEnabled else { idle(); return }

        generation &+= 1
        let currentGeneration = generation
        debounceWork?.cancel()
        bridgeModel.cancel()
        queue.removeAll()
        pendingLookups = 0

        var next = LearningDisplayState.loading(
            sourcePhrase: text,
            selection: languageSelection
        )
        next.vocabularyCards = extractor.extract(from: text).map {
            VocabularyCard.loading(source: $0.word)
        }
        state = next
        publish()

        if LinguaTypePreferences.isDictionaryLookupEnabled {
            for index in next.vocabularyCards.indices {
                lookupChineseCard(index: index, generation: currentGeneration)
            }
        }

        let work = DispatchWorkItem { [weak self] in
            self?.enqueueMissingTranslations(generation: currentGeneration)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    func clearDictionaryCache() { dictionaryService.clearCache() }

    func setLanguageSelection(_ selection: LanguageSelection) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard selection != languageSelection else { return }
        languageSelection = selection
        persistSelection(selection)

        guard var current = state else { return }
        let existingRows = Dictionary(
            uniqueKeysWithValues: current.phraseTranslations.map { ($0.language, $0) }
        )
        current.phraseTranslations = selection.orderedLanguages.map { language in
            existingRows[language]
                ?? PhraseTranslation(language: language, text: nil, status: .loading)
        }
        current.lesson = lesson(for: current)
        state = current
        publish()

        debounceWork?.cancel()
        debounceWork = nil
        bridgeModel.cancel()
        queue.removeAll()
        enqueueMissingTranslations(generation: generation)
    }

    func setLearnerLevel(_ level: LearnerLevel, for language: LearningLanguage) {
        dispatchPrecondition(condition: .onQueue(.main))
        persistLearnerLevel(level, language)
        guard var current = state else { return }
        current.lesson = lesson(for: current)
        state = current
        publish()
    }

    func lesson(for state: LearningDisplayState) -> MicroLesson? {
        lessonPlanner.plan(
            from: state,
            primaryLanguage: languageSelection.primary,
            level: learnerLevel(languageSelection.primary)
        )
    }

    func modelStatuses() -> [LearningLanguage: String] {
        guard let state else {
            return Dictionary(uniqueKeysWithValues: LearningLanguage.displayOrder.map { ($0, "按需准备") })
        }
        return Dictionary(uniqueKeysWithValues: state.phraseTranslations.map { row in
            let value: String
            switch row.status {
            case .loading: value = "准备中"
            case .success: value = "可用"
            case .failure: value = "不可用"
            }
            return (row.language, value)
        })
    }

    private func enqueueMissingTranslations(generation: UInt64) {
        guard self.generation == generation, let state else { return }
        workPlanner.missingJobs(
            state: state,
            selection: languageSelection,
            generation: generation
        ).forEach { queue.enqueue($0) }
        beginNextJob()
    }

    private func beginNextJob() {
        guard bridgeModel.request == nil else { return }
        queue.discard(olderThan: generation)
        guard let job = queue.popNext() else {
            finishIfReady()
            return
        }
        bridgeModel.submit(job: job)
    }

    fileprivate func translationCompleted(_ text: String, job: TranslationJob) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard job.generation == generation else { beginNextJob(); return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch job.purpose {
        case .phrase(let language):
            updatePhrase(language: language, text: cleaned, status: .success)
        case .term(let cardID, let language):
            updateTerm(cardID: cardID, language: language, text: cleaned)
            if LinguaTypePreferences.isDictionaryLookupEnabled {
                lookupTargetCard(index: cardID, language: language, term: cleaned, generation: job.generation)
            }
        case .definition(let cardID, _, _):
            appendChineseSense(cleaned, cardID: cardID)
        }
        bridgeModel.completeCurrent()
        publish()
        beginNextJob()
    }

    fileprivate func translationFailed(_ message: String, job: TranslationJob) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard job.generation == generation else { bridgeModel.completeCurrent(); beginNextJob(); return }
        if case .phrase(let language) = job.purpose {
            updatePhrase(language: language, text: nil, status: .failure("翻译模型未准备好"))
        }
        bridgeModel.completeCurrent()
        publish()
        beginNextJob()
    }

    private func lookupChineseCard(index: Int, generation: UInt64) {
        guard let state, state.vocabularyCards.indices.contains(index),
              let query = DictionaryQuery(term: state.vocabularyCards[index].source, language: .chinese) else { return }
        lookup(providers: [WiktionaryDictionaryProvider(language: .chinese)], query: query, cardID: index, language: nil, generation: generation)
    }

    private func lookupTargetCard(index: Int, language: LearningLanguage, term: String, generation: UInt64) {
        let dictionaryLanguage: DictionaryLanguage
        let providers: [any DictionaryProvider]
        switch language {
        case .french:
            dictionaryLanguage = .french
            providers = [WiktionaryDictionaryProvider(language: .french)]
        case .english:
            dictionaryLanguage = .english
            providers = [EnglishDictionaryProvider(), WiktionaryDictionaryProvider(language: .english)]
        case .japanese:
            dictionaryLanguage = .japanese
            providers = [JapaneseDictionaryProvider()]
        }
        guard let query = DictionaryQuery(term: term, language: dictionaryLanguage) else { return }
        lookup(providers: providers, query: query, cardID: index, language: language, generation: generation)
    }

    private func lookup(
        providers: [any DictionaryProvider],
        query: DictionaryQuery,
        cardID: Int,
        language: LearningLanguage?,
        generation: UInt64
    ) {
        pendingLookups += 1
        dictionaryService.lookup(providers: providers, query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingLookups = max(0, self.pendingLookups - 1)
                guard self.generation == generation else { return }
                if case .success(let entry?) = result {
                    self.applyDictionaryEntry(entry, cardID: cardID, language: language, generation: generation)
                }
                self.publish()
                self.finishIfReady()
            }
        }
    }

    private func applyDictionaryEntry(
        _ entry: DictionaryEntry,
        cardID: Int,
        language: LearningLanguage?,
        generation: UInt64
    ) {
        guard var current = state, current.vocabularyCards.indices.contains(cardID) else { return }
        if let language {
            if let index = current.vocabularyCards[cardID].terms.firstIndex(where: { $0.language == language }) {
                var term = current.vocabularyCards[cardID].terms[index]
                term.ipa = entry.ipa
                term.kana = entry.kana
                if let kana = entry.kana { term.romanization = RomajiTransliterator.romanize(kana: kana) }
                current.vocabularyCards[cardID].terms[index] = term
            }
            if current.vocabularyCards[cardID].chineseSenses.isEmpty {
                let sourceID = language == .french ? "fr" : "en"
                for (senseIndex, sense) in entry.senses.prefix(3).enumerated() {
                    queue.enqueue(TranslationJob(
                        generation: generation,
                        purpose: .definition(cardID: cardID, language: language, senseIndex: senseIndex),
                        text: sense,
                        sourceLanguageID: sourceID,
                        targetLanguageID: "zh-Hans"
                    ))
                }
            }
        } else {
            current.vocabularyCards[cardID].partOfSpeech = entry.partOfSpeech
            current.vocabularyCards[cardID].chineseSenses = Array(entry.senses.prefix(3))
        }
        current.vocabularyCards[cardID].status = .partial
        current.lesson = lesson(for: current)
        state = current
        beginNextJob()
    }

    private func updatePhrase(language: LearningLanguage, text: String?, status: RowStatus) {
        guard var current = state,
              let index = current.phraseTranslations.firstIndex(where: { $0.language == language }) else { return }
        current.phraseTranslations[index].text = text
        current.phraseTranslations[index].status = status
        current.phase = .loadingVocabulary
        current.lesson = lesson(for: current)
        state = current
    }

    private func updateTerm(cardID: Int, language: LearningLanguage, text: String) {
        guard var current = state, current.vocabularyCards.indices.contains(cardID) else { return }
        let term = LocalizedTerm(language: language, term: text, ipa: nil, kana: nil, romanization: nil)
        current.vocabularyCards[cardID].terms.removeAll { $0.language == language }
        current.vocabularyCards[cardID].terms.append(term)
        current.vocabularyCards[cardID].status = .partial
        current.lesson = lesson(for: current)
        state = current
    }

    private func appendChineseSense(_ sense: String, cardID: Int) {
        guard !sense.isEmpty, var current = state, current.vocabularyCards.indices.contains(cardID) else { return }
        if !current.vocabularyCards[cardID].chineseSenses.contains(sense),
           current.vocabularyCards[cardID].chineseSenses.count < 3 {
            current.vocabularyCards[cardID].chineseSenses.append(sense)
        }
        current.lesson = lesson(for: current)
        state = current
    }

    private func finishIfReady() {
        guard queue.isEmpty, bridgeModel.request == nil, pendingLookups == 0, var current = state else { return }
        current.phase = .complete
        for index in current.vocabularyCards.indices {
            current.vocabularyCards[index].status = current.vocabularyCards[index].terms.isEmpty
                ? .unavailable("暂无详细词典释义") : .complete
        }
        state = current
        publish()
    }

    private func publish() { onUpdate?(state) }
}

final class LinguaTypeTranslationBridgeModel: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id: UInt64
        let job: TranslationJob
        let configuration: TranslationSession.Configuration
    }

    @Published private(set) var request: Request?
    private weak var coordinator: LearningCoordinator?
    private var serial: UInt64 = 0

    init(coordinator: LearningCoordinator) { self.coordinator = coordinator }

    func cancel() { request = nil }
    func completeCurrent() { request = nil }

    func submit(job: TranslationJob) {
        serial &+= 1
        request = Request(
            id: serial,
            job: job,
            configuration: TranslationSession.Configuration(
                source: Locale.Language(identifier: job.sourceLanguageID),
                target: Locale.Language(identifier: job.targetLanguageID)
            )
        )
    }

    func run(session: TranslationSession, request: Request) async {
        guard await isCurrent(request.id) else { return }
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(request.job.text)
            try Task.checkCancellation()
            guard await isCurrent(request.id) else { return }
            await MainActor.run { [weak coordinator] in
                coordinator?.translationCompleted(response.targetText, job: request.job)
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run { [weak coordinator] in
                coordinator?.translationFailed(error.localizedDescription, job: request.job)
            }
        }
    }

    private func isCurrent(_ id: UInt64) async -> Bool {
        await MainActor.run { [weak self] in self?.request?.id == id }
    }
}

struct LinguaTypeTranslationBridgeView: View {
    @ObservedObject var model: LinguaTypeTranslationBridgeModel

    var body: some View {
        Group {
            if let request = model.request {
                Color.clear
                    .translationTask(request.configuration) { session in
                        await model.run(session: session, request: request)
                    }
                    .id(request.id)
            } else {
                Color.clear
            }
        }
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .allowsHitTesting(false)
    }
}
