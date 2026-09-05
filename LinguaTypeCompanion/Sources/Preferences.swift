import Foundation

/// User-tweakable preferences for the Companion. Persisted via UserDefaults
/// under the same keys the IMK variant wrote, so users who previously set
/// languages with configure-languages.sh don't have to do it twice.
enum LinguaTypePreferences {
    private static let primaryKey = "LinguaType.primaryLanguage"
    private static let secondaryKey = "LinguaType.secondaryLanguage"
    private static let enabledKey = "LinguaType.learningEnabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var primaryLanguageID: String {
        let value = UserDefaults.standard.string(forKey: primaryKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "fr"
    }

    static var secondaryLanguageID: String? {
        let value = UserDefaults.standard.string(forKey: secondaryKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty, value.lowercased() != "off" { return value }
        return "en"
    }

    private static let cycleOrder = ["fr", "en", "ja", "de", "es", "ko"]

    static func cyclePrimary() {
        let cur = primaryLanguageID
        let next = next(after: cur, in: cycleOrder)
        UserDefaults.standard.set(next, forKey: primaryKey)
    }

    static func cycleSecondary() {
        let cur = secondaryLanguageID ?? "en"
        let next = next(after: cur, in: cycleOrder + ["off"])
        if next == "off" {
            UserDefaults.standard.set("off", forKey: secondaryKey)
        } else {
            UserDefaults.standard.set(next, forKey: secondaryKey)
        }
    }

    private static func next(after current: String, in order: [String]) -> String {
        guard let idx = order.firstIndex(of: current) else { return order[0] }
        return order[(idx + 1) % order.count]
    }
}