import Foundation

private final class CapturingTranslationClipboard: TranslationClipboardWriting {
    var values: [String] = []
    func write(_ text: String) { values.append(text) }
}

enum TranslationClipboardTests {
    static func run() {
        let clipboard = CapturingTranslationClipboard()
        let service = TranslationCopyService(clipboard: clipboard)

        Test.expect(
            service.copy(PhraseTranslation(language: .french, text: "Bonjour", status: .success)),
            "successful translation can be copied"
        )
        Test.expect(
            clipboard.values == ["Bonjour"],
            "copy writes only the complete translation text"
        )
        Test.expect(
            !service.copy(PhraseTranslation(language: .english, text: nil, status: .loading)),
            "loading translation cannot be copied"
        )
        Test.expect(
            !service.copy(PhraseTranslation(language: .japanese, text: "失敗", status: .failure("未准备好"))),
            "failed translation cannot be copied"
        )
        Test.expect(
            clipboard.values == ["Bonjour"],
            "ineligible copy actions leave the clipboard unchanged"
        )
    }
}
