import Foundation

final class ReviewStore {
    private static let storageKey = "LinguaType.reviewItems"
    private static let intervalsInDays = [1, 3, 7, 14, 30]

    private let defaults: UserDefaults
    private(set) var items: [ReviewItem]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ReviewItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    func save(_ point: LearningPoint, now: Date) {
        guard !items.contains(where: { $0.point.id == point.id }) else { return }
        items.append(
            ReviewItem(
                id: UUID(),
                point: point,
                dueDate: dueDate(from: now, intervalIndex: 0),
                intervalIndex: 0,
                lastAnswerCorrect: nil
            )
        )
        persist()
    }

    func dueItems(now: Date) -> [ReviewItem] {
        items
            .filter { $0.dueDate <= now }
            .sorted { $0.dueDate < $1.dueDate }
    }

    func answer(itemID: UUID, isCorrect: Bool, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let intervalIndex: Int
        if isCorrect {
            intervalIndex = min(items[index].intervalIndex + 1, Self.intervalsInDays.count - 1)
        } else {
            intervalIndex = 0
        }
        items[index].intervalIndex = intervalIndex
        items[index].dueDate = dueDate(from: now, intervalIndex: intervalIndex)
        items[index].lastAnswerCorrect = isCorrect
        persist()
    }

    private func dueDate(from date: Date, intervalIndex: Int) -> Date {
        date.addingTimeInterval(TimeInterval(Self.intervalsInDays[intervalIndex] * 86_400))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
