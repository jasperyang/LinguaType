import Foundation

final class DictionaryCache {
    struct Key: Hashable, Codable {
        let providerID: String
        let query: DictionaryQuery

        var storageKey: String { "\(providerID)|\(query.language.rawValue)|\(query.term.lowercased())" }
    }

    private struct Record: Codable {
        let entry: DictionaryEntry
        let storedAt: Date
    }

    private struct Document: Codable {
        let version: Int
        var records: [String: Record]
    }

    private let fileURL: URL
    private let now: () -> Date
    private var document: Document
    private let successTTL: TimeInterval = 30 * 86_400

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinguaType/dictionary-cache-v1.json")
        self.now = now
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(Document.self, from: data),
           decoded.version == 1 {
            document = decoded
        } else {
            document = Document(version: 1, records: [:])
        }
    }

    func entry(for key: Key) -> DictionaryEntry? {
        guard let record = document.records[key.storageKey] else { return nil }
        guard now().timeIntervalSince(record.storedAt) <= successTTL else {
            document.records.removeValue(forKey: key.storageKey)
            persist()
            return nil
        }
        return record.entry
    }

    func store(_ entry: DictionaryEntry, for key: Key) {
        document.records[key.storageKey] = Record(entry: entry, storedAt: now())
        persist()
    }

    func clear() {
        document.records.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
