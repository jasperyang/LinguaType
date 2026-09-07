import Cocoa

protocol TranslationClipboardWriting: AnyObject {
    func write(_ text: String)
}

final class SystemTranslationClipboard: TranslationClipboardWriting {
    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct TranslationCopyService {
    private let clipboard: TranslationClipboardWriting

    init(clipboard: TranslationClipboardWriting = SystemTranslationClipboard()) {
        self.clipboard = clipboard
    }

    @discardableResult
    func copy(_ translation: PhraseTranslation) -> Bool {
        guard translation.status == .success,
              let text = translation.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        clipboard.write(text)
        return true
    }
}
