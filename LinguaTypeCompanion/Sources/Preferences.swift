import Foundation

/// User-tweakable Companion switches persisted via UserDefaults.
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

}
