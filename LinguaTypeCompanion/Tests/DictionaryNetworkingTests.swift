import Foundation

private final class StubDictionaryURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Int) -> (Int, Data))?
    static var attempts = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.attempts += 1
        let result = Self.handler?(request, Self.attempts) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct StubDictionaryProvider: DictionaryProvider {
    let id: String
    func makeRequest(for query: DictionaryQuery) throws -> URLRequest {
        URLRequest(url: URL(string: "https://\(id).dictionary.invalid/\(query.term)")!)
    }
    func decode(_ data: Data, response: HTTPURLResponse, query: DictionaryQuery) throws -> DictionaryEntry? {
        guard (200..<300).contains(response.statusCode) else { throw DictionaryProviderError.malformedResponse }
        return try JSONDecoder().decode(DictionaryEntry.self, from: data)
    }
}

enum DictionaryNetworkingTests {
    static func run() {
        testConcurrencyLimiter()
        testRetryAndPrivacy()
        testProviderFallback()
    }

    private static func testConcurrencyLimiter() {
        let limiter = DictionaryRequestLimiter(globalLimit: 4, providerLimit: 2)
        var started: [String] = []
        for label in ["a1", "a2", "a3", "b1", "b2", "b3"] {
            limiter.enqueue(providerID: String(label.prefix(1))) { started.append(label) }
        }
        Test.expect(started == ["a1", "a2", "b1", "b2"], "dictionary networking limits four global and two per provider")

        limiter.finish(providerID: "a")
        Test.expect(started.last == "a3", "dictionary networking starts the next eligible provider request")
        limiter.finish(providerID: "b")
        Test.expect(started.last == "b3", "dictionary networking drains queued requests fairly")
    }

    private static func testRetryAndPrivacy() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubDictionaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("network-cache-\(UUID().uuidString).json")
        let cache = DictionaryCache(fileURL: cacheURL)
        var logs: [String] = []
        let service = DictionaryLookupService(session: session, cache: cache, logger: { logs.append($0) })
        let expected = DictionaryEntry(term: "suit", partOfSpeech: "verb", senses: ["合适"], ipa: "/suːt/", kana: nil, providerID: "stub")
        let data = try! JSONEncoder().encode(expected)
        StubDictionaryURLProtocol.attempts = 0
        StubDictionaryURLProtocol.handler = { _, attempt in attempt == 1 ? (500, Data()) : (200, data) }

        let semaphore = DispatchSemaphore(value: 0)
        var received: DictionaryEntry?
        service.lookup(provider: StubDictionaryProvider(id: "stub"), query: DictionaryQuery(term: "suit", language: .english)!) { result in
            received = try? result.get()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)

        Test.expect(StubDictionaryURLProtocol.attempts == 2, "dictionary networking retries one server failure")
        Test.expect(received == expected, "dictionary networking returns the provider entry")
        Test.expect(logs.allSatisfy { !$0.contains("suit") }, "dictionary diagnostics never log query terms")
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private static func testProviderFallback() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubDictionaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("fallback-cache-\(UUID().uuidString).json")
        let expected = DictionaryEntry(term: "suit", partOfSpeech: "动词", senses: ["合适"], ipa: "/suːt/", kana: nil, providerID: "fallback")
        let data = try! JSONEncoder().encode(expected)
        StubDictionaryURLProtocol.attempts = 0
        StubDictionaryURLProtocol.handler = { request, _ in
            request.url?.host?.hasPrefix("primary") == true ? (500, Data()) : (200, data)
        }

        let service = DictionaryLookupService(
            session: session,
            cache: DictionaryCache(fileURL: cacheURL),
            logger: { _ in }
        )
        let semaphore = DispatchSemaphore(value: 0)
        var received: DictionaryEntry?
        service.lookup(
            providers: [StubDictionaryProvider(id: "primary"), StubDictionaryProvider(id: "fallback")],
            query: DictionaryQuery(term: "suit", language: .english)!
        ) { result in
            received = try? result.get()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)

        Test.expect(StubDictionaryURLProtocol.attempts == 3, "dictionary provider fallback runs after one primary retry")
        Test.expect(received == expected, "dictionary provider fallback returns the backup entry")
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
