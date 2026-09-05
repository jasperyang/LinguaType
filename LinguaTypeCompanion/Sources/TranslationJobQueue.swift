import Foundation

enum TranslationPurpose: Equatable {
    case phrase(language: LearningLanguage)
    case term(cardID: Int, language: LearningLanguage)
    case definition(cardID: Int, language: LearningLanguage, senseIndex: Int)

    fileprivate var priority: Int {
        switch self {
        case .phrase: return 0
        case .term: return 1
        case .definition: return 2
        }
    }
}

struct TranslationJob: Equatable {
    let generation: UInt64
    let purpose: TranslationPurpose
    let text: String
    let sourceLanguageID: String
    let targetLanguageID: String
}

struct TranslationJobQueue {
    private struct QueuedJob {
        let sequence: UInt64
        let job: TranslationJob
    }

    private var items: [QueuedJob] = []
    private var nextSequence: UInt64 = 0

    var isEmpty: Bool { items.isEmpty }

    mutating func enqueue(_ job: TranslationJob) {
        nextSequence &+= 1
        items.append(QueuedJob(sequence: nextSequence, job: job))
    }

    mutating func popNext() -> TranslationJob? {
        guard let index = items.indices.min(by: { left, right in
            let lhs = items[left]
            let rhs = items[right]
            if lhs.job.purpose.priority == rhs.job.purpose.priority {
                return lhs.sequence < rhs.sequence
            }
            return lhs.job.purpose.priority < rhs.job.purpose.priority
        }) else { return nil }
        return items.remove(at: index).job
    }

    mutating func discard(olderThan generation: UInt64) {
        items.removeAll { $0.job.generation < generation }
    }

    mutating func removeAll() {
        items.removeAll()
    }
}
