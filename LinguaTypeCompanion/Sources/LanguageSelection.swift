import Foundation

struct LanguageSelection: Equatable {
    static let `default` = LanguageSelection(
        primary: .french,
        selected: Set(LearningLanguage.displayOrder)
    )

    private(set) var primary: LearningLanguage
    private(set) var selected: Set<LearningLanguage>

    init(primary: LearningLanguage, selected: Set<LearningLanguage>) {
        self.primary = primary
        self.selected = selected.union([primary])
    }

    var orderedLanguages: [LearningLanguage] {
        [primary] + LearningLanguage.displayOrder.filter {
            $0 != primary && selected.contains($0)
        }
    }

    mutating func setPrimary(_ language: LearningLanguage) {
        primary = language
        selected.insert(language)
    }

    mutating func setSelected(_ language: LearningLanguage, enabled: Bool) {
        guard enabled || language != primary else { return }
        if enabled {
            selected.insert(language)
        } else {
            selected.remove(language)
        }
    }
}
