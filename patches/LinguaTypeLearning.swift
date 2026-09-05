import AppKit
import Carbon.HIToolbox
import Foundation
import NaturalLanguage
import SwiftUI
import Translation

// LinguaType's learning layer is intentionally downstream of Rime candidate
// production. Translation and persistence never participate in the keyDown ->
// librime -> candidate path.

enum LinguaTypeLearningPreferences {
    private static let primaryKey = "LinguaType.primaryLanguage"
    private static let secondaryKey = "LinguaType.secondaryLanguage"
    private static let enabledKey = "LinguaType.learningEnabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var primaryLanguageID: String {
        let value = UserDefaults.standard.string(forKey: primaryKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "fr"
    }

    static var secondaryLanguageID: String? {
        let value = UserDefaults.standard.string(forKey: secondaryKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty, value.lowercased() != "off" { return value }
        return "en"
    }
}

enum LinguaTypeLearningJobKind: Equatable {
    case phrase
    case vocabulary(String)
}

struct LinguaTypeLearningJob: Equatable {
    let generation: UInt64
    let sourceText: String
    let targetLanguageID: String
    let kind: LinguaTypeLearningJobKind
}

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

    private let queue = DispatchQueue(label: "io.linguatype.exposure-store", qos: .utility)
    private let fileURL: URL
    private var entries: [String: Entry] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("LinguaType", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
                                                  withIntermediateDirectories: true)
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
                // Fast repeated redraws of the same candidate are not separate exposures.
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

private final class LinguaTypeTranslationBridgeModel: ObservableObject {
    struct Request: Identifiable {
        let id: UInt64
        let configuration: TranslationSession.Configuration
        let job: LinguaTypeLearningJob
    }

    @Published private(set) var request: Request?
    private weak var coordinator: LinguaTypeLearningCoordinator?
    private var configuration: TranslationSession.Configuration?
    private var pair: (String, String)?
    private var serial: UInt64 = 0

    init(coordinator: LinguaTypeLearningCoordinator) {
        self.coordinator = coordinator
    }

    func submit(_ job: LinguaTypeLearningJob) {
        dispatchPrecondition(condition: .onQueue(.main))
        let source = "zh-Hans"
        let nextPair = (source, job.targetLanguageID)
        let nextConfiguration: TranslationSession.Configuration
        if pair?.0 == nextPair.0, pair?.1 == nextPair.1,
           var current = configuration {
            current.invalidate()
            nextConfiguration = current
        } else {
            pair = nextPair
            nextConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: source),
                target: Locale.Language(identifier: job.targetLanguageID)
            )
        }
        configuration = nextConfiguration
        serial &+= 1
        request = Request(id: serial, configuration: nextConfiguration, job: job)
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        request = nil
        configuration = nil
        pair = nil
        serial &+= 1
    }

    func run(session: TranslationSession, request: Request) async {
        guard await isCurrent(request.id) else { return }
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard await isCurrent(request.id) else { return }
            let response = try await session.translate(request.job.sourceText)
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

final class LinguaTypeLearningCoordinator {
    static let shared = LinguaTypeLearningCoordinator()

    private let panel: NSPanel
    private let visualEffect = NSVisualEffectView()
    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "语言学习")
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let vocabularyLabel = NSTextField(labelWithString: "")

    private lazy var bridgeModel = LinguaTypeTranslationBridgeModel(coordinator: self)
    private lazy var bridgeHost: NSHostingView<LinguaTypeTranslationBridgeView> = {
        let host = NSHostingView(rootView: LinguaTypeTranslationBridgeView(model: bridgeModel))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.alphaValue = 0.001
        return host
    }()

    private var generation: UInt64 = 0
    private var debounceWork: DispatchWorkItem?
    private var currentSource = ""
    private var currentAnchor = NSRect.zero
    private var queue: [LinguaTypeLearningJob] = []
    private var activeJob: LinguaTypeLearningJob?
    private var phraseTranslations: [String: String] = [:]
    private var vocabularyTranslations: [String: String] = [:]
    private var vocabularySource: String?
    private var cache: [String: String] = [:]

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 126),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 9
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = visualEffect

        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        for label in [primaryLabel, secondaryLabel, vocabularyLabel] {
            label.font = .systemFont(ofSize: 12.5, weight: .regular)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        vocabularyLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        vocabularyLabel.textColor = .secondaryLabelColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(primaryLabel)
        stack.addArrangedSubview(secondaryLabel)
        stack.addArrangedSubview(vocabularyLabel)
        visualEffect.addSubview(stack)
        visualEffect.addSubview(bridgeHost)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            bridgeHost.widthAnchor.constraint(equalToConstant: 1),
            bridgeHost.heightAnchor.constraint(equalToConstant: 1),
            bridgeHost.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            bridgeHost.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])
    }

    func candidateDidChange(text: String?,
                            anchor: NSRect,
                            presentation: CandidatePresentationMode) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard presentation == .caret,
              LinguaTypeLearningPreferences.isEnabled,
              !IsSecureEventInputEnabled(),
              let text = normalized(text),
              containsHan(text) else {
            hide()
            return
        }

        currentAnchor = anchor
        if text == currentSource, panel.isVisible {
            positionPanel(anchor: anchor)
            return
        }

        generation &+= 1
        debounceWork?.cancel()
        bridgeModel.cancel()
        activeJob = nil
        queue.removeAll()
        currentSource = text
        phraseTranslations.removeAll()
        vocabularyTranslations.removeAll()
        vocabularySource = extractVocabulary(from: text)
        renderLoading()
        positionPanel(anchor: anchor)
        panel.orderFrontRegardless()

        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected,
                  !IsSecureEventInputEnabled(),
                  self.currentSource == text else { return }
            self.prepareJobs(generation: expected)
            self.beginNextJob()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    func hide() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        debounceWork?.cancel()
        debounceWork = nil
        bridgeModel.cancel()
        activeJob = nil
        queue.removeAll()
        currentSource = ""
        phraseTranslations.removeAll()
        vocabularyTranslations.removeAll()
        vocabularySource = nil
        panel.orderOut(nil)
    }

    fileprivate func translationCompleted(_ targetText: String,
                                           job: LinguaTypeLearningJob) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard job.generation == generation,
              currentSource == sourcePhrase(for: job),
              activeJob == job else { return }
        activeJob = nil
        let cleaned = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        cache[cacheKey(job)] = cleaned
        switch job.kind {
        case .phrase:
            phraseTranslations[job.targetLanguageID] = cleaned
        case let .vocabulary(source):
            vocabularyTranslations[job.targetLanguageID] = cleaned
            LinguaTypeExposureStore.shared.record(source: source,
                                                  target: cleaned,
                                                  language: job.targetLanguageID)
        }
        renderCurrent()
        beginNextJob()
    }

    fileprivate func translationFailed(_ message: String,
                                        job: LinguaTypeLearningJob) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard job.generation == generation, activeJob == job else { return }
        activeJob = nil
        switch job.kind {
        case .phrase:
            phraseTranslations[job.targetLanguageID] = "翻译模型未准备好"
        case .vocabulary:
            break
        }
        renderCurrent()
        beginNextJob()
    }

    private func prepareJobs(generation: UInt64) {
        let targets = uniqueTargets()
        queue = targets.map {
            LinguaTypeLearningJob(generation: generation,
                                  sourceText: currentSource,
                                  targetLanguageID: $0,
                                  kind: .phrase)
        }
        if let vocabularySource {
            queue.append(contentsOf: targets.map {
                LinguaTypeLearningJob(generation: generation,
                                      sourceText: vocabularySource,
                                      targetLanguageID: $0,
                                      kind: .vocabulary(vocabularySource))
            })
        }
    }

    private func beginNextJob() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeJob == nil, generation > 0 else { return }
        while !queue.isEmpty {
            let job = queue.removeFirst()
            guard job.generation == generation else { continue }
            if let cached = cache[cacheKey(job)] {
                switch job.kind {
                case .phrase:
                    phraseTranslations[job.targetLanguageID] = cached
                case .vocabulary:
                    vocabularyTranslations[job.targetLanguageID] = cached
                }
                renderCurrent()
                continue
            }
            activeJob = job
            bridgeModel.submit(job)
            return
        }
    }

    private func renderLoading() {
        let primary = LinguaTypeLearningPreferences.primaryLanguageID
        let secondary = LinguaTypeLearningPreferences.secondaryLanguageID
        primaryLabel.stringValue = "\(flag(for: primary))  ···"
        secondaryLabel.isHidden = secondary == nil
        secondaryLabel.stringValue = secondary.map { "\(flag(for: $0))  ···" } ?? ""
        if let vocabularySource {
            vocabularyLabel.isHidden = false
            vocabularyLabel.stringValue = "词汇  \(vocabularySource)  →  ···"
        } else {
            vocabularyLabel.isHidden = true
        }
    }

    private func renderCurrent() {
        let primary = LinguaTypeLearningPreferences.primaryLanguageID
        let secondary = LinguaTypeLearningPreferences.secondaryLanguageID
        primaryLabel.stringValue = "\(flag(for: primary))  \(phraseTranslations[primary] ?? "···")"
        secondaryLabel.isHidden = secondary == nil
        if let secondary {
            secondaryLabel.stringValue = "\(flag(for: secondary))  \(phraseTranslations[secondary] ?? "···")"
        }
        if let vocabularySource {
            let p = vocabularyTranslations[primary]
            let s = secondary.flatMap { vocabularyTranslations[$0] }
            let pieces = [p, s].compactMap { $0 }.filter { !$0.isEmpty }
            vocabularyLabel.isHidden = false
            vocabularyLabel.stringValue = pieces.isEmpty
                ? "词汇  \(vocabularySource)  →  ···"
                : "词汇  \(vocabularySource)  →  \(pieces.joined(separator: "  /  "))"
        } else {
            vocabularyLabel.isHidden = true
        }
    }

    private func uniqueTargets() -> [String] {
        var result: [String] = []
        for candidate in [LinguaTypeLearningPreferences.primaryLanguageID,
                          LinguaTypeLearningPreferences.secondaryLanguageID].compactMap({ $0 }) {
            if candidate.lowercased().hasPrefix("zh") { continue }
            if !result.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                result.append(candidate)
            }
        }
        return result
    }

    private func sourcePhrase(for job: LinguaTypeLearningJob) -> String {
        switch job.kind {
        case .phrase: return job.sourceText
        case .vocabulary: return currentSource
        }
    }

    private func cacheKey(_ job: LinguaTypeLearningJob) -> String {
        "\(job.targetLanguageID)\u{1f}\(job.sourceText)"
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2, value.count <= 120 else { return nil }
        return value
    }

    private func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
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

    private func flag(for language: String) -> String {
        let id = language.lowercased()
        if id.hasPrefix("fr") { return "🇫🇷" }
        if id.hasPrefix("en") { return "🇬🇧" }
        if id.hasPrefix("ja") { return "🇯🇵" }
        if id.hasPrefix("de") { return "🇩🇪" }
        if id.hasPrefix("es") { return "🇪🇸" }
        if id.hasPrefix("ko") { return "🇰🇷" }
        return "🌐"
    }

    private func positionPanel(anchor: NSRect) {
        let width: CGFloat = 460
        let height: CGFloat = vocabularySource == nil ? 98 : 126
        let visible = screen(for: anchor)?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.minX
        var y = anchor.minY - 54 - height
        if y < visible.minY + 6 {
            y = anchor.maxY + 54
        }
        x = min(max(x, visible.minX + 6), visible.maxX - width - 6)
        y = min(max(y, visible.minY + 6), visible.maxY - height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func screen(for rect: NSRect) -> NSScreen? {
        if let exact = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) { return exact }
        return NSScreen.main
    }
}
