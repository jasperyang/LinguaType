import Foundation

enum PrivacySafeLogTests {
    static func run() {
        let phrase = "你好今天天气"
        let message = PrivacySafeLog.committedText(characterCount: phrase.count)

        Test.expect(message.contains("characters=\(phrase.count)"), "commit diagnostics retain only the character count")
        Test.expect(!message.contains(phrase), "commit diagnostics never contain the user's phrase")
    }
}
