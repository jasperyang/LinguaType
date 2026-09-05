import Foundation
import NaturalLanguage
import SwiftUI
import Translation

/// Owns the translation state and the Apple Translation bridge. Pulled out
/// of the original LinguaTypeLearning.swift so it can run in the standalone
/// Companion process instead of inside IMK. Same semantics: 280 ms debounce,
/// per-session LRU cache, exposure log on disk, vocabulary picked from the
/// committed Chinese via NLTokenizer.
final class LearningCoordinator {
    static let shared = LearningCoordinator()

    enum DisplayState: Equatable {
        case idle
        case loading(Source)
        case translated(Source, Translations)
    }

    struct Source: Equatable {
        let phrase: String
        let vocabulary: String?
    }

    struct Translations: Equatable {
        var primary: String?
        var secondary: String?
        var vocabulary: [String?]
    }

    enum Kind: Equatable {
        case phrase(target: String)
        case vocabulary(target: String, source: String)

        var targetLanguageID: String {
            switch self {
            case let .phrase(target): return target
            case let .vocabulary(target, _): return target
            }
        }
    }

    var onUpdate: ((DisplayState) -> Void)?

    private weak var panel: TranslationPanel?
    private var generation: UInt64 = 0
    private var debounceWork: DispatchWorkItem?
    private var currentSource = Source(phrase: "", vocabulary: nil)
    private var phraseTranslations: [String: String] = [:]
    private var vocabularyTranslations: [String: String] = [:]
    private var cache: [String: String] = [:]
    private var bridgeModel: LinguaTypeTranslationBridgeModel!
    private var bridgeHost: NSHostingView<LinguaTypeTranslationBridgeView>!

    private init() {
        bridgeModel = LinguaTypeTranslationBridgeModel(coordinator: self)
        bridgeHost = NSHostingView(rootView: LinguaTypeTranslationBridgeView(model: bridgeModel))
        bridgeHost.translatesAutoresizingMaskIntoConstraints = false
        bridgeHost.alphaValue = 0.001
    }

    /// The coordinator must own the SwiftUI translation host view, otherwise
    /// TranslationSession has no view lifecycle to attach to and silently
    /// returns empty responses. AppDelegate hands us a containing view that
    /// is already on-screen so the host has somewhere to live.
    func install(into hostView: NSView) {
        hostView.addSubview(bridgeHost)
        NSLayoutConstraint.activate([
            bridgeHost.widthAnchor.constraint(equalToConstant: 1),
            bridgeHost.heightAnchor.constraint(equalToConstant: 1),
            bridgeHost.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            bridgeHost.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
    }

    func attach(panel: TranslationPanel) {
        self.panel = panel
    }

    func idle() {
        generation &+= 1
        debounceWork?.cancel()
        debounceWork = nil
        currentSource = Source(phrase: "", vocabulary: nil)
        phraseTranslations.removeAll()
        vocabularyTranslations.removeAll()
        onUpdate?(.idle)
    }

    /// Called by the AX observer whenever a focused field commits new text.
    func commit(text: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard LinguaTypePreferences.isEnabled else { idle(); return }

        let phrase = text
        let vocab = extractVocabulary(from: phrase)
        let source = Source(phrase: phrase, vocabulary: vocab)
        currentSource = source

        generation &+= 1
        debounceWork?.cancel()
        bridgeModel.cancel()
        phraseTranslations.removeAll()
        vocabularyTranslations.removeAll()
        onUpdate?(.loading(source))

        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            self.beginNextJob()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    fileprivate func translationCompleted(_ text: String, _ kind: Kind) {
        dispatchPrecondition(condition: .onQueue(.main))
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cache[cacheKey(kind: kind)] = cleaned
        switch kind {
        case let .phrase(target):
            phraseTranslations[target] = cleaned
        case let .vocabulary(target, source):
            vocabularyTranslations[target] = cleaned
            LinguaTypeExposureStore.shared.record(source: source,
                                                  target: cleaned,
                                                  language: target)
        }
        onUpdate?(.translated(currentSource, currentTranslations()))
        beginNextJob()
    }

    fileprivate func translationFailed(_ message: String, _ kind: Kind) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch kind {
        case let .phrase(target):
            phraseTranslations[target] = "翻译模型未准备好"
        case .vocabulary:
            break
        }
        onUpdate?(.translated(currentSource, currentTranslations()))
        beginNextJob()
    }

    private func currentTranslations() -> Translations {
        Translations(
            primary: phraseTranslations[LinguaTypePreferences.primaryLanguageID],
            secondary: LinguaTypePreferences.secondaryLanguageID
                .flatMap { phraseTranslations[$0] },
            vocabulary: vocabularyTranslationsList()
        )
    }

    private func vocabularyTranslationsList() -> [String?] {
        var out: [String?] = []
        out.append(vocabularyTranslations[LinguaTypePreferences.primaryLanguageID])
        if let secondary = LinguaTypePreferences.secondaryLanguageID {
            out.append(vocabularyTranslations[secondary])
        }
        return out
    }

    private func beginNextJob() {
        guard generation > 0 else { return }
        let targets = uniqueTargets()
        for target in targets {
            let key = cacheKeyPhrase(target)
            if let cached = cache[key] {
                phraseTranslations[target] = cached
                continue
            }
            bridgeModel.submitJob(
                kind: .phrase(target: target),
                phrase: currentSource.phrase,
                vocabulary: currentSource.vocabulary ?? "",
                sourceLanguageID: "zh-Hans",
                targetLanguageID: target
            )
            return
        }
        if let vocab = currentSource.vocabulary {
            for target in targets {
                let key = cacheKeyVocab(vocab, target)
                if let cached = cache[key] {
                    vocabularyTranslations[target] = cached
                    continue
                }
                bridgeModel.submitJob(
                    kind: .vocabulary(target: target, source: vocab),
                    phrase: vocab,
                    vocabulary: vocab,
                    sourceLanguageID: "zh-Hans",
                    targetLanguageID: target
                )
                return
            }
        }
    }

    private func uniqueTargets() -> [String] {
        var result: [String] = []
        for candidate in [LinguaTypePreferences.primaryLanguageID,
                          LinguaTypePreferences.secondaryLanguageID].compactMap({ $0 }) {
            if candidate.lowercased().hasPrefix("zh") { continue }
            if !result.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                result.append(candidate)
            }
        }
        return result
    }

    private func cacheKeyPhrase(_ target: String) -> String {
        "phrase:\(target):\(currentSource.phrase)"
    }
    private func cacheKeyVocab(_ vocab: String, _ target: String) -> String {
        "vocab:\(target):\(vocab)"
    }
    private func cacheKey(kind: Kind) -> String {
        switch kind {
        case let .phrase(target): return cacheKeyPhrase(target)
        case let .vocabulary(target, source): return cacheKeyVocab(source, target)
        }
    }

    private func extractVocabulary(from text: String) -> String? {
        let stopwords: Set<String> = [
            "这个", "那个", "一下", "然后", "就是", "还是", "已经", "可以", "需要",
            "我们", "你们", "他们", "今天", "现在", "一个", "一些", "觉得", "如果", "因为"
        ]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.simplifiedChinese)
        var candidates: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if token.count >= 2, !stopwords.contains(token), containsHan(token) {
                candidates.append(token)
            }
            return true
        }
        return candidates.last
    }

    private func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}

// MARK: - Translation bridge

/// Bridges Coordinator → Apple Translation. The host SwiftUI view exists so
/// TranslationSession has a real view lifecycle. The actual Translation
/// call is dispatched through the host; the host calls `run(session:request:)`
/// on the bridge model, which forwards the response back to the coordinator.
final class LinguaTypeTranslationBridgeModel: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id: UInt64
        let kind: LearningCoordinator.Kind
        let phrase: String
        let vocabulary: String
        let configuration: TranslationSession.Configuration
    }

    @Published private(set) var request: Request?
    private weak var coordinator: LearningCoordinator?
    private var serial: UInt64 = 0

    init(coordinator: LearningCoordinator) {
        self.coordinator = coordinator
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        request = nil
    }

    func submitJob(kind: LearningCoordinator.Kind,
                   phrase: String,
                   vocabulary: String,
                   sourceLanguageID: String,
                   targetLanguageID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        serial &+= 1
        request = Request(
            id: serial,
            kind: kind,
            phrase: phrase,
            vocabulary: vocabulary,
            configuration: TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceLanguageID),
                target: Locale.Language(identifier: targetLanguageID)
            )
        )
    }

    func run(session: TranslationSession, request: Request) async {
        guard await isCurrent(request.id) else { return }
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard await isCurrent(request.id) else { return }
            let response = try await session.translate(request.phrase)
            try Task.checkCancellation()
            await MainActor.run { [weak coordinator] in
                coordinator?.translationCompleted(response.targetText, request.kind)
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run { [weak coordinator] in
                coordinator?.translationFailed(error.localizedDescription, request.kind)
            }
        }
    }

    private func isCurrent(_ id: UInt64) async -> Bool {
        await MainActor.run { [weak self] in self?.request?.id == id }
    }
}

private struct LinguaTypeTranslationBridgeView: View {
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

// MARK: - Exposure store

private final class LinguaTypeExposureStore {
    static let shared = LinguaTypeExposureStore()

    private struct Entry: Codable {
        var source: String
        var target: String
        var language: String
        var count: Int
        var firstSeen: TimeInterval
        var lastSeen: TimeInterval
    }

    private let queue = DispatchQueue(label: "io.linguatype.companion.exposure-store", qos: .utility)
    private let fileURL: URL
    private var entries: [String: Entry] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("LinguaType", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("learning-exposure.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    func record(source: String, target: String, language: String) {
        guard !source.isEmpty, !target.isEmpty else { return }
        queue.async { [self] in
            let now = Date().timeIntervalSince1970
            let key = "\(language)\u{1f}\(source)\u{1f}\(target)"
            if var entry = entries[key] {
                if now - entry.lastSeen >= 30 {
                    entry.count += 1
                    entry.lastSeen = now
                    entries[key] = entry
                }
            } else {
                entries[key] = Entry(source: source,
                                     target: target,
                                     language: language,
                                     count: 1,
                                     firstSeen: now,
                                     lastSeen: now)
            }
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}