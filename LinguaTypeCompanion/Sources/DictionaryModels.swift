import Foundation

enum DictionaryLanguage: String, Codable, Hashable {
    case chinese = "zh"
    case french = "fr"
    case english = "en"
    case japanese = "ja"
}

struct DictionaryQuery: Hashable, Codable {
    let term: String
    let language: DictionaryLanguage

    init?(term: String, language: DictionaryLanguage) {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let normalized = term.trimmingCharacters(in: trimSet)
        guard !normalized.isEmpty, normalized.count <= 32 else { return nil }
        self.term = normalized
        self.language = language
    }
}

struct DictionaryEntry: Codable, Equatable {
    let term: String
    let partOfSpeech: String?
    let senses: [String]
    let ipa: String?
    let kana: String?
    let providerID: String
}

enum DictionaryProviderError: Error {
    case unsupportedLanguage
    case invalidURL
    case malformedResponse
}

protocol DictionaryProvider {
    var id: String { get }
    func makeRequest(for query: DictionaryQuery) throws -> URLRequest
    func decode(
        _ data: Data,
        response: HTTPURLResponse,
        query: DictionaryQuery
    ) throws -> DictionaryEntry?
}
