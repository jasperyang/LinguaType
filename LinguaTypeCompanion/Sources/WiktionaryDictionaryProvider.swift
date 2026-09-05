import Foundation

struct WiktionaryDictionaryProvider: DictionaryProvider {
    let language: DictionaryLanguage

    var id: String {
        switch language {
        case .chinese: return "zh-wiktionary"
        case .french: return "fr-wiktionary"
        case .english: return "en-wiktionary"
        case .japanese: preconditionFailure("Japanese uses the JMdict-backed provider")
        }
    }

    init(language: DictionaryLanguage) {
        precondition(language != .japanese)
        self.language = language
    }

    func makeRequest(for query: DictionaryQuery) throws -> URLRequest {
        guard query.language == language else { throw DictionaryProviderError.unsupportedLanguage }
        let host: String
        switch language {
        case .chinese: host = "zh.wiktionary.org"
        case .french: host = "fr.wiktionary.org"
        case .english: host = "en.wiktionary.org"
        case .japanese: throw DictionaryProviderError.unsupportedLanguage
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "prop", value: "wikitext"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "redirects", value: "1"),
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
        guard let wikitext = result.parse?.wikitext["*"] else { return nil }
        let section = languageSection(in: wikitext)
        let senses = section.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("# ") }
            .map { cleanWikitext(String($0.dropFirst(2))) }
            .filter { !$0.isEmpty }
        let ipa: String?
        switch language {
        case .french:
            ipa = matches(#"\{\{pron\|([^|}]*)\|fr(?:\|[^}]*)?\}\}"#, in: section).first.map { "/\($0)/" }
        case .english:
            ipa = matches(#"\{\{IPA\|en\|(/[^|}]+/)(?:\|[^}]*)?\}\}"#, in: section).first
        case .chinese, .japanese:
            ipa = nil
        }
        let partOfSpeech = partOfSpeech(in: section)
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
        struct Parse: Decodable { let wikitext: [String: String] }
    }

    private func languageSection(in wikitext: String) -> String {
        let lines = wikitext.components(separatedBy: .newlines)
        var collecting = false
        var result: [String] = []
        for line in lines {
            let heading = line.trimmingCharacters(in: .whitespaces)
            if isLevelTwoHeading(heading) {
                if collecting { break }
                switch language {
                case .chinese:
                    collecting = heading.contains("漢語") || heading.contains("汉语")
                case .french:
                    collecting = heading.contains("{{langue|fr}}")
                case .english:
                    collecting = heading.localizedCaseInsensitiveContains("English")
                case .japanese:
                    collecting = false
                }
                continue
            }
            if collecting { result.append(line) }
        }
        return result.joined(separator: "\n")
    }

    private func isLevelTwoHeading(_ line: String) -> Bool {
        line.hasPrefix("==") && !line.hasPrefix("===")
            && line.hasSuffix("==") && !line.hasSuffix("===")
    }

    private func partOfSpeech(in section: String) -> String? {
        let candidates: [(needles: [String], label: String)]
        switch language {
        case .chinese:
            candidates = [(["動詞", "动词"], "动词"), (["名詞", "名词"], "名词"), (["形容詞", "形容词"], "形容词"), (["副詞", "副词"], "副词")]
        case .french:
            candidates = [(["|verbe|"], "动词"), (["|nom|"], "名词"), (["|adjectif|"], "形容词"), (["|adverbe|"], "副词")]
        case .english:
            candidates = [(["===Verb==="], "动词"), (["===Noun==="], "名词"), (["===Adjective==="], "形容词"), (["===Adverb==="], "副词")]
        case .japanese:
            candidates = []
        }
        return candidates.first { candidate in
            candidate.needles.contains { section.localizedCaseInsensitiveContains($0) }
        }?.label
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

    private func cleanWikitext(_ value: String) -> String {
        var cleaned = value
        cleaned = replace(#"\[\[[^\]|]+\|([^\]]+)\]\]"#, in: cleaned, withCapture: 1)
        cleaned = replace(#"\[\[([^\]]+)\]\]"#, in: cleaned, withCapture: 1)
        while cleaned.range(of: #"\{\{[^{}]*\}\}"#, options: .regularExpression) != nil {
            cleaned = cleaned.replacingOccurrences(of: #"\{\{[^{}]*\}\}"#, with: "", options: .regularExpression)
        }
        return cleaned
            .replacingOccurrences(of: "'''", with: "")
            .replacingOccurrences(of: "''", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replace(_ pattern: String, in input: String, withCapture captureIndex: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        var output = input
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        for match in matches.reversed() {
            guard let whole = Range(match.range(at: 0), in: output),
                  let capture = Range(match.range(at: captureIndex), in: output) else { continue }
            output.replaceSubrange(whole, with: output[capture])
        }
        return output
    }
}
