import Foundation
import NaturalLanguage

struct VocabularyCandidate: Equatable {
    let word: String
    let lexicalClass: NLTag?
    let sourceOrder: Int
}

struct VocabularyExtractor {
    private let exposureCount: (String) -> Int
    private let stopwords: Set<String> = [
        "这个", "那个", "一下", "然后", "就是", "还是", "已经", "可以", "需要",
        "我们", "你们", "他们", "今天", "现在", "一个", "一些", "觉得", "如果", "因为",
        "的", "了", "着", "很", "也", "都", "在", "和", "与", "及", "是",
    ]

    init(exposureCount: @escaping (String) -> Int = { _ in 0 }) {
        self.exposureCount = exposureCount
    }

    func extract(from text: String) -> [VocabularyCandidate] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.simplifiedChinese)

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.simplifiedChinese, range: text.startIndex..<text.endIndex)

        var candidates: [VocabularyCandidate] = []
        var order = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            candidates.append(VocabularyCandidate(word: word, lexicalClass: tag, sourceOrder: order))
            order += 1
            return true
        }
        return select(candidates: candidates)
    }

    func select(candidates: [VocabularyCandidate]) -> [VocabularyCandidate] {
        var seen = Set<String>()
        let filtered = candidates.filter { candidate in
            guard candidate.word.count >= 2,
                  candidate.word.count <= 12,
                  !stopwords.contains(candidate.word),
                  containsHan(candidate.word),
                  seen.insert(candidate.word).inserted else {
                return false
            }
            return true
        }

        let ranked = filtered.sorted { left, right in
            let leftScore = score(left)
            let rightScore = score(right)
            if leftScore == rightScore { return left.sourceOrder < right.sourceOrder }
            return leftScore > rightScore
        }
        return Array(ranked.prefix(3)).sorted { $0.sourceOrder < $1.sourceOrder }
    }

    private func score(_ candidate: VocabularyCandidate) -> Int {
        let contentTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb]
        let contentScore = candidate.lexicalClass.map(contentTags.contains) == true ? 10 : 5
        let lengthScore = (2...4).contains(candidate.word.count) ? 4 : 0
        let repetitionPenalty = min(exposureCount(candidate.word), 5) * 3
        return contentScore + lengthScore - repetitionPenalty
    }

    private func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
