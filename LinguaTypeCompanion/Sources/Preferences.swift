import Foundation

/// User-tweakable preferences for the Companion. Persisted via UserDefaults
/// under the same keys the IMK variant wrote, so users who previously set
/// languages with configure-languages.sh don't have to do it twice.
enum LinguaTypePreferences {
    private static let enabledKey = "LinguaType.learningEnabled"
    private static let dictionaryLookupKey = "LinguaType.dictionaryLookupEnabled"

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

    // Temporary compatibility for the existing two-row coordinator. These
    // disappear when the fixed three-language pipeline lands.
    static var primaryLanguageID: String { LearningLanguage.french.rawValue }
    static var secondaryLanguageID: String? { LearningLanguage.english.rawValue }

}
