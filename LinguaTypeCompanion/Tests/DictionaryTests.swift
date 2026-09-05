import Foundation

enum DictionaryTests {
    static func run() {
        testQueryValidationAndPrivacy()
        testProviderParsing()
        testCacheExpiry()
        testJapaneseRomanization()
    }

    private static func testQueryValidationAndPrivacy() {
        let query = DictionaryQuery(term: "  take a walk。 ", language: .english)
        Test.expect(query?.term == "take a walk", "dictionary query trims surrounding punctuation")
        Test.expect(
            DictionaryQuery(term: String(repeating: "词", count: 33), language: .chinese) == nil,
            "dictionary query rejects more than 32 characters"
        )

        let phrase = "今天的天气很适合散步"
        let providersAndQueries: [(any DictionaryProvider, DictionaryQuery)] = [
            (WiktionaryDictionaryProvider(language: .chinese), DictionaryQuery(term: "适合", language: .chinese)!),
            (WiktionaryDictionaryProvider(language: .french), DictionaryQuery(term: "convenir", language: .french)!),
            (EnglishDictionaryProvider(), DictionaryQuery(term: "suit", language: .english)!),
            (JapaneseDictionaryProvider(), DictionaryQuery(term: "適する", language: .japanese)!),
        ]
        let isPrivate = providersAndQueries.allSatisfy { provider, query in
            guard let request = try? provider.makeRequest(for: query) else { return false }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return request.url?.absoluteString.contains(phrase) != true && !body.contains(phrase)
        }
        Test.expect(isPrivate, "dictionary requests contain isolated terms rather than the committed phrase")
    }

    private static func testProviderParsing() {
        let englishJSON = #"[{"word":"suit","phonetic":"/suːt/","meanings":[{"partOfSpeech":"verb","definitions":[{"definition":"be convenient for"},{"definition":"meet the needs of"}]}]}]"#.data(using: .utf8)!
        let english = EnglishDictionaryProvider()
        let enQuery = DictionaryQuery(term: "suit", language: .english)!
        let enEntry = try? english.decode(englishJSON, response: response(for: try! english.makeRequest(for: enQuery)), query: enQuery)
        Test.expect(enEntry?.ipa == "/suːt/", "English dictionary returns IPA")
        Test.expect(enEntry?.senses == ["be convenient for", "meet the needs of"], "English dictionary returns multiple senses")

        let japaneseJSON = #"{"words":[{"reading":{"kana":"てきする","kanji":"適する","furigana":"[適|てき]する"},"common":true,"senses":[{"glosses":["to fit","to suit"],"pos":["verb"],"language":"English"}],"pitch":[]}],"kanji":[]}"#.data(using: .utf8)!
        let japanese = JapaneseDictionaryProvider()
        let jaQuery = DictionaryQuery(term: "適する", language: .japanese)!
        let jaEntry = try? japanese.decode(japaneseJSON, response: response(for: try! japanese.makeRequest(for: jaQuery)), query: jaQuery)
        Test.expect(jaEntry?.kana == "てきする", "Japanese dictionary returns kana")
        Test.expect(jaEntry?.senses == ["to fit", "to suit"], "Japanese dictionary returns multiple senses")

        let wikiJSON = #"{"parse":{"text":{"*":"<h3><span>动词</span></h3><p><span class=\"IPA\">/ʂʐ̩⁵¹ xɤ³⁵/</span></p><ol><li>合适；符合条件。</li><li>适宜用于某种情况。</li></ol>"}}}"#.data(using: .utf8)!
        let wiki = WiktionaryDictionaryProvider(language: .chinese)
        let zhQuery = DictionaryQuery(term: "适合", language: .chinese)!
        let zhEntry = try? wiki.decode(wikiJSON, response: response(for: try! wiki.makeRequest(for: zhQuery)), query: zhQuery)
        Test.expect(zhEntry?.senses == ["合适；符合条件。", "适宜用于某种情况。"], "Wiktionary returns clean Chinese senses")
    }

    private static func testCacheExpiry() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("linguat-cache-\(UUID().uuidString).json")
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = DictionaryCache(fileURL: fileURL, now: { now })
        let key = DictionaryCache.Key(providerID: "english", query: DictionaryQuery(term: "suit", language: .english)!)
        let entry = DictionaryEntry(term: "suit", partOfSpeech: "verb", senses: ["合适"], ipa: "/suːt/", kana: nil, providerID: "english")
        cache.store(entry, for: key)
        now.addTimeInterval(29 * 86_400)
        Test.expect(cache.entry(for: key) == entry, "successful dictionary cache survives for 29 days")
        now.addTimeInterval(2 * 86_400)
        Test.expect(cache.entry(for: key) == nil, "successful dictionary cache expires after 30 days")
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func testJapaneseRomanization() {
        Test.expect(RomajiTransliterator.romanize(kana: "てきする") == "tekisuru", "Japanese kana is romanized locally")
    }

    private static func response(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}
