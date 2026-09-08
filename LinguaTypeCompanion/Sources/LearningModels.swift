import Foundation

enum LearningLanguage: String, CaseIterable, Codable, Equatable {
    case french = "fr"
    case english = "en"
    case japanese = "ja"

    static let displayOrder: [LearningLanguage] = [.french, .english, .japanese]

    var displayName: String {
        switch self {
        case .french: return "法语"
        case .english: return "英语"
        case .japanese: return "日语"
        }
    }

    var shortCode: String { rawValue.uppercased() == "JA" ? "JP" : rawValue.uppercased() }

    var nativeName: String {
        switch self {
        case .french: return "Français"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }

    var flag: String {
        switch self {
        case .french: return "🇫🇷"
        case .english: return "🇬🇧"
        case .japanese: return "🇯🇵"
        }
    }
}

enum RowStatus: Equatable {
    case loading
    case success
    case failure(String)
}

enum CardStatus: Equatable {
    case loading
    case partial
    case complete
    case unavailable(String)
}

enum LoadingPhase: Equatable {
    case translatingPhrase
    case loadingVocabulary
    case complete
}

enum LearningMode: String, Codable, Equatable {
    case minimal
    case deep
}

enum LearnerLevel: String, CaseIterable, Codable, Equatable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        switch self {
        case .beginner: return "入门"
        case .intermediate: return "中级"
        case .advanced: return "高级"
        }
    }
}

enum LearningPointKind: String, Codable, Equatable {
    case pattern
    case expression
    case translationDifference
}

struct SentenceMapPair: Codable, Equatable {
    var source: String
    var target: String
    var evidenceID: String
}

struct LearningExample: Codable, Equatable {
    var target: String
    var chineseMeaning: String
}

struct LearningPoint: Codable, Equatable, Identifiable {
    var id: String
    var language: LearningLanguage
    var kind: LearningPointKind
    var targetExpression: String
    var pronunciation: String?
    var chineseMeaning: String
    var pattern: String?
    var example: LearningExample?
    var evidenceID: String
}

struct WhyExplanation: Codable, Equatable {
    var title: String
    var body: String
    var evidenceID: String
}

struct MicroPractice: Codable, Equatable {
    var id: String
    var prompt: String
    var choices: [String]
    var correctChoice: String
    var successFeedback: String
    var evidenceID: String

    func isCorrect(choice: String) -> Bool {
        choice == correctChoice
    }
}

struct MicroLesson: Codable, Equatable {
    var primaryLanguage: LearningLanguage
    var mapPairs: [SentenceMapPair]
    var learningPoints: [LearningPoint]
    var explanation: WhyExplanation?
    var practice: MicroPractice?
    var reviewCandidates: [LearningPoint]
}

struct ReviewItem: Codable, Equatable, Identifiable {
    var id: UUID
    var point: LearningPoint
    var dueDate: Date
    var intervalIndex: Int
    var lastAnswerCorrect: Bool?
}

struct PhraseTranslation: Equatable {
    var language: LearningLanguage
    var text: String?
    var status: RowStatus
}

struct LocalizedTerm: Equatable {
    var language: LearningLanguage
    var term: String
    var ipa: String?
    var kana: String?
    var romanization: String?
}

struct VocabularyCard: Equatable {
    var source: String
    var partOfSpeech: String?
    var chineseSenses: [String]
    var contextualSense: String?
    var terms: [LocalizedTerm]
    var status: CardStatus

    static func loading(source: String) -> VocabularyCard {
        VocabularyCard(
            source: source,
            partOfSpeech: nil,
            chineseSenses: [],
            contextualSense: nil,
            terms: [],
            status: .loading
        )
    }
}

struct LearningDisplayState: Equatable {
    var sourcePhrase: String
    var phraseTranslations: [PhraseTranslation]
    var vocabularyCards: [VocabularyCard]
    var phase: LoadingPhase
    var lesson: MicroLesson? = nil

    static func loading(
        sourcePhrase: String,
        selection: LanguageSelection = .default
    ) -> LearningDisplayState {
        LearningDisplayState(
            sourcePhrase: sourcePhrase,
            phraseTranslations: selection.orderedLanguages.map {
                PhraseTranslation(language: $0, text: nil, status: .loading)
            },
            vocabularyCards: [],
            phase: .translatingPhrase,
            lesson: nil
        )
    }
}
