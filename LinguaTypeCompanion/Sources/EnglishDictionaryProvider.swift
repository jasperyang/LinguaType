import Foundation

struct EnglishDictionaryProvider: DictionaryProvider {
    let id = "free-dictionary"

    func makeRequest(for query: DictionaryQuery) throws -> URLRequest {
        guard query.language == .english else { throw DictionaryProviderError.unsupportedLanguage }
        guard let encoded = query.term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            throw DictionaryProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        return request
    }

    func decode(_ data: Data, response: HTTPURLResponse, query: DictionaryQuery) throws -> DictionaryEntry? {
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw DictionaryProviderError.malformedResponse }
        let records = try JSONDecoder().decode([Record].self, from: data)
        guard let record = records.first else { return nil }
        let firstMeaning = record.meanings.first
        let senses = Array(record.meanings.flatMap(\.definitions).map(\.definition).filter { !$0.isEmpty }.prefix(3))
        guard !senses.isEmpty || record.phonetic != nil else { return nil }
        return DictionaryEntry(
            term: record.word,
            partOfSpeech: firstMeaning?.partOfSpeech,
            senses: senses,
            ipa: record.phonetic ?? record.phonetics?.compactMap(\.text).first,
            kana: nil,
            providerID: id
        )
    }

    private struct Record: Decodable {
        let word: String
        let phonetic: String?
        let phonetics: [Phonetic]?
        let meanings: [Meaning]
    }
    private struct Phonetic: Decodable { let text: String? }
    private struct Meaning: Decodable {
        let partOfSpeech: String?
        let definitions: [Definition]
    }
    private struct Definition: Decodable { let definition: String }
}
