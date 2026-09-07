import Foundation

enum LanguageSelectionTests {
    static func run() {
        var selection = LanguageSelection(primary: .french, selected: [.english])
        Test.expect(
            selection.selected == [.french, .english],
            "primary language is always selected"
        )
        Test.expect(
            selection.orderedLanguages == [.french, .english],
            "primary language sorts before references"
        )

        selection.setSelected(.french, enabled: false)
        Test.expect(
            selection.selected.contains(.french),
            "primary language cannot be unchecked"
        )

        selection.setPrimary(.japanese)
        Test.expect(
            selection.primary == .japanese && selection.selected.contains(.japanese),
            "choosing a primary language also selects it"
        )
        Test.expect(
            selection.orderedLanguages == [.japanese, .french, .english],
            "references retain stable product order after primary language"
        )

        let suiteName = "LanguageSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        Test.expect(
            LinguaTypePreferences.languageSelection(defaults: defaults) == .default,
            "language selection defaults to French plus all supported languages"
        )
        LinguaTypePreferences.setLanguageSelection(selection, defaults: defaults)
        Test.expect(
            LinguaTypePreferences.languageSelection(defaults: defaults) == selection,
            "language selection persists"
        )

        defaults.set("unknown", forKey: "LinguaType.primaryLanguage")
        defaults.set(["fr", "unknown"], forKey: "LinguaType.selectedLanguages")
        Test.expect(
            LinguaTypePreferences.languageSelection(defaults: defaults) == .default,
            "invalid persisted language values fall back safely"
        )

        Test.expect(
            LearningLanguage.displayOrder.map(\.shortCode) == ["FR", "EN", "JP"],
            "panel language codes are stable and flag-free"
        )
        Test.expect(
            LearningLanguage.displayOrder.map(\.nativeName) == ["Français", "English", "日本語"],
            "language picker exposes native language names"
        )
    }
}
