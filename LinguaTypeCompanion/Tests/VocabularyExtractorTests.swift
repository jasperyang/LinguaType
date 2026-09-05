import NaturalLanguage

enum VocabularyExtractorTests {
    static func run() {
        let extractor = VocabularyExtractor(exposureCount: { $0 == "天气" ? 4 : 0 })
        let selected = extractor.select(candidates: [
            VocabularyCandidate(word: "天气", lexicalClass: .noun, sourceOrder: 0),
            VocabularyCandidate(word: "适合", lexicalClass: .verb, sourceOrder: 1),
            VocabularyCandidate(word: "散步", lexicalClass: .verb, sourceOrder: 2),
            VocabularyCandidate(word: "公园", lexicalClass: .noun, sourceOrder: 3),
        ])
        Test.expect(
            selected.map(\.word) == ["适合", "散步", "公园"],
            "recently repeated vocabulary gives way to new content words"
        )

        let filtered = extractor.select(candidates: [
            VocabularyCandidate(word: "的", lexicalClass: nil, sourceOrder: 0),
            VocabularyCandidate(word: "然后", lexicalClass: .adverb, sourceOrder: 1),
            VocabularyCandidate(word: "散步", lexicalClass: .verb, sourceOrder: 2),
            VocabularyCandidate(word: "散步", lexicalClass: .verb, sourceOrder: 3),
        ])
        Test.expect(filtered.map(\.word) == ["散步"], "function words and duplicate words are filtered")

        let phraseWords = VocabularyExtractor().extract(from: "今天的天气很适合散步")
        Test.expect(
            phraseWords.map(\.word) == ["天气", "适合", "散步"],
            "Chinese tokenization extracts the three meaningful words in source order"
        )
    }
}
