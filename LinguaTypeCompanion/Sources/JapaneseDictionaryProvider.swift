import Foundation

struct JapaneseDictionaryProvider: DictionaryProvider {
    let id = "jotoba-jmdict"

    func makeRequest(for query: DictionaryQuery) throws -> URLRequest {
        guard query.language == .japanese else { throw DictionaryProviderError.unsupportedLanguage }
        guard let url = URL(string: "https://jotoba.de/api/search/words") else {
            throw DictionaryProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LinguaType/0.1 (+https://github.com/jasperyang/LinguaType)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query.term,
            "language": "English",
            "no_english": false,
        ])
        return request
    }

    func decode(_ data: Data, response: HTTPURLResponse, query: DictionaryQuery) throws -> DictionaryEntry? {
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 404 { return nil }
            throw DictionaryProviderError.malformedResponse
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard let word = result.words.first else { return nil }
        let senses = Array(word.senses.flatMap(\.glosses).filter { !$0.isEmpty }.prefix(3))
        return DictionaryEntry(
            term: word.reading.kanji ?? word.reading.kana,
            partOfSpeech: word.senses.first?.pos.compactMap(\.label).first,
            senses: senses,
            ipa: nil,
            kana: word.reading.kana,
            providerID: id
        )
    }

    private struct Response: Decodable { let words: [Word] }
    private struct Word: Decodable {
        let reading: Reading
        let senses: [Sense]
    }
    private struct Reading: Decodable {
        let kana: String
        let kanji: String?
    }
    private struct Sense: Decodable {
        let glosses: [String]
        let pos: [PartOfSpeech]
    }
    private struct PartOfSpeech: Decodable {
        let label: String?

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                label = Self.localized(value)
                return
            }
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            label = container.allKeys.first.map { Self.localized($0.stringValue) }
        }

        private static func localized(_ value: String) -> String {
            switch value.lowercased() {
            case let name where name.contains("verb"): return "动词"
            case let name where name.contains("noun"): return "名词"
            case let name where name.contains("adjective"): return "形容词"
            case let name where name.contains("adverb"): return "副词"
            default: return value
            }
        }
    }
    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
