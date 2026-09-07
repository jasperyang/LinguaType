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

    static func loading(sourcePhrase: String) -> LearningDisplayState {
        LearningDisplayState(
            sourcePhrase: sourcePhrase,
            phraseTranslations: LearningLanguage.displayOrder.map {
                PhraseTranslation(language: $0, text: nil, status: .loading)
            },
            vocabularyCards: [],
            phase: .translatingPhrase
        )
    }
}
