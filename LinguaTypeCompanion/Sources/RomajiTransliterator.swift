import Foundation

enum RomajiTransliterator {
    static func romanize(kana: String) -> String? {
        guard !kana.isEmpty else { return nil }
        let mutable = NSMutableString(string: kana)
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) else { return nil }
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let value = (mutable as String)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
