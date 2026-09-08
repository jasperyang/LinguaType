import Foundation

/// User-tweakable Companion switches persisted via UserDefaults.
enum LinguaTypePreferences {
    private static let enabledKey = "LinguaType.learningEnabled"
    private static let dictionaryLookupKey = "LinguaType.dictionaryLookupEnabled"
    private static let primaryLanguageKey = "LinguaType.primaryLanguage"
    private static let selectedLanguagesKey = "LinguaType.selectedLanguages"
    private static let learningModeKey = "LinguaType.learningMode"
    private static let learnerLevelPrefix = "LinguaType.learnerLevel."

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    static var isDictionaryLookupEnabled: Bool {
        if UserDefaults.standard.object(forKey: dictionaryLookupKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: dictionaryLookupKey)
    }

    static func setDictionaryLookupEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: dictionaryLookupKey)
    }

    static func languageSelection(defaults: UserDefaults = .standard) -> LanguageSelection {
        guard let primaryRaw = defaults.string(forKey: primaryLanguageKey) else {
            return .default
        }
        guard let primary = LearningLanguage(rawValue: primaryRaw) else {
            return .default
        }
        let rawValues = defaults.stringArray(forKey: selectedLanguagesKey)
            ?? LearningLanguage.displayOrder.map(\.rawValue)
        let selected = Set(rawValues.compactMap(LearningLanguage.init(rawValue:)))
        return LanguageSelection(primary: primary, selected: selected)
    }

    static func setLanguageSelection(
        _ selection: LanguageSelection,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(selection.primary.rawValue, forKey: primaryLanguageKey)
        defaults.set(
            LearningLanguage.displayOrder
                .filter(selection.selected.contains)
                .map(\.rawValue),
            forKey: selectedLanguagesKey
        )
    }

    static func learningMode(defaults: UserDefaults = .standard) -> LearningMode {
        defaults.string(forKey: learningModeKey)
            .flatMap(LearningMode.init(rawValue:))
            ?? .minimal
    }

    static func setLearningMode(
        _ mode: LearningMode,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: learningModeKey)
    }

    static func learnerLevel(
        for language: LearningLanguage,
        defaults: UserDefaults = .standard
    ) -> LearnerLevel {
        defaults.string(forKey: learnerLevelPrefix + language.rawValue)
            .flatMap(LearnerLevel.init(rawValue:))
            ?? .beginner
    }

    static func setLearnerLevel(
        _ level: LearnerLevel,
        for language: LearningLanguage,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(level.rawValue, forKey: learnerLevelPrefix + language.rawValue)
    }
}
