import Foundation

struct WiktionaryDictionaryProvider: DictionaryProvider {
    let language: DictionaryLanguage

    var id: String { language == .chinese ? "zh-wiktionary" : "fr-wiktionary" }

    init(language: DictionaryLanguage) {
        precondition(language == .chinese || language == .french)
        self.language = language
    }

    func makeRequest(for query: DictionaryQuery) throws -> URLRequest {
        guard query.language == language else { throw DictionaryProviderError.unsupportedLanguage }
        let host = language == .chinese ? "zh.wiktionary.org" : "fr.wiktionary.org"
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "prop", value: "text"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "page", value: query.term),
        ]
        guard let url = components.url else { throw DictionaryProviderError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("LinguaType/0.1 (+https://github.com/jasperyang/LinguaType)", forHTTPHeaderField: "User-Agent")
        return request
    }

    func decode(_ data: Data, response: HTTPURLResponse, query: DictionaryQuery) throws -> DictionaryEntry? {
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw DictionaryProviderError.malformedResponse }
        let result = try JSONDecoder().decode(ParseResponse.self, from: data)
        guard let html = result.parse?.text["*"] else { return nil }
        let senses = matches(#"<li[^>]*>(.*?)</li>"#, in: html)
            .map(cleanHTML)
            .filter { !$0.isEmpty }
        let ipa = matches(#"class=[\"']IPA[\"'][^>]*>(.*?)</span>"#, in: html)
            .map(cleanHTML)
            .first
        let headings = matches(#"<h[234][^>]*>(.*?)</h[234]>"#, in: html).map(cleanHTML)
        let partOfSpeech = headings.first { heading in
            ["名词", "动词", "形容词", "副词", "nom", "verbe", "adjectif", "adverbe"]
                .contains { heading.localizedCaseInsensitiveContains($0) }
        }
        let cleanSenses = Array(senses.prefix(3))
        guard !cleanSenses.isEmpty || ipa != nil else { return nil }
        return DictionaryEntry(
            term: query.term,
            partOfSpeech: partOfSpeech,
            senses: cleanSenses,
            ipa: ipa,
            kana: nil,
            providerID: id
        )
    }

    private struct ParseResponse: Decodable {
        let parse: Parse?
        struct Parse: Decodable { let text: [String: String] }
    }

    private func matches(_ pattern: String, in input: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: input) else { return nil }
            return String(input[capture])
        }
    }

    private func cleanHTML(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
